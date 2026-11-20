import Foundation
import InputBridge
import Network
import Security

/// One screen, no certificates: the app generates its own identity, finds peers on
/// the local network and asks the user a yes/no question when somebody wants control.
@MainActor
final class AppModel: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: String
        var name: String
        var address: String
        var fingerprint: String
        var port: UInt16
        var side: Side?
    }

    enum Side: String, CaseIterable, Identifiable {
        case left, right, above, below
        var id: String { rawValue }
        var label: String {
            switch self {
            case .left: return "Left"
            case .right: return "Right"
            case .above: return "Above"
            case .below: return "Below"
            }
        }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var status = "Starting…"
    @Published private(set) var connectedDevice: String?
    @Published private(set) var sharing = false
    @Published var allowControl = false {
        didSet { allowControl ? startListening() : stopListening() }
    }
    @Published var pendingRequest: PendingRequest?
    @Published var errorText = ""

    struct PendingRequest: Identifiable {
        let id = UUID()
        let name: String
        let fingerprintPrefix: String
    }

    private(set) var identity: DeviceIdentity?
    private var discovery: PeerDiscovery?
    private var listener: NWListener?
    private var heldConnection: NWConnection?
    private var receiver: SecureInputReceiver?
    private var sender: SecureInputSender?
    private var session: InputSession?
    private var capture: MacInputCapture?
    private var sink: MacInputSink?
    private let servicePort: UInt16 = 24_800
    private var placements: [String: Side] = [:]

    init() {
        do {
            let identity = try DeviceIdentity.loadOrCreate()
            self.identity = identity
            startDiscovery(identity)
            status = "Ready — no device connected"
        } catch {
            status = "Cannot create device identity"
            errorText = error.localizedDescription
        }
    }

    // MARK: discovery

    private func startDiscovery(_ identity: DeviceIdentity) {
        let discovery = PeerDiscovery()
        discovery.onPeersChanged = { [weak self] peers in
            guard let self else { return }
            let mapped = peers.map { peer in
                Device(id: peer.id, name: peer.name, address: peer.address,
                       fingerprint: peer.fingerprint, port: peer.port,
                       side: self.placements[peer.id])
            }
            self.devices = mapped
        }
        self.discovery = discovery
        try? discovery.start(id: identity.id, name: identity.name,
                             fingerprint: identity.fingerprintHex(), servicePort: servicePort)
    }

    // MARK: sending

    func connect(_ device: Device) {
        guard let identity, sender == nil else { return }
        do {
            let pin = try SecureTransport.parseFingerprint(device.fingerprint)
            let connection = try SecureTransport.client(host: device.address, port: device.port,
                                                        fingerprint: pin, identity: identity.identity,
                                                        callbackQueue: .main)
            let newSender = SecureInputSender(connection: connection, queue: .main) { [weak self] error in
                self?.teardown()
                self?.status = error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected"
            }
            let newSession = InputSession(send: { [weak newSender] event in
                guard let newSender else { throw NSError(domain: "cursorloom", code: 1) }
                try newSender.send(event)
            }, stopCapture: { [weak self] in self?.capture?.stop(); self?.capture = nil })
            try newSession.beginConnection()
            sender = newSender
            session = newSession
            connectedDevice = device.id
            status = "Connecting to \(device.name)…"
            newSender.start { [weak self, weak newSession] in
                guard let self else { return }
                do {
                    try newSession?.authenticated()
                    self.status = "Connected to \(device.name) — press Share to start"
                } catch { self.disconnect() }
            }
        } catch {
            errorText = error.localizedDescription
            status = "Connection failed"
        }
    }

    func share() {
        guard let session, session.state.phase == .connected else { return }
        do {
            try session.beginSharing(consent: true, clipboard: false)
            let capture = MacInputCapture { [weak self] event in
                guard let self else { return }
                do { try self.session?.forward(event) }
                catch { self.disconnect(); self.status = "Sharing stopped" }
            }
            self.capture = capture
            try capture.start()
            sharing = true
            status = "Sharing mouse and keyboard. Local input still works."
        } catch {
            status = "Cannot start input capture — allow Accessibility in System Settings"
            errorText = error.localizedDescription
        }
    }

    func stopSharing() {
        session?.stopSharing()
        capture?.stop()
        capture = nil
        sharing = false
        if connectedDevice != nil { status = "Connected — sharing off" }
    }

    func disconnect() {
        teardown()
        status = "Ready — no device connected"
    }

    private func teardown() {
        capture?.stop(); capture = nil
        session?.stopSharing()
        session = nil
        sender?.stop(); sender = nil
        sharing = false
        connectedDevice = nil
    }

    // MARK: receiving

    private func startListening() {
        guard listener == nil, let identity else { return }
        do {
            let listener = try SecureTransport.pairingListener(port: servicePort, identity: identity.identity,
                                                              callbackQueue: .main) { _ in }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    Task { @MainActor in self?.status = "Cannot listen: \(error.localizedDescription)" }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.handleIncoming(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
            status = "Allowed devices can ask to control this Mac"
        } catch {
            errorText = error.localizedDescription
            allowControl = false
        }
    }

    private func handleIncoming(_ connection: NWConnection) {
        guard receiver == nil, heldConnection == nil else { connection.cancel(); return }
        heldConnection = connection
        status = "A device wants to connect…"
        // The peer's certificate is only known after the TLS handshake; until then the
        // name is unknown, so the prompt starts immediately after authenticate.
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.pendingRequest = PendingRequest(name: "Nearby device",
                                                         fingerprintPrefix: connection.endpoint.debugDescription)
                case .failed, .cancelled:
                    self.heldConnection = nil
                    self.pendingRequest = nil
                    if self.receiver == nil { self.status = "Ready — no device connected" }
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    func answerRequest(_ allow: Bool) {
        guard let connection = heldConnection else { return }
        pendingRequest = nil
        if !allow {
            heldConnection = nil
            connection.cancel()
            status = "Request denied"
            return
        }
        let sink = MacInputSink()
        self.sink = sink
        let instance = SecureInputReceiver(connection: connection, queue: .main, apply: { input in
            sink.apply(input, allowClipboard: false)
        }, release: { sink.releaseAll() }, finished: { [weak self] error in
            self?.receiver = nil
            self?.sink = nil
            self?.heldConnection = nil
            self?.status = error.map { "Connection ended: \($0.localizedDescription)" } ?? "Device disconnected"
        })
        receiver = instance
        heldConnection = nil
        status = "Controlled by another device"
        instance.start()
    }

    private func stopListening() {
        listener?.cancel(); listener = nil
        heldConnection?.cancel(); heldConnection = nil
        receiver?.stop(); receiver = nil
        pendingRequest = nil
        if connectedDevice == nil { status = "Ready — no device connected" }
    }

    // MARK: layout

    func place(_ device: Device, side: Side?) {
        if let side { placements[device.id] = side } else { placements.removeValue(forKey: device.id) }
        devices = devices.map { current in
            var updated = current
            if current.id == device.id { updated.side = side }
            return updated
        }
    }

    func sideLabel(for device: Device) -> String {
        device.side?.label ?? "Not placed"
    }
}

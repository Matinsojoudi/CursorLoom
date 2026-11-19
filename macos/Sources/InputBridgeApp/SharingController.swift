import Foundation
import InputBridge
import Security

/// Development-only manual controller, running on the main thread.
/// Network identity and peer pin are chosen manually and never persisted.
final class SharingController: ObservableObject {
    @Published private(set) var status = "Stopped"
    private var sender: SecureInputSender?
    private var capture: MacInputCapture?
    private var session: InputSession?

    func connect(host: String, port: UInt16, certificate: Data, password: String, peerFingerprint: String) throws {
        precondition(Thread.isMainThread)
        guard sender == nil else { throw ControllerError.alreadyRunning }
        let identity = try Identity.fromPKCS12(certificate, password: password)
        let pin = try SecureTransport.parseFingerprint(peerFingerprint)
        let connection = try SecureTransport.client(host: host, port: port, fingerprint: pin,
                                                    identity: identity, callbackQueue: .main)
        let newSender = SecureInputSender(connection: connection, queue: .main) { [weak self] error in
            self?.session?.disconnect()
            self?.capture?.stop()
            self?.capture = nil
            self?.session = nil
            self?.sender = nil
            self?.status = error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected"
        }
        let newSession = InputSession(send: { [weak newSender] event in
            guard let newSender else { throw ControllerError.notConnected }
            try newSender.send(event)
        }, stopCapture: { [weak self] in self?.capture?.stop(); self?.capture = nil })
        try newSession.beginConnection()
        sender = newSender
        session = newSession
        status = "Connecting…"
        newSender.start { [weak self, weak newSession] in
            do { try newSession?.authenticated(); self?.status = "Connected — sharing off" }
            catch { self?.stop(); self?.status = "Session error" }
        }
    }

    func startSharing() throws {
        precondition(Thread.isMainThread)
        guard let session, session.state.phase == .connected else { throw ControllerError.notConnected }
        try session.beginSharing(consent: true, clipboard: false)
        let capture = MacInputCapture { [weak self] event in
            guard let self else { return }
            do { try self.session?.forward(event) }
            catch { self.stop(); self.status = "Input sharing stopped" }
        }
        self.capture = capture
        do { try capture.start(); status = "Sharing input — local input remains active" }
        catch { session.stopSharing(); self.capture = nil; throw error }
    }

    func stopSharing() { session?.stopSharing(); status = "Connected — sharing off" }

    func stop() {
        precondition(Thread.isMainThread)
        session?.stopSharing()
        sender?.stop()
        session = nil
        capture = nil
        sender = nil
        status = "Stopped"
    }

    enum ControllerError: Error { case alreadyRunning, notConnected }
}

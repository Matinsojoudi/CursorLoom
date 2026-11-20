import Foundation
import InputBridge
import Network

/// Experimental receiver; all state and input injection remain on the main queue.
final class ReceiverController: ObservableObject {
    @Published private(set) var status = "Receiver stopped"
    @Published private(set) var active = false
    private var listener: NWListener?
    private var receiver: SecureInputReceiver?
    private var sink: MacInputSink?

    func start(port: UInt16, certificate: Data, password: String, peerFingerprint: String,
               consent: Bool, allowClipboard: Bool) throws {
        precondition(Thread.isMainThread)
        guard consent else { throw ReceiverError.consentRequired }
        guard listener == nil, receiver == nil else { throw ReceiverError.alreadyRunning }
        guard port != 0 else { throw ReceiverError.invalidPort }
        let identity = try Identity.fromPKCS12(certificate, password: password)
        let pin = try SecureTransport.parseFingerprint(peerFingerprint)
        let newListener = try SecureTransport.listener(port: port, fingerprint: pin, identity: identity, callbackQueue: .main)
        let inputSink = MacInputSink()
        sink = inputSink
        listener = newListener
        active = true
        status = "Waiting for an authenticated device…"
        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error): self?.stop(); self?.status = "Receiver failed: \(error.localizedDescription)"
            default: break
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            guard let self, self.receiver == nil, self.active else { connection.cancel(); return }
            // Accept only one connection, even before authentication, and stop listening.
            self.listener?.cancel()
            self.listener = nil
            let instance = SecureInputReceiver(connection: connection, queue: .main, apply: { input in
                inputSink.apply(input, allowClipboard: allowClipboard)
            }, release: { inputSink.releaseAll() }, finished: { [weak self] error in
                self?.receiver = nil
                self?.sink = nil
                self?.active = false
                self?.status = error.map { "Receiver stopped: \($0.localizedDescription)" } ?? "Receiver disconnected"
            })
            self.receiver = instance
            self.status = "Authenticating device…"
            instance.start()
        }
        newListener.start(queue: .main)
    }

    func stop() {
        precondition(Thread.isMainThread)
        listener?.cancel()
        listener = nil
        receiver?.stop()
        receiver = nil
        sink = nil
        active = false
        status = "Receiver stopped"
    }

    enum ReceiverError: Error { case consentRequired, alreadyRunning, invalidPort }
}

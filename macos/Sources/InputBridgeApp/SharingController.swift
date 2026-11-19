import Foundation
import InputBridge
import Security

/// Development-only manual controller, running on the main thread.
/// Network identity and peer pin are chosen manually and never persisted.
final class SharingController: ObservableObject {
    @Published private(set) var status = "Stopped"
    @Published private(set) var connected = false
    @Published private(set) var sharing = false
    private var sender: SecureInputSender?
    private var capture: MacInputCapture?
    private var session: InputSession?
    private var clipboard: ClipboardMonitor?
    private var clipboardTimer: Timer?

    func connect(host: String, port: UInt16, certificate: Data, password: String, peerFingerprint: String) throws {
        precondition(Thread.isMainThread)
        guard sender == nil else { throw ControllerError.alreadyRunning }
        let identity = try Identity.fromPKCS12(certificate, password: password)
        let pin = try SecureTransport.parseFingerprint(peerFingerprint)
        let connection = try SecureTransport.client(host: host, port: port, fingerprint: pin,
                                                    identity: identity, callbackQueue: .main)
        let newSender = SecureInputSender(connection: connection, queue: .main) { [weak self] error in
            self?.stopClipboard()
            self?.connected = false
            self?.sharing = false
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
            do { try newSession?.authenticated(); self?.connected = true; self?.status = "Connected — sharing off" }
            catch { self?.stop(); self?.status = "Session error" }
        }
    }

    func startSharing(shareClipboard: Bool) throws {
        precondition(Thread.isMainThread)
        guard let session, session.state.phase == .connected else { throw ControllerError.notConnected }
        try session.beginSharing(consent: true, clipboard: shareClipboard)
        let capture = MacInputCapture { [weak self] event in
            guard let self else { return }
            do {
                try self.session?.forward(event)
                if case .releaseAll = event { self.stopSharing(); self.status = "Capture stopped by macOS" }
            } catch { self.stop(); self.status = "Input sharing stopped" }
        }
        self.capture = capture
        do {
            try capture.start()
            if shareClipboard {
                let monitor = ClipboardMonitor { [weak self] text in
                    do { try self?.session?.forward(.clipboard(text: text)) }
                    catch { self?.stop(); self?.status = "Clipboard sharing stopped" }
                }
                clipboard = monitor
                clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    self?.clipboard?.poll()
                }
            }
            sharing = true
            status = "Sharing input — local input remains active"
        } catch { session.stopSharing(); self.capture = nil; stopClipboard(); throw error }
    }

    private func stopClipboard() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        clipboard = nil
    }

    func stopSharing() {
        stopClipboard()
        session?.stopSharing()
        sharing = false
        status = connected ? "Connected — sharing off" : "Stopped"
    }

    func stop() {
        precondition(Thread.isMainThread)
        stopClipboard()
        session?.stopSharing()
        sender?.stop()
        session = nil
        capture = nil
        sender = nil
        connected = false
        sharing = false
        status = "Stopped"
    }

    enum ControllerError: Error { case alreadyRunning, notConnected }
}

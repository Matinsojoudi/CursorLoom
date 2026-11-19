import Foundation

/// Coordinates consent and input delivery. The caller serializes all calls.
/// Its transport closure must only target an authenticated, pinned TLS connection.
public final class InputSession {
    public enum Error: Swift.Error { case notPermitted }
    public private(set) var state = SessionState()
    private let send: (RemoteInput) throws -> Void
    private let stopCapture: () -> Void

    public init(send: @escaping (RemoteInput) throws -> Void, stopCapture: @escaping () -> Void) {
        self.send = send
        self.stopCapture = stopCapture
    }

    public func beginConnection() throws { try state.beginConnection() }
    public func authenticated() throws { try state.authenticated() }
    public func beginSharing(consent: Bool, clipboard: Bool) throws {
        try state.beginSharing(consent: consent, clipboard: clipboard)
    }

    public func forward(_ input: RemoteInput) throws {
        guard state.permits(input) else { throw Error.notPermitted }
        do { try send(input) }
        catch {
            disconnect()
            throw error
        }
    }

    /// Release the peer's pressed keys before capture is stopped. The receiver must
    /// also release independently on transport failure if this message is lost.
    public func stopSharing() {
        let wasSharing = state.phase == .sharing
        state.stopSharing()
        if wasSharing {
            stopCapture()
            do { try send(.releaseAll) }
            catch { state.disconnect() }
        }
    }

    public func disconnect() {
        let wasSharing = state.phase == .sharing
        state.disconnect()
        if wasSharing { stopCapture() }
    }
}

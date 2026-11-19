import Foundation

/// Pure consent/session state machine. This does not establish a connection or capture input.
public struct SessionState: Equatable {
    public enum Phase: Equatable { case stopped, connecting, connected, sharing }
    public enum SessionError: Error, Equatable { case invalidTransition, missingConsent }
    public private(set) var phase: Phase = .stopped
    public private(set) var clipboardEnabled = false

    public init() {}

    public mutating func beginConnection() throws {
        guard phase == .stopped else { throw SessionError.invalidTransition }
        phase = .connecting
    }

    public mutating func authenticated() throws {
        guard phase == .connecting else { throw SessionError.invalidTransition }
        phase = .connected
    }

    public mutating func beginSharing(consent: Bool, clipboard: Bool) throws {
        guard phase == .connected else { throw SessionError.invalidTransition }
        guard consent else { throw SessionError.missingConsent }
        clipboardEnabled = clipboard
        phase = .sharing
    }

    public mutating func stopSharing() {
        if phase == .sharing { phase = .connected }
        clipboardEnabled = false
    }

    public mutating func disconnect() {
        clipboardEnabled = false
        phase = .stopped
    }

    public func permits(_ input: RemoteInput) -> Bool {
        guard phase == .sharing else { return false }
        if case .clipboard = input { return clipboardEnabled }
        return true
    }
}

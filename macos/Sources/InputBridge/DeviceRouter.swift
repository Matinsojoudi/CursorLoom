import Foundation

/// Pure single-active-target state. The transport owner serializes calls and must
/// disconnect any peer whose release fails. This does not itself transmit messages.
public struct DeviceRouter {
    public enum RouterError: Error { case invalidPeer, duplicatePeer, peerLimit, unknownPeer }
    public static let maximumPeers = 4
    public private(set) var peers: Set<String> = []
    public private(set) var activePeer: String?

    public init() {}

    public mutating func add(_ peer: String) throws {
        guard !peer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, peer.utf8.count <= 128 else { throw RouterError.invalidPeer }
        guard !peers.contains(peer) else { throw RouterError.duplicatePeer }
        guard peers.count < Self.maximumPeers else { throw RouterError.peerLimit }
        peers.insert(peer)
    }

    /// Release prior peer before selecting a new one. Failure leaves local active.
    @discardableResult
    public mutating func select(_ next: String?, release: (String) throws -> Bool) throws -> Bool {
        if let next, !peers.contains(next) { throw RouterError.unknownPeer }
        let previous = activePeer
        if previous == next { return true }
        activePeer = nil
        if let previous {
            do {
                guard try release(previous) else { peers.remove(previous); return false }
            } catch {
                peers.remove(previous)
                throw error
            }
        }
        activePeer = next
        return true
    }

    public mutating func remove(_ peer: String) {
        peers.remove(peer)
        if activePeer == peer { activePeer = nil }
    }
}

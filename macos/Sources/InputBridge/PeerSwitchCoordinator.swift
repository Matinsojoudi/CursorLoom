import Foundation

/// Draft state coordinator. The app must serialize access and close a failed peer.
/// A release acknowledgement must be negotiated and received before completing
/// a switch; this type does not send network traffic or guarantee OS delivery.
public struct PeerSwitchCoordinator {
    public enum SwitchError: Error { case alreadySwitching, unknownPeer, mismatchedID, noSwitch }
    private var router = DeviceRouter()
    private var tracker = ReleaseTracker()
    private var target: String?
    public var activePeer: String? { router.activePeer }
    public var peers: Set<String> { router.peers }
    public var switching: Bool { tracker.pendingID != nil }

    public init() {}
    public mutating func add(_ peer: String) throws { try router.add(peer) }

    /// Returns a release request when a previous peer exists; caller sends it only
    /// to that peer. While pending, no peer is selected for input delivery.
    public mutating func beginSwitch(to next: String?, requestID: String) throws -> (previous: String, request: Envelope)? {
        guard !switching else { throw SwitchError.alreadySwitching }
        if let next, !router.peers.contains(next) { throw SwitchError.unknownPeer }
        guard let previous = router.activePeer, previous != next else {
            _ = try router.select(next) { _ in true }
            return nil
        }
        let request = try tracker.begin(id: requestID)
        _ = try router.select(nil) { _ in true }
        target = next
        pendingPrevious = previous
        return (previous, request)
    }

    public mutating func completeSwitch(_ acknowledgement: Envelope, from peer: String) throws {
        guard tracker.pendingID != nil else { throw SwitchError.noSwitch }
        // Caller must additionally authenticate and associate the response with
        // the previous connection; peer identity is checked explicitly.
        guard peer == pendingPrevious else { failSwitch(); throw SwitchError.mismatchedID }
        do {
            try tracker.complete(acknowledgement)
            let next = target
            target = nil
            pendingPrevious = nil
            _ = try router.select(next) { _ in true }
        } catch {
            failSwitch()
            throw error
        }
    }

    private var pendingPrevious: String?

    public mutating func failSwitch() {
        if let previous = pendingPrevious { router.remove(previous) }
        tracker.cancel()
        target = nil
        pendingPrevious = nil
    }

    public mutating func remove(_ peer: String) {
        if peer == pendingPrevious || peer == target { failSwitch() }
        router.remove(peer)
    }

    public func destination(for input: RemoteInput, clipboardAllowed: Set<String>) -> String? {
        router.destination(for: input, clipboardAllowed: clipboardAllowed)
    }
}

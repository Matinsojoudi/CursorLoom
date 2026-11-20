import Foundation

/// Correlates release acknowledgements; caller serializes access and enforces timeouts.
/// This does not prove OS input delivery or establish protocol compatibility.
public struct ReleaseTracker {
    public enum TrackerError: Error, Equatable { case alreadyPending, noPending, mismatchedID, releaseRejected }
    public private(set) var pendingID: String?

    public init() {}

    public mutating func begin(id: String) throws -> Envelope {
        guard pendingID == nil else { throw TrackerError.alreadyPending }
        let message = try ReleaseAcknowledgement.request(id: id)
        pendingID = id
        return message
    }

    public mutating func complete(_ envelope: Envelope) throws {
        guard let expected = pendingID else { throw TrackerError.noPending }
        let result: (id: String, accepted: Bool)
        do { result = try ReleaseAcknowledgement.parseResponse(envelope) }
        catch { pendingID = nil; throw error }
        pendingID = nil
        guard result.id.caseInsensitiveCompare(expected) == .orderedSame else { throw TrackerError.mismatchedID }
        guard result.accepted else { throw TrackerError.releaseRejected }
    }

    public mutating func cancel() { pendingID = nil }
}

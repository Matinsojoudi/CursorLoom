import Foundation

/// Draft v1 extension. Not integrated with network sessions: old peers reject it.
/// An acknowledgement means only that the OS injection API accepted creation of
/// release events; it cannot guarantee the operating system delivered them.
public enum ReleaseAcknowledgement {
    public enum ValidationError: Error { case invalidMessage }
    public static func request(id: String) throws -> Envelope {
        guard valid(id) else { throw ValidationError.invalidMessage }
        return Envelope(type: "releaseRequest", payload: ["id": .string(id)])
    }
    public static func response(id: String, accepted: Bool) throws -> Envelope {
        guard valid(id) else { throw ValidationError.invalidMessage }
        return Envelope(type: "releaseAck", payload: ["id": .string(id), "accepted": .bool(accepted)])
    }
    public static func parseRequest(_ message: Envelope) throws -> String {
        guard message.version == 1, message.type == "releaseRequest", message.payload.count == 1,
              case let .string(id)? = message.payload["id"], valid(id) else { throw ValidationError.invalidMessage }
        return id
    }
    public static func parseResponse(_ message: Envelope) throws -> (id: String, accepted: Bool) {
        guard message.version == 1, message.type == "releaseAck", message.payload.count == 2,
              case let .string(id)? = message.payload["id"], valid(id),
              case let .bool(accepted)? = message.payload["accepted"] else { throw ValidationError.invalidMessage }
        return (id, accepted)
    }
    private static func valid(_ id: String) -> Bool {
        id.utf8.count == 36 && UUID(uuidString: id) != nil
    }
}

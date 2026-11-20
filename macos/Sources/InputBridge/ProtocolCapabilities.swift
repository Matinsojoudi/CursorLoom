import Foundation

/// Draft capability exchange; not enabled on existing connections. New messages
/// cannot be sent until a future versioned handshake negotiates them explicitly.
public struct ProtocolCapabilities: Equatable, Sendable {
    public let releaseAcknowledgements: Bool
    public init(releaseAcknowledgements: Bool) { self.releaseAcknowledgements = releaseAcknowledgements }

    public func envelope() -> Envelope {
        Envelope(type: "capabilities", payload: ["releaseAck": .bool(releaseAcknowledgements)])
    }

    public static func parse(_ envelope: Envelope) throws -> ProtocolCapabilities {
        guard envelope.version == 1, envelope.type == "capabilities", envelope.payload.count == 1,
              case let .bool(releaseAck)? = envelope.payload["releaseAck"] else {
            throw CapabilityError.invalidMessage
        }
        return ProtocolCapabilities(releaseAcknowledgements: releaseAck)
    }

    public func supportsReleaseWith(_ peer: ProtocolCapabilities) -> Bool {
        releaseAcknowledgements && peer.releaseAcknowledgements
    }
    public enum CapabilityError: Error { case invalidMessage }
}

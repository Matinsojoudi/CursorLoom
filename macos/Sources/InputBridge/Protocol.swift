import Foundation

/// Initial protocol scaffolding. Never use without an authenticated encrypted channel.
public struct Envelope: Codable, Equatable, Sendable {
    public let version: Int
    public let type: String
    public let payload: [String: JSONValue]

    public init(version: Int = 1, type: String, payload: [String: JSONValue]) {
        self.version = version
        self.type = type
        self.payload = payload
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public enum ProtocolError: Error, Equatable {
    case messageTooLarge
    case unsupportedVersion
}

public enum MessageCodec {
    public static let maximumBytes = 65_536

    public static func encode(_ message: Envelope) throws -> Data {
        guard message.version == 1 else { throw ProtocolError.unsupportedVersion }
        var data = try JSONEncoder().encode(message)
        guard data.count + 1 <= maximumBytes else { throw ProtocolError.messageTooLarge }
        data.append(0x0a)
        return data
    }

    /// Decode exactly one framed message; enforce size before parsing untrusted input.
    public static func decode(_ data: Data) throws -> Envelope {
        guard data.count <= maximumBytes else { throw ProtocolError.messageTooLarge }
        let message = try JSONDecoder().decode(Envelope.self, from: data)
        guard message.version == 1 else { throw ProtocolError.unsupportedVersion }
        return message
    }
}

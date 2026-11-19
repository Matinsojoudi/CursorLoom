import Foundation

/// Validated commands, independent of transport and operating-system injection.
public enum RemoteInput: Equatable, Sendable {
    case key(usage: Int, down: Bool)
    case pointer(x: Double, y: Double)
    case button(index: Int, down: Bool)
    case scroll(vertical: Int, horizontal: Int)
    case clipboard(text: String)
    case releaseAll
}

public enum InputValidationError: Error, Equatable {
    case unsupportedType
    case invalidPayload
}

public enum InputValidator {
    /// Unknown fields and out-of-range values are rejected rather than silently normalized.
    public static func parse(_ envelope: Envelope) throws -> RemoteInput {
        guard envelope.version == 1 else { throw InputValidationError.invalidPayload }
        let p = envelope.payload
        func keys(_ expected: Set<String>) throws {
            guard Set(p.keys) == expected else { throw InputValidationError.invalidPayload }
        }
        func integer(_ name: String, range: ClosedRange<Int>) throws -> Int {
            guard case let .number(value)? = p[name], value.isFinite,
                  value.rounded(.towardZero) == value,
                  value >= Double(range.lowerBound), value <= Double(range.upperBound) else {
                throw InputValidationError.invalidPayload
            }
            return Int(value)
        }
        func boolean(_ name: String) throws -> Bool {
            guard case let .bool(value)? = p[name] else { throw InputValidationError.invalidPayload }
            return value
        }
        func fraction(_ name: String) throws -> Double {
            guard case let .number(value)? = p[name], value.isFinite, (0...1).contains(value) else {
                throw InputValidationError.invalidPayload
            }
            return value
        }
        switch envelope.type {
        case "key":
            try keys(["usage", "down"])
            return .key(usage: try integer("usage", range: 0...255), down: try boolean("down"))
        case "pointer":
            try keys(["x", "y"])
            return .pointer(x: try fraction("x"), y: try fraction("y"))
        case "button":
            try keys(["index", "down"])
            return .button(index: try integer("index", range: 0...1), down: try boolean("down"))
        case "scroll":
            try keys(["vertical", "horizontal"])
            return .scroll(vertical: try integer("vertical", range: -100...100), horizontal: try integer("horizontal", range: -100...100))
        case "clipboard":
            try keys(["text"])
            guard case let .string(text)? = p["text"], text.utf8.count <= 48_000 else { throw InputValidationError.invalidPayload }
            return .clipboard(text: text)
        case "releaseAll":
            try keys([])
            return .releaseAll
        default:
            throw InputValidationError.unsupportedType
        }
    }
}

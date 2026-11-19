import Foundation

public enum InputEncoding {
    public static func envelope(_ input: RemoteInput) -> Envelope {
        switch input {
        case let .key(usage, down):
            return Envelope(type: "key", payload: ["usage": .number(Double(usage)), "down": .bool(down)])
        case let .pointer(x, y):
            return Envelope(type: "pointer", payload: ["x": .number(x), "y": .number(y)])
        case let .button(index, down):
            return Envelope(type: "button", payload: ["index": .number(Double(index)), "down": .bool(down)])
        case let .scroll(vertical, horizontal):
            return Envelope(type: "scroll", payload: ["vertical": .number(Double(vertical)), "horizontal": .number(Double(horizontal))])
        case let .clipboard(text):
            return Envelope(type: "clipboard", payload: ["text": .string(text)])
        case .releaseAll:
            return Envelope(type: "releaseAll", payload: [:])
        }
    }

    public static func encode(_ input: RemoteInput) throws -> Data {
        let message = envelope(input)
        _ = try InputValidator.parse(message)
        return try MessageCodec.encode(message)
    }
}

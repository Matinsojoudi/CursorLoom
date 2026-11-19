import XCTest
@testable import InputBridge

final class RemoteInputTests: XCTestCase {
    func testSharedWireFixtures() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let wire = try Data(contentsOf: root.appendingPathComponent("test-vectors/input-messages.jsonl"))
        var decoder = FrameDecoder()
        let commands = try decoder.append(wire).map(InputValidator.parse)
        try decoder.finish()
        XCTAssertEqual(commands, [.key(usage: 4, down: true), .pointer(x: 0.25, y: 0.75),
                                  .button(index: 1, down: false), .scroll(vertical: -3, horizontal: 1),
                                  .clipboard(text: "سلام 🌍\nline"), .releaseAll])
    }

    func testEncodingRoundTripsAndRejectsInvalidValues() throws {
        let events: [RemoteInput] = [.key(usage: 4, down: true), .pointer(x: 0, y: 1),
            .button(index: 0, down: false), .scroll(vertical: -1, horizontal: 2),
            .clipboard(text: "آزمایش"), .releaseAll]
        for event in events {
            let frame = try InputEncoding.encode(event)
            XCTAssertEqual(try InputValidator.parse(MessageCodec.decode(frame)), event)
        }
        XCTAssertThrowsError(try InputEncoding.encode(.pointer(x: -1, y: 1)))
    }

    func testValidCommands() throws {
        XCTAssertEqual(try InputValidator.parse(Envelope(type: "pointer", payload: ["x": .number(0.3), "y": .number(1)])), .pointer(x: 0.3, y: 1))
        XCTAssertEqual(try InputValidator.parse(Envelope(type: "key", payload: ["usage": .number(4), "down": .bool(true)])), .key(usage: 4, down: true))
        XCTAssertEqual(try InputValidator.parse(Envelope(type: "releaseAll", payload: [:])), .releaseAll)
        XCTAssertEqual(try InputValidator.parse(Envelope(type: "clipboard", payload: ["text": .string("سلام")])), .clipboard(text: "سلام"))
    }

    func testInvalidCommandsFailClosed() {
        let invalid: [Envelope] = [
            Envelope(type: "pointer", payload: ["x": .number(-1), "y": .number(0)]),
            Envelope(type: "key", payload: ["usage": .number(4.5), "down": .bool(true)]),
            Envelope(type: "key", payload: ["usage": .number(4), "down": .bool(true), "extra": .null]),
            Envelope(type: "button", payload: ["index": .number(2), "down": .bool(true)]),
            Envelope(type: "clipboard", payload: ["text": .string(String(repeating: "x", count: 48_001))]),
            Envelope(type: "scroll", payload: ["vertical": .number(101), "horizontal": .number(0)]),
            Envelope(type: "other", payload: [:])
        ]
        for message in invalid { XCTAssertThrowsError(try InputValidator.parse(message)) }
    }
}

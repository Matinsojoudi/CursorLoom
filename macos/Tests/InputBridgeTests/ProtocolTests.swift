import XCTest
@testable import InputBridge

final class ProtocolTests: XCTestCase {
    func testInvalidIdentityRejected() {
        XCTAssertThrowsError(try Identity.fromPKCS12(Data("not a certificate".utf8), password: "wrong"))
    }

    func testCertificateFingerprintParsing() throws {
        let expected = Data(repeating: 0xab, count: 32)
        XCTAssertEqual(try SecureTransport.parseFingerprint(Array(repeating: "AB", count: 32).joined(separator: ":")), expected)
        XCTAssertThrowsError(try SecureTransport.parseFingerprint("aa"))
        XCTAssertThrowsError(try SecureTransport.parseFingerprint(String(repeating: "zz", count: 32)))
        XCTAssertThrowsError(try SecureTransport.parseFingerprint(String(repeating: "é", count: 32)))
    }

    func testHIDMapping() {
        XCTAssertEqual(MacInputSink.keyCode(for: 4), 0)
        XCTAssertEqual(MacInputSink.keyCode(for: 40), 36)
        XCTAssertEqual(MacInputSink.keyCode(for: 224), 59)
        XCTAssertNil(MacInputSink.keyCode(for: -1))
        XCTAssertNil(MacInputSink.keyCode(for: 9999))
        XCTAssertEqual(MacInputCapture.usage(for: 0), 4)
        XCTAssertEqual(MacInputCapture.usage(for: 36), 40)
        XCTAssertNil(MacInputCapture.usage(for: -1))
        XCTAssertNil(MacInputCapture.usage(for: 9999))
    }

    func testRoundTrip() throws {
        let message = Envelope(type: "key", payload: ["usage": .number(4), "down": .bool(true)])
        let encoded = try MessageCodec.encode(message)
        XCTAssertEqual(encoded.last, 10)
        XCTAssertEqual(try MessageCodec.decode(encoded), message)
    }

    func testRejectUnsupportedVersion() throws {
        XCTAssertThrowsError(try MessageCodec.encode(Envelope(version: 2, type: "hello", payload: [:])))
    }

    func testFragmentedAndCombinedFrames() throws {
        let first = Envelope(type: "hello", payload: [:])
        let second = Envelope(type: "clipboard", payload: ["text": .string("سلام\nworld")])
        let wire = try MessageCodec.encode(first) + MessageCodec.encode(second)
        var decoder = FrameDecoder()
        let split = wire.count / 2
        let received = try decoder.append(Data(wire.prefix(split))) + decoder.append(Data(wire.dropFirst(split)))
        XCTAssertEqual(received, [first, second])
        try decoder.finish()
    }

    func testOversizedAndTruncatedFramesFailClosed() throws {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data(repeating: 65, count: MessageCodec.maximumBytes)))
        XCTAssertThrowsError(try decoder.append(Data("{}\n".utf8)))
        var partial = FrameDecoder()
        _ = try partial.append(Data("{".utf8))
        XCTAssertThrowsError(try partial.finish())
    }

    func testEmptyAndMalformedFramesFailClosed() throws {
        var empty = FrameDecoder()
        XCTAssertThrowsError(try empty.append(Data("\n".utf8)))
        var malformed = FrameDecoder()
        XCTAssertThrowsError(try malformed.append(Data("{}\n".utf8)))
        XCTAssertThrowsError(try malformed.append(Data("{}\n".utf8)))
    }

    func testRejectOversizeMessage() throws {
        let message = Envelope(type: "clipboard", payload: ["text": .string(String(repeating: "x", count: 65_536))])
        XCTAssertThrowsError(try MessageCodec.encode(message))
    }
}

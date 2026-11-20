import XCTest
@testable import InputBridge

final class ProtocolCapabilitiesTests: XCTestCase {
    func testRequiresBothPeersAndRejectsUnknownFields() throws {
        let supported = ProtocolCapabilities(releaseAcknowledgements: true)
        let unsupported = ProtocolCapabilities(releaseAcknowledgements: false)
        XCTAssertEqual(try ProtocolCapabilities.parse(MessageCodec.decode(MessageCodec.encode(supported.envelope()))), supported)
        XCTAssertTrue(supported.supportsReleaseWith(supported))
        XCTAssertFalse(supported.supportsReleaseWith(unsupported))
        XCTAssertThrowsError(try ProtocolCapabilities.parse(Envelope(type: "capabilities", payload: ["releaseAck": .bool(true), "extra": .null])))
    }
}

import XCTest
@testable import InputBridge

final class ReleaseAcknowledgementTests: XCTestCase {
    func testRoundTripAndStrictValidation() throws {
        let id = "12345678-1234-1234-1234-123456789abc"
        XCTAssertEqual(try ReleaseAcknowledgement.parseRequest(MessageCodec.decode(MessageCodec.encode(ReleaseAcknowledgement.request(id: id)))), id)
        let response = try ReleaseAcknowledgement.parseResponse(MessageCodec.decode(MessageCodec.encode(ReleaseAcknowledgement.response(id: id, accepted: false))))
        XCTAssertEqual(response.id, id)
        XCTAssertFalse(response.accepted)
        XCTAssertThrowsError(try ReleaseAcknowledgement.request(id: "not-a-uuid"))
        XCTAssertThrowsError(try ReleaseAcknowledgement.parseResponse(Envelope(type: "releaseAck", payload: ["id": .string(id), "accepted": .bool(true), "extra": .null])))
    }
}

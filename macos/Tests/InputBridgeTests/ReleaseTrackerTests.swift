import XCTest
@testable import InputBridge

final class ReleaseTrackerTests: XCTestCase {
    func testCorrelatesAndFailsClosed() throws {
        let first = "12345678-1234-1234-1234-123456789abc"
        let other = "22345678-1234-1234-1234-123456789abc"
        var tracker = ReleaseTracker()
        _ = try tracker.begin(id: first)
        XCTAssertThrowsError(try tracker.begin(id: other))
        XCTAssertThrowsError(try tracker.complete(ReleaseAcknowledgement.response(id: other, accepted: true)))
        XCTAssertNil(tracker.pendingID)
        _ = try tracker.begin(id: first)
        XCTAssertThrowsError(try tracker.complete(ReleaseAcknowledgement.response(id: first, accepted: false)))
        XCTAssertNil(tracker.pendingID)
        _ = try tracker.begin(id: first)
        try tracker.complete(ReleaseAcknowledgement.response(id: first.uppercased(), accepted: true))
        XCTAssertNil(tracker.pendingID)
        XCTAssertThrowsError(try tracker.complete(ReleaseAcknowledgement.response(id: first, accepted: true)))
    }
}

import XCTest
@testable import InputBridge

final class SessionStateTests: XCTestCase {
    func testConsentAndDisconnectFailClosed() throws {
        var session = SessionState()
        XCTAssertFalse(session.permits(.key(usage: 4, down: true)))
        XCTAssertThrowsError(try session.beginSharing(consent: true, clipboard: true))
        try session.beginConnection()
        XCTAssertThrowsError(try session.beginConnection())
        try session.authenticated()
        XCTAssertThrowsError(try session.beginSharing(consent: false, clipboard: true))
        try session.beginSharing(consent: true, clipboard: false)
        XCTAssertTrue(session.permits(.key(usage: 4, down: true)))
        XCTAssertFalse(session.permits(.clipboard(text: "private")))
        session.stopSharing()
        XCTAssertFalse(session.permits(.key(usage: 4, down: true)))
        try session.beginSharing(consent: true, clipboard: true)
        XCTAssertTrue(session.permits(.clipboard(text: "ok")))
        session.disconnect()
        XCTAssertFalse(session.permits(.clipboard(text: "private")))
        XCTAssertFalse(session.clipboardEnabled)
        XCTAssertEqual(session.phase, .stopped)
    }
}

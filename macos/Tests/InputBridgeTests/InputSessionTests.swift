import XCTest
@testable import InputBridge

final class InputSessionTests: XCTestCase {
    func testConsentAndRelease() throws {
        var sent: [RemoteInput] = []
        var stops = 0
        let session = InputSession(send: { sent.append($0) }, stopCapture: { stops += 1 })
        XCTAssertThrowsError(try session.forward(.key(usage: 4, down: true)))
        try session.beginConnection()
        try session.authenticated()
        try session.beginSharing(consent: true, clipboard: false)
        XCTAssertThrowsError(try session.forward(.clipboard(text: "secret")))
        try session.forward(.key(usage: 4, down: true))
        session.stopSharing()
        XCTAssertEqual(sent, [.key(usage: 4, down: true), .releaseAll])
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(session.state.phase, .connected)
        XCTAssertThrowsError(try session.forward(.key(usage: 4, down: true)))
    }

    func testTransportFailureStopsCapture() throws {
        enum TestError: Error { case failed }
        var stops = 0
        let session = InputSession(send: { _ in throw TestError.failed }, stopCapture: { stops += 1 })
        try session.beginConnection()
        try session.authenticated()
        try session.beginSharing(consent: true, clipboard: true)
        XCTAssertThrowsError(try session.forward(.pointer(x: 0, y: 0)))
        XCTAssertEqual(session.state.phase, .stopped)
        XCTAssertEqual(stops, 1)
    }
}

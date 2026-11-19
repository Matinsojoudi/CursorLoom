import XCTest
@testable import InputBridge

final class EdgeSwitchTests: XCTestCase {
    func testRequiresArmingAndEdgeDwell() {
        var detector = EdgeSwitch(edge: .right, delay: 0.25)
        XCTAssertNil(detector.observe(x: 1, time: 1))
        detector.arm()
        XCTAssertNil(detector.observe(x: 1, time: 2))
        XCTAssertNil(detector.observe(x: 1, time: 2.2))
        XCTAssertEqual(detector.observe(x: 1, time: 2.3), .enterRemote)
        XCTAssertTrue(detector.isRemote)
        XCTAssertNil(detector.observe(x: 1, time: 3))
        XCTAssertEqual(detector.returnToLocal(), .returnLocal)
        XCTAssertNil(detector.returnToLocal())
        detector.disarm()
        XCTAssertNil(detector.observe(x: 1, time: 5))
    }

    func testLeavingEdgeAndClockRollbackResetDelay() {
        var detector = EdgeSwitch(edge: .left, delay: 0.5)
        detector.arm()
        XCTAssertNil(detector.observe(x: 0, time: 5))
        XCTAssertNil(detector.observe(x: 0.4, time: 6))
        XCTAssertNil(detector.observe(x: 0, time: 6.1))
        XCTAssertNil(detector.observe(x: 0, time: 2))
        XCTAssertEqual(detector.observe(x: 0, time: 2.5), .enterRemote)
    }
}

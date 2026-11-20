import XCTest
@testable import InputBridge

final class DeviceRouterTests: XCTestCase {
    func testSwitchReleasesPreviousBeforeActivation() throws {
        var router = DeviceRouter()
        try router.add("a"); try router.add("b")
        var releases: [String] = []
        XCTAssertTrue(try router.select("a") { releases.append($0); return true })
        XCTAssertTrue(try router.select("b") { releases.append($0); return true })
        XCTAssertEqual(releases, ["a"])
        XCTAssertEqual(router.activePeer, "b")
        router.remove("b")
        XCTAssertNil(router.activePeer)
    }

    func testReleaseFailureAndLimitFailClosed() throws {
        var router = DeviceRouter()
        for peer in ["a", "b", "c", "d"] { try router.add(peer) }
        XCTAssertThrowsError(try router.add("e"))
        XCTAssertTrue(try router.select("a") { _ in true })
        XCTAssertFalse(try router.select("b") { _ in false })
        XCTAssertNil(router.activePeer)
        XCTAssertFalse(router.peers.contains("a"))
        XCTAssertThrowsError(try router.select("unknown") { _ in true })
    }
}

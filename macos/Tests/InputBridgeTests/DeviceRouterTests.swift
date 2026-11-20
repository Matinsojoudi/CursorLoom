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
        XCTAssertEqual(router.destination(for: .key(usage: 4, down: true), clipboardAllowed: []), "b")
        XCTAssertNil(router.destination(for: .clipboard(text: "private"), clipboardAllowed: ["a"]))
        XCTAssertEqual(router.destination(for: .clipboard(text: "ok"), clipboardAllowed: ["b"]), "b")
        router.remove("b")
        XCTAssertNil(router.activePeer)
    }

    func testReleaseFailureAndLimitFailClosed() throws {
        var router = DeviceRouter()
        for peer in ["a", "b", "c", "d"] { try router.add(peer) }
        XCTAssertThrowsError(try router.add("e"))
        var emptyRouter = DeviceRouter()
        XCTAssertThrowsError(try emptyRouter.add(String(repeating: "ا", count: 65)))
        XCTAssertTrue(try router.select("a") { _ in true })
        XCTAssertFalse(try router.select("b") { _ in false })
        XCTAssertNil(router.activePeer)
        XCTAssertFalse(router.peers.contains("a"))
        XCTAssertThrowsError(try router.select("unknown") { _ in true })
    }
}

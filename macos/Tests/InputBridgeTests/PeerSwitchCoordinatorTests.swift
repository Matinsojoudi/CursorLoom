import XCTest
@testable import InputBridge

final class PeerSwitchCoordinatorTests: XCTestCase {
    func testSwitchWaitsForCorrelatedPeerAcknowledgement() throws {
        let id = "12345678-1234-1234-1234-123456789abc"
        var coordinator = PeerSwitchCoordinator()
        try coordinator.add("a"); try coordinator.add("b")
        XCTAssertNil(try coordinator.beginSwitch(to: "a", requestID: id))
        XCTAssertEqual(try coordinator.beginSwitch(to: "b", requestID: id)?.previous, "a")
        XCTAssertNil(coordinator.destination(for: .key(usage: 4, down: true), clipboardAllowed: []))
        try coordinator.completeSwitch(ReleaseAcknowledgement.response(id: id, accepted: true), from: "a")
        XCTAssertEqual(coordinator.activePeer, "b")
        _ = try coordinator.beginSwitch(to: "a", requestID: id)
        XCTAssertThrowsError(try coordinator.completeSwitch(ReleaseAcknowledgement.response(id: id, accepted: true), from: "a"))
        XCTAssertNil(coordinator.activePeer)
        XCTAssertFalse(coordinator.peers.contains("b"))
    }

    func testDisconnectDuringSwitchFailsClosed() throws {
        var coordinator = PeerSwitchCoordinator()
        try coordinator.add("a"); try coordinator.add("b")
        let id = "12345678-1234-1234-1234-123456789abc"
        _ = try coordinator.beginSwitch(to: "a", requestID: id)
        _ = try coordinator.beginSwitch(to: "b", requestID: id)
        coordinator.remove("b")
        XCTAssertNil(coordinator.activePeer)
        XCTAssertFalse(coordinator.switching)
    }
}

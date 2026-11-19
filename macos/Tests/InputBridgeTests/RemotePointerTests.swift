import XCTest
@testable import InputBridge

final class RemotePointerTests: XCTestCase {
    func testEnterMoveClampAndReturn() {
        var pointer = RemotePointer(returnSide: .left, y: 0.4)
        XCTAssertEqual(pointer.move(dx: 0.5, dy: 0.8), .move(x: 0.5, y: 1))
        XCTAssertEqual(pointer.move(dx: 1, dy: -2), .move(x: 1, y: 0))
        XCTAssertEqual(pointer.move(dx: -1.1, dy: 0.3), .exit(y: 0.3))
    }

    func testOtherSideAndNonFiniteInput() {
        var pointer = RemotePointer(returnSide: .right, y: .nan)
        XCTAssertEqual(pointer.y, 0.5)
        XCTAssertEqual(pointer.move(dx: .infinity, dy: 0), .unchanged)
        XCTAssertEqual(pointer.move(dx: -0.25, dy: 0), .move(x: 0.75, y: 0.5))
        XCTAssertEqual(pointer.move(dx: 0.5, dy: 0), .exit(y: 0.5))
    }
}

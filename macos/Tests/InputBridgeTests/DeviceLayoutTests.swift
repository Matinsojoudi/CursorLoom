import XCTest
@testable import InputBridge

final class DeviceLayoutTests: XCTestCase {
    func testAdjacencyAndValidation() throws {
        var layout = DeviceLayout()
        try layout.add("windows", at: .init(x: 1, y: 0))
        try layout.add("mac", at: .init(x: 1, y: -1))
        XCTAssertEqual(layout.neighbor(of: "local", direction: .right), "windows")
        XCTAssertEqual(layout.neighbor(of: "windows", direction: .up), "mac")
        XCTAssertNil(layout.neighbor(of: "local", direction: .left))
        XCTAssertThrowsError(try layout.add("duplicate-position", at: .init(x: 1, y: 0)))
        XCTAssertThrowsError(try layout.add("windows", at: .init(x: 2, y: 0)))
        XCTAssertThrowsError(try layout.add("bad", at: .init(x: Int.max, y: 0)))
        layout.remove("windows")
        XCTAssertNil(layout.neighbor(of: "local", direction: .right))
    }
}

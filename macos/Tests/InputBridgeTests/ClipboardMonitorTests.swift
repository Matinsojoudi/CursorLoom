import AppKit
import XCTest
@testable import InputBridge

final class ClipboardMonitorTests: XCTestCase {
    func testPollingAndRemoteEchoSuppression() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("InputBridgeTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var values: [String] = []
        let monitor = ClipboardMonitor(pasteboard: board) { values.append($0) }
        board.clearContents()
        XCTAssertTrue(board.setString("local", forType: .string))
        monitor.poll()
        monitor.poll()
        XCTAssertEqual(values, ["local"])
        XCTAssertTrue(monitor.applyRemote("remote"))
        monitor.poll()
        XCTAssertEqual(values, ["local"])
        XCTAssertEqual(board.string(forType: .string), "remote")
        XCTAssertFalse(monitor.applyRemote(String(repeating: "x", count: 48_001)))
    }
}

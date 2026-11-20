import XCTest
import Foundation
@testable import InputBridge

final class PeerDiscoveryTests: XCTestCase {
    func testDevicesDiscoverEachOtherAndIgnoreBadBeacons() throws {
        let port: UInt16 = 24_900 + UInt16.random(in: 0...80)
        let alice = PeerDiscovery(port: port)
        let bob = PeerDiscovery(port: port)
        addTeardownBlock { alice.stop(); bob.stop() }

        let found = expectation(description: "bob sees alice")
        found.assertForOverFulfill = false
        bob.onPeersChanged = { peers in
            if peers.contains(where: { $0.id == "11111111-1111-1111-1111-111111111111" }) { found.fulfill() }
        }
        try alice.start(id: "11111111-1111-1111-1111-111111111111", name: "MacBook",
                        fingerprint: String(repeating: "ab", count: 32), servicePort: 24_800)
        try bob.start(id: "22222222-2222-2222-2222-222222222222", name: "Desktop",
                      fingerprint: String(repeating: "cd", count: 32), servicePort: 24_800)
        wait(for: [found], timeout: 6)

        let peers = bob.snapshot()
        XCTAssertEqual(peers.count, 1)
        XCTAssertEqual(peers.first?.name, "MacBook")
        XCTAssertEqual(peers.first?.port, 24_800)
        XCTAssertFalse(peers.first?.address.isEmpty ?? true, "Discovered peer needs a reachable address")
        XCTAssertFalse(alice.snapshot().contains { $0.id == "11111111-1111-1111-1111-111111111111" },
                       "A device must not list itself")
    }

    func testRejectsOversizedOrMalformedCertificatesInBeacons() throws {
        let port: UInt16 = 24_990 + UInt16.random(in: 0...5)
        let discovery = PeerDiscovery(port: port)
        addTeardownBlock { discovery.stop() }
        let bogus = expectation(description: "no bogus peers")
        bogus.isInverted = true
        discovery.onPeersChanged = { peers in if !peers.isEmpty { bogus.fulfill() } }
        try discovery.start(id: "33333333-3333-3333-3333-333333333333", name: "Self",
                            fingerprint: String(repeating: "ef", count: 32), servicePort: 24_800)

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var destination = sockaddr_in()
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        destination.sin_addr = in_addr(s_addr: INADDR_LOOPBACK)
        let payload = Data(#"{"v":1,"id":"44444444-4444-4444-4444-444444444444","name":"Fake","fp":"short","port":24800}"#.utf8)
        _ = payload.withUnsafeBytes { raw in
            withUnsafePointer(to: &destination) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, raw.baseAddress, payload.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        wait(for: [bogus], timeout: 2)
    }
}

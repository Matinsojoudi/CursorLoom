import Darwin
import Foundation

public struct DiscoveredPeer: Equatable, Sendable {
    public let id: String
    public let name: String
    public let fingerprint: String
    public let port: UInt16
    public let address: String
    public let lastSeen: Date
}

public struct PeerBeacon: Codable, Equatable, Sendable {
    public static let protocolVersion = 1
    public var v: Int = Self.protocolVersion
    public var id: String
    public var name: String
    public var fp: String
    public var port: UInt16
    public init(id: String, name: String, fp: String, port: UInt16) {
        self.id = id; self.name = name; self.fp = fp; self.port = port
    }
}

/// Broadcast-based LAN discovery. Devices announce themselves every few seconds;
/// nothing is trusted from a beacon beyond "this address claims this identity".
/// The TLS certificate pin still decides whether a connection is accepted.
public final class PeerDiscovery {
    public enum StartError: Error { case socketFailed, bindFailed }
    public static let defaultPort: UInt16 = 24_802

    private let queue = DispatchQueue(label: "cursorloom.discovery")
    private var socketFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var beaconTimer: DispatchSourceTimer?
    private let lock = NSLock()
    private var peers: [String: DiscoveredPeer] = [:]
    private var selfID = ""
    private var beacon = Data()
    private let port: UInt16
    private let expiry: TimeInterval

    public var onPeersChanged: (( [DiscoveredPeer] ) -> Void)?

    public init(port: UInt16 = PeerDiscovery.defaultPort, expiry: TimeInterval = 8) {
        self.port = port
        self.expiry = expiry
    }

    deinit { stop() }

    public func start(id: String, name: String, fingerprint: String, servicePort: UInt16) throws {
        stop()
        lock.lock()
        selfID = id
        lock.unlock()
        beacon = try JSONEncoder().encode(PeerBeacon(id: id, name: name, fp: fingerprint, port: servicePort))

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw StartError.socketFailed }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { close(fd); throw StartError.bindFailed }

        var bufferSize: Int32 = 1 << 16
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
        socketFD = fd

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in self?.drain() }
        readSource.resume()
        source = readSource

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.announce()
            self?.prune()
        }
        timer.resume()
        beaconTimer = timer
    }

    public func stop() {
        beaconTimer?.cancel(); beaconTimer = nil
        source?.cancel(); source = nil
        if socketFD >= 0 { close(socketFD); socketFD = -1 }
        lock.lock(); peers.removeAll(); lock.unlock()
    }

    public func snapshot() -> [DiscoveredPeer] {
        lock.lock(); defer { lock.unlock() }
        return peers.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func announce() {
        guard socketFD >= 0 else { return }
        for target in broadcastAddresses() { send(beacon, to: target) }
        send(beacon, to: in_addr(s_addr: INADDR_LOOPBACK))
    }

    private func send(_ payload: Data, to address: in_addr) {
        var destination = sockaddr_in()
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        destination.sin_addr = address
        let sent = payload.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &destination) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, raw.baseAddress, payload.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        _ = sent
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            var sender = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &sender) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketFD, &buffer, buffer.count, 0, $0, &length)
                }
            }
            guard received > 0 else { return }
            guard received < 2048 else { continue }
            let data = Data(buffer[0..<received])
            guard data.count <= 1024,
                  let beacon = try? JSONDecoder().decode(PeerBeacon.self, from: data),
                  beacon.v == PeerBeacon.protocolVersion,
                  beacon.id != selfID,
                  isPlausible(beacon) else { continue }
            var addressBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var host = sender.sin_addr
            inet_ntop(AF_INET, &host, &addressBuffer, socklen_t(INET_ADDRSTRLEN))
            let address = String(cString: addressBuffer)
            let peer = DiscoveredPeer(id: beacon.id, name: String(beacon.name.prefix(64)),
                                      fingerprint: beacon.fp, port: beacon.port,
                                      address: address, lastSeen: Date())
            lock.lock()
            let changed = peers[peer.id]?.address != peer.address || peers[peer.id]?.name != peer.name
            peers[peer.id] = peer
            let snapshot = peers.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onPeersChanged?(snapshot) } }
        }
    }

    private func isPlausible(_ beacon: PeerBeacon) -> Bool {
        UUID(uuidString: beacon.id) != nil && beacon.port != 0
            && !beacon.name.isEmpty && beacon.fp.utf8.count == 64
            && beacon.fp.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-expiry)
        lock.lock()
        let removed = peers.filter { $0.value.lastSeen < cutoff }.map(\.key)
        for key in removed { peers.removeValue(forKey: key) }
        let snapshot = peers.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lock.unlock()
        if !removed.isEmpty { DispatchQueue.main.async { self.onPeersChanged?(snapshot) } }
    }

    private func broadcastAddresses() -> [in_addr] {
        var results: [in_addr] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return results }
        defer { freeifaddrs(interfaces) }
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (Int32(interface.pointee.ifa_flags) & IFF_BROADCAST) != 0,
                  (Int32(interface.pointee.ifa_flags) & IFF_LOOPBACK) == 0,
                  let broadcast = interface.pointee.ifa_dstaddr else { continue }
            let candidate = broadcast.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            if candidate.s_addr != 0 { results.append(candidate) }
        }
        return results
    }
}

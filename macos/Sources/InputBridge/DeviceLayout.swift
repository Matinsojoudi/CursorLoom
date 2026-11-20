import Foundation

/// Grid topology independent of transport and platform UI. Each grid position is
/// a single device; the local device is the origin. Adjacency is never inferred.
public struct DeviceLayout {
    public struct Position: Hashable, Sendable {
        public let x: Int
        public let y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }
    public enum Direction { case left, right, up, down }
    public enum LayoutError: Error { case invalidDevice, occupied, duplicate, deviceLimit, invalidPosition }
    public static let localDevice = "local"
    private var positions: [String: Position] = [localDevice: Position(x: 0, y: 0)]

    public init() {}

    public mutating func add(_ device: String, at position: Position) throws {
        guard !device.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, device.utf8.count <= 128,
              device != Self.localDevice else { throw LayoutError.invalidDevice }
        guard (-100...100).contains(position.x), (-100...100).contains(position.y) else { throw LayoutError.invalidPosition }
        guard positions[device] == nil else { throw LayoutError.duplicate }
        guard positions.count <= DeviceRouter.maximumPeers else { throw LayoutError.deviceLimit }
        guard !positions.values.contains(position) else { throw LayoutError.occupied }
        positions[device] = position
    }

    public mutating func remove(_ device: String) {
        guard device != Self.localDevice else { return }
        positions.removeValue(forKey: device)
    }

    public func neighbor(of device: String, direction: Direction) -> String? {
        guard let position = positions[device] else { return nil }
        let target: Position
        switch direction {
        case .left: target = Position(x: position.x - 1, y: position.y)
        case .right: target = Position(x: position.x + 1, y: position.y)
        case .up: target = Position(x: position.x, y: position.y - 1)
        case .down: target = Position(x: position.x, y: position.y + 1)
        }
        return positions.first { $0.value == target }?.key
    }
}

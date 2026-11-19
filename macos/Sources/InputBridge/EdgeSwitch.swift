import Foundation

/// Pure edge-switch detector. Coordinates are normalized primary-display positions.
/// Explicit arming prevents accidental activation after connect or reconnect.
public struct EdgeSwitch {
    public enum Edge { case left, right }
    public enum Event: Equatable { case enterRemote, returnLocal }
    public let edge: Edge
    public let delay: TimeInterval
    private let margin: Double
    private var enteredAt: TimeInterval?
    public private(set) var isRemote = false
    public private(set) var armed = false

    public init(edge: Edge, delay: TimeInterval = 0.25, margin: Double = 0.002) {
        self.edge = edge
        self.delay = max(0, delay)
        self.margin = min(max(0, margin), 0.1)
    }

    public mutating func arm() { armed = true; isRemote = false; enteredAt = nil }
    public mutating func disarm() { armed = false; isRemote = false; enteredAt = nil }
    public mutating func returnToLocal() -> Event? {
        guard armed, isRemote else { return nil }
        isRemote = false
        enteredAt = nil
        return .returnLocal
    }

    /// Call repeatedly with a monotonic timestamp, including when stationary at edge.
    public mutating func observe(x: Double, time: TimeInterval) -> Event? {
        guard armed, !isRemote, x.isFinite, time.isFinite, (0...1).contains(x) else {
            enteredAt = nil
            return nil
        }
        let atEdge = edge == .left ? x <= margin : x >= 1 - margin
        guard atEdge else { enteredAt = nil; return nil }
        if let enteredAt, time >= enteredAt {
            guard time - enteredAt >= delay else { return nil }
            isRemote = true
            self.enteredAt = nil
            return .enterRemote
        }
        enteredAt = time
        if delay == 0 { isRemote = true; self.enteredAt = nil; return .enterRemote }
        return nil
    }
}

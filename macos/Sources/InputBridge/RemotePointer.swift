import Foundation

/// Integrates relative pointer movement on the remote primary display.
/// This state model does not warp or suppress local operating-system input.
public struct RemotePointer {
    public enum Side { case left, right }
    public enum Result: Equatable { case move(x: Double, y: Double), exit(y: Double), unchanged }
    public private(set) var x: Double
    public private(set) var y: Double
    private let returnSide: Side

    public init(returnSide: Side, y: Double) {
        self.returnSide = returnSide
        self.x = returnSide == .left ? 0 : 1
        self.y = y.isFinite ? min(max(y, 0), 1) : 0.5
    }

    /// dx and dy are normalized to the remote screen size. Crossing the return
    /// edge requests release, while other edges clamp the pointer to the screen.
    public mutating func move(dx: Double, dy: Double) -> Result {
        guard dx.isFinite, dy.isFinite else { return .unchanged }
        let nextX = x + dx
        let nextY = min(max(y + dy, 0), 1)
        if (returnSide == .left && nextX < 0) || (returnSide == .right && nextX > 1) {
            y = nextY
            return .exit(y: nextY)
        }
        x = min(max(nextX, 0), 1)
        y = nextY
        return .move(x: x, y: y)
    }
}

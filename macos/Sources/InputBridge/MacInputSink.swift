import ApplicationServices
import AppKit
import Foundation

/// Explicitly invoked local event injection. Never attach this to an unauthenticated connection.
/// All calls must be made on the same thread; releaseAll must be called on disconnect.
public final class MacInputSink {
    private var pressedKeys: Set<CGKeyCode> = []
    private var pressedButtons: Set<Int> = []

    public init() {}

    /// USB HID keyboard usage to macOS virtual key code. Unsupported usages fail closed.
    public static func keyCode(for usage: Int) -> CGKeyCode? {
        // USB HID keyboard page 0x07. These are hardware positions, not text characters.
        let codes: [Int: CGKeyCode] = [
            4: 0, 5: 11, 6: 8, 7: 2, 8: 14, 9: 3, 10: 5, 11: 4,
            12: 34, 13: 38, 14: 40, 15: 37, 16: 46, 17: 45, 18: 31,
            19: 35, 20: 12, 21: 15, 22: 1, 23: 17, 24: 32, 25: 9,
            26: 13, 27: 7, 28: 16, 29: 6, 30: 18, 31: 19, 32: 20,
            33: 21, 34: 23, 35: 22, 36: 26, 37: 28, 38: 25, 39: 29,
            40: 36, 41: 53, 42: 51, 43: 48, 44: 49, 45: 27, 46: 24,
            47: 33, 48: 30, 49: 42, 51: 41, 52: 39, 53: 50, 54: 43,
            55: 47, 56: 44, 57: 57, 58: 122, 59: 120, 60: 99, 61: 118,
            62: 96, 63: 97, 64: 98, 65: 100, 66: 101, 67: 109,
            68: 103, 69: 111, 73: 114, 74: 115, 75: 116, 76: 117,
            77: 119, 78: 121, 79: 124, 80: 123, 81: 125, 82: 126,
            224: 59, 225: 56, 226: 58, 227: 55, 228: 62, 229: 60,
            230: 61, 231: 54
        ]
        return codes[usage]
    }

    @discardableResult
    public func key(usage: Int, down: Bool) -> Bool {
        guard AXIsProcessTrusted(), let code = Self.keyCode(for: usage),
              let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return false }
        if down { pressedKeys.insert(code) } else { pressedKeys.remove(code) }
        event.post(tap: .cghidEventTap)
        return true
    }

    @discardableResult
    public func move(to point: CGPoint) -> Bool {
        guard AXIsProcessTrusted(), point.x.isFinite, point.y.isFinite,
              let display = NSScreen.main,
              display.frame.width > 0, display.frame.height > 0 else { return false }
        // Normalized primary-display coordinates, clamped to visible bounds.
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let position = CGPoint(x: bounds.minX + min(max(point.x, 0), 1) * max(bounds.width - 1, 0),
                               y: bounds.minY + min(max(point.y, 0), 1) * max(bounds.height - 1, 0))
        let active = pressedButtons.sorted().first
        let type: CGEventType = active == 0 ? .leftMouseDragged : active == 1 ? .rightMouseDragged : .mouseMoved
        let button: CGMouseButton = active == 1 ? .right : .left
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: button) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }

    @discardableResult
    public func button(_ button: Int, down: Bool) -> Bool {
        guard AXIsProcessTrusted(), button == 0 || button == 1,
              let current = CGEvent(source: nil) else { return false }
        let mouseButton: CGMouseButton = button == 0 ? .left : .right
        let type: CGEventType = button == 0 ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: current.location, mouseButton: mouseButton) else { return false }
        if down { pressedButtons.insert(button) } else { pressedButtons.remove(button) }
        event.post(tap: .cghidEventTap)
        return true
    }

    @discardableResult
    public func scroll(vertical: Int, horizontal: Int) -> Bool {
        guard AXIsProcessTrusted(), (-100...100).contains(vertical), (-100...100).contains(horizontal),
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                                  wheel1: Int32(vertical), wheel2: Int32(horizontal), wheel3: 0) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }

    /// Call only after user consent and successful peer authentication.
    @discardableResult
    public func apply(_ input: RemoteInput, allowClipboard: Bool = false) -> Bool {
        switch input {
        case let .key(usage, down): return key(usage: usage, down: down)
        case let .pointer(x, y): return move(to: CGPoint(x: x, y: y))
        case let .button(index, down): return button(index, down: down)
        case let .scroll(vertical, horizontal): return scroll(vertical: vertical, horizontal: horizontal)
        case let .clipboard(text):
            guard allowClipboard, text.utf8.count <= 48_000 else { return false }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        case .releaseAll:
            return releaseAll()
        }
    }

    @discardableResult
    public func releaseAll() -> Bool {
        guard AXIsProcessTrusted() else { return pressedKeys.isEmpty && pressedButtons.isEmpty }
        for code in Array(pressedKeys) {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { continue }
            event.post(tap: .cghidEventTap)
            pressedKeys.remove(code)
        }
        for button in Array(pressedButtons) { _ = self.button(button, down: false) }
        // CGEvent.post provides no delivery acknowledgement; this reports creation only.
        return pressedKeys.isEmpty && pressedButtons.isEmpty
    }
}

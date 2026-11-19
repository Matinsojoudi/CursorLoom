import ApplicationServices
import CoreGraphics
import Foundation

/// Opt-in passive input capture. Does not suppress local input or transmit events.
/// The owner must keep this object alive and call start/stop on the main thread.
/// Never start capture without informed consent; captured keystrokes are sensitive.
public final class MacInputCapture {
    public enum CaptureError: Error { case alreadyStarted, permissionDenied, tapCreationFailed }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: (RemoteInput) -> Void
    private var pressedModifierUsages: Set<Int> = []

    public init(handler: @escaping (RemoteInput) -> Void) {
        self.handler = handler
    }

    public func start() throws {
        precondition(Thread.isMainThread)
        guard tap == nil else { throw CaptureError.alreadyStarted }
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else { throw CaptureError.permissionDenied }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .keyDown, .keyUp, .flagsChanged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                               options: .listenOnly, eventsOfInterest: mask,
                                               callback: captureCallback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            throw CaptureError.tapCreationFailed
        }
        guard let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            throw CaptureError.tapCreationFailed
        }
        tap = eventTap
        source = runSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    public func stop() {
        precondition(Thread.isMainThread)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        pressedModifierUsages.removeAll()
    }

    deinit {
        // Invalidation prevents callbacks retaining a dangling unmanaged pointer.
        if let tap { CFMachPortInvalidate(tap) }
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Stop rather than silently losing key-up events. Owner can release remote input.
            stop()
            handler(.releaseAll)
            return
        }
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            let bounds = CGDisplayBounds(CGMainDisplayID())
            guard bounds.width > 1, bounds.height > 1, bounds.contains(event.location) else { return }
            handler(.pointer(x: min(max((event.location.x - bounds.minX) / (bounds.width - 1), 0), 1),
                             y: min(max((event.location.y - bounds.minY) / (bounds.height - 1), 0), 1)))
        case .leftMouseDown: handler(.button(index: 0, down: true))
        case .leftMouseUp: handler(.button(index: 0, down: false))
        case .rightMouseDown: handler(.button(index: 1, down: true))
        case .rightMouseUp: handler(.button(index: 1, down: false))
        case .keyDown, .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard let usage = Self.usage(for: code) else { return }
            handler(.key(usage: usage, down: type == .keyDown))
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard let usage = Self.usage(for: code), let flag = Self.modifierFlag(for: usage) else { return }
            // flagsChanged identifies the physical modifier; aggregate flags cannot
            // distinguish left/right when both are held, so track each transition.
            let down = !pressedModifierUsages.contains(usage) && event.flags.contains(flag)
            if down { pressedModifierUsages.insert(usage) } else { pressedModifierUsages.remove(usage) }
            handler(.key(usage: usage, down: down))
        case .scrollWheel:
            let vertical = max(-100, min(100, event.getIntegerValueField(.scrollWheelEventDeltaAxis1)))
            let horizontal = max(-100, min(100, event.getIntegerValueField(.scrollWheelEventDeltaAxis2)))
            if vertical != 0 || horizontal != 0 { handler(.scroll(vertical: Int(vertical), horizontal: Int(horizontal))) }
        default: break
        }
    }

    private static let reverseKeyCodes: [Int64: Int] = {
        var result: [Int64: Int] = [:]
        for usage in 0...255 {
            if let code = MacInputSink.keyCode(for: usage), result[Int64(code)] == nil {
                result[Int64(code)] = usage
            }
        }
        return result
    }()

    public static func usage(for keyCode: Int64) -> Int? {
        reverseKeyCodes[keyCode]
    }

    private static func modifierFlag(for usage: Int) -> CGEventFlags? {
        switch usage {
        case 224, 228: return .maskControl
        case 225, 229: return .maskShift
        case 226, 230: return .maskAlternate
        case 227, 231: return .maskCommand
        default: return nil
        }
    }
}

private func captureCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                             userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<MacInputCapture>.fromOpaque(userInfo).takeUnretainedValue()
    owner.receive(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

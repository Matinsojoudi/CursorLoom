import AppKit
import Foundation

/// Explicit, main-thread-only text clipboard polling. Never starts automatically.
/// Call only when a user has opted in to sharing clipboard contents.
public final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private let onText: (String) -> Void

    public init(pasteboard: NSPasteboard = .general, onText: @escaping (String) -> Void) {
        precondition(Thread.isMainThread)
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.onText = onText
    }

    public func poll() {
        precondition(Thread.isMainThread)
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard let text = pasteboard.string(forType: .string), text.utf8.count <= 48_000 else { return }
        onText(text)
    }

    /// Prevents echo when applying an authenticated remote clipboard update.
    @discardableResult
    public func applyRemote(_ text: String) -> Bool {
        precondition(Thread.isMainThread)
        guard text.utf8.count <= 48_000 else { return false }
        pasteboard.clearContents()
        let result = pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        return result
    }
}

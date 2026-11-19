import Foundation

public enum FrameError: Error, Equatable {
    case frameTooLarge
    case emptyFrame
    case truncatedFrame
}

/// Incrementally extracts newline-delimited messages without buffering more than one frame.
/// A framing error invalidates the decoder; close the connection after an error.
public struct FrameDecoder {
    private var pending = Data()
    private var failed = false

    public init() {}

    public mutating func append(_ bytes: Data) throws -> [Envelope] {
        guard !failed else { throw FrameError.truncatedFrame }
        var messages: [Envelope] = []
        do {
            for byte in bytes {
                if byte == 0x0a {
                    guard !pending.isEmpty else { throw FrameError.emptyFrame }
                    pending.append(byte)
                    messages.append(try MessageCodec.decode(pending))
                    pending.removeAll(keepingCapacity: true)
                } else {
                    // One byte must remain available for the terminating newline.
                    guard pending.count < MessageCodec.maximumBytes - 1 else {
                        throw FrameError.frameTooLarge
                    }
                    pending.append(byte)
                }
            }
            return messages
        } catch {
            pending.removeAll()
            failed = true
            throw error
        }
    }

    public mutating func finish() throws {
        guard !failed, pending.isEmpty else {
            failed = true
            pending.removeAll()
            throw FrameError.truncatedFrame
        }
    }
}

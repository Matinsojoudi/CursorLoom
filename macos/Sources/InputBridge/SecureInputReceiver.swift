import Foundation
import Network

/// Handles a single already configured, mutually authenticated connection.
/// All calls and callbacks run on the supplied serial queue. It never starts itself;
/// the owner must obtain explicit user consent and dispatch UI operations safely.
public final class SecureInputReceiver {
    public enum ReceiverError: Error { case rejectedInput, handshakeTimeout }
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let apply: (RemoteInput) -> Bool
    private let release: () -> Void
    private let finished: (Error?) -> Void
    private var decoder = FrameDecoder()
    private var closed = false
    private var started = false
    private var handshakeDeadline: DispatchWorkItem?

    public init(connection: NWConnection, queue: DispatchQueue,
                apply: @escaping (RemoteInput) -> Bool,
                release: @escaping () -> Void, finished: @escaping (Error?) -> Void) {
        self.connection = connection
        self.queue = queue
        self.apply = apply
        self.release = release
        self.finished = finished
    }

    public func start() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !started, !closed else { return }
        started = true
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.handshakeDeadline?.cancel()
                self.handshakeDeadline = nil
                self.receive()
            case .waiting(let error), .failed(let error): self.close(error)
            case .cancelled: self.close(nil)
            default: break
            }
        }
        let deadline = DispatchWorkItem { [weak self] in self?.close(ReceiverError.handshakeTimeout) }
        handshakeDeadline = deadline
        queue.asyncAfter(deadline: .now() + 10, execute: deadline)
        connection.start(queue: queue)
    }

    public func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        close(nil)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            if let error { self.close(error); return }
            do {
                if let data {
                    for message in try self.decoder.append(data) {
                        guard self.apply(try InputValidator.parse(message)) else { throw ReceiverError.rejectedInput }
                    }
                }
                if complete { try self.decoder.finish(); self.close(nil) }
                else { self.receive() }
            } catch { self.close(error) }
        }
    }

    private func close(_ error: Error?) {
        guard !closed else { return }
        closed = true
        handshakeDeadline?.cancel()
        handshakeDeadline = nil
        connection.cancel()
        release()
        finished(error)
    }
}

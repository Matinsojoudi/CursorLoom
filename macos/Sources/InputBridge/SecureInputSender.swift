import Foundation
import Network

/// Single-use sender over an already configured mutually authenticated TLS connection.
/// All methods and callbacks must run on the supplied serial queue. No automatic capture,
/// connection, or retries: the caller must obtain consent and stop capture on failure.
public final class SecureInputSender {
    public enum SenderError: Error { case notReady, queueOverflow, unexpectedPeerData }
    private enum State { case idle, connecting, ready, closed }
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let onClosed: (Error?) -> Void
    private var state: State = .idle
    private var pendingBytes = 0
    private let pendingLimit = 256 * 1024

    public init(connection: NWConnection, queue: DispatchQueue, onClosed: @escaping (Error?) -> Void) {
        self.connection = connection
        self.queue = queue
        self.onClosed = onClosed
    }

    public func start(onReady: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard case .idle = state else { return }
        state = .connecting
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard case .connecting = self.state else { return }
                self.state = .ready
                self.monitorPeerClosure()
                onReady()
            case .failed(let error): self.close(error)
            case .cancelled: self.close(nil)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    public func send(_ event: RemoteInput) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        guard case .ready = state else { throw SenderError.notReady }
        let data = try InputEncoding.encode(event)
        guard pendingBytes <= pendingLimit - data.count else {
            close(SenderError.queueOverflow)
            throw SenderError.queueOverflow
        }
        pendingBytes += data.count
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.pendingBytes -= data.count
            if let error { self.close(error) }
        })
    }

    /// Receiver must independently release keys when the connection closes.
    public func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        close(nil)
    }

    private func monitorPeerClosure() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let error { self.close(error); return }
            // Protocol is currently one-way; any incoming application data is unexpected.
            if let data, !data.isEmpty { self.close(SenderError.unexpectedPeerData); return }
            if complete { self.close(nil); return }
            guard case .ready = self.state else { return }
            self.monitorPeerClosure()
        }
    }

    private func close(_ error: Error?) {
        guard case .closed = state else {
            state = .closed
            connection.cancel()
            onClosed(error)
            return
        }
    }
}

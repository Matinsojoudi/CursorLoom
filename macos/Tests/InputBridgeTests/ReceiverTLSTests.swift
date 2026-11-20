import XCTest
import Foundation
import Network
import Security
@testable import InputBridge

final class ReceiverTLSTests: XCTestCase {
    func testMutualTLSReceiverAndInputFrame() throws {
        guard ProcessInfo.processInfo.environment["CURSORLOOM_TLS_INTEGRATION"] == "1" else { throw XCTSkip("TLS integration disabled") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func command(_ args: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw NSError(domain: "openssl", code: Int(process.terminationStatus)) }
        }
        func identity(_ name: String) throws -> SecIdentity {
            let key = dir.appendingPathComponent(name + ".key").path
            let cert = dir.appendingPathComponent(name + ".pem").path
            let bundle = dir.appendingPathComponent(name + ".p12").path
            try command(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "1", "-subj", "/CN=\(name)"])
            try command(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", bundle, "-passout", "pass:test"])
            return try Identity.fromPKCS12(Data(contentsOf: URL(fileURLWithPath: bundle)), password: "test")
        }
        let serverIdentity = try identity("server")
        let clientIdentity = try identity("client")
        let wrongIdentity = try identity("untrusted")
        let queue = DispatchQueue(label: "receiver-test")
        let listener = try SecureTransport.listener(port: 0, fingerprint: Identity.fingerprint(of: clientIdentity), identity: serverIdentity, callbackQueue: queue)
        let ready = expectation(description: "listener ready")
        let applied = expectation(description: "key applied")
        let released = expectation(description: "keys released on disconnect")
        var receiver: SecureInputReceiver?
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            receiver = SecureInputReceiver(connection: connection, queue: queue, apply: { input in
                XCTAssertEqual(input, .key(usage: 4, down: true)); applied.fulfill(); return true
            }, release: { released.fulfill() }, finished: { _ in })
            receiver?.start()
        }
        listener.start(queue: queue)
        defer { listener.cancel(); withExtendedLifetime(receiver) {} }
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port?.rawValue)
        let client = try SecureTransport.client(host: "127.0.0.1", port: port, fingerprint: Identity.fingerprint(of: serverIdentity), identity: clientIdentity, callbackQueue: queue)
        let sent = expectation(description: "sent")
        client.stateUpdateHandler = { state in
            if case .ready = state {
                do {
                    client.send(content: try InputEncoding.encode(.key(usage: 4, down: true)), completion: .contentProcessed { error in
                        XCTAssertNil(error); sent.fulfill()
                    })
                } catch { XCTFail("Encoding failed: \(error)") }
            }
        }
        client.start(queue: queue)
        wait(for: [sent, applied], timeout: 10)
        client.cancel()
        wait(for: [released], timeout: 10)

        let rejected = expectation(description: "untrusted client rejected")
        let notApplied = expectation(description: "untrusted input never applied")
        notApplied.isInverted = true
        listener.newConnectionHandler = { connection in
            receiver = SecureInputReceiver(connection: connection, queue: queue, apply: { _ in
                notApplied.fulfill(); return true
            }, release: {}, finished: { _ in rejected.fulfill() })
            receiver?.start()
        }
        let wrongClient = try SecureTransport.client(host: "127.0.0.1", port: port,
                                                     fingerprint: Identity.fingerprint(of: serverIdentity),
                                                     identity: wrongIdentity, callbackQueue: queue)
        wrongClient.stateUpdateHandler = { state in
            if case .ready = state, let data = try? InputEncoding.encode(.key(usage: 4, down: true)) {
                wrongClient.send(content: data, completion: .contentProcessed { _ in })
            }
        }
        wrongClient.start(queue: queue)
        wait(for: [rejected, notApplied], timeout: 4)
        wrongClient.cancel()
    }
}

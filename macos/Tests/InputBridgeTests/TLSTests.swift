import XCTest
import Foundation
import Security
import CryptoKit
import Network
@testable import InputBridge

final class TLSTests: XCTestCase {
    func testTLSClientAcceptsPinnedServerAndRejectsWrongPin() throws {
        guard ProcessInfo.processInfo.environment["CURSORLOOM_TLS_INTEGRATION"] == "1" else {
            throw XCTSkip("Set CURSORLOOM_TLS_INTEGRATION=1 to run OpenSSL loopback integration test")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func openssl(_ arguments: [String]) throws {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            task.arguments = arguments
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try task.run(); task.waitUntilExit()
            XCTAssertEqual(task.terminationStatus, 0, "OpenSSL failed")
            guard task.terminationStatus == 0 else { throw NSError(domain: "OpenSSL", code: Int(task.terminationStatus)) }
        }
        let serverKey = directory.appendingPathComponent("server.key").path
        let serverCert = directory.appendingPathComponent("server.pem").path
        let clientKey = directory.appendingPathComponent("client.key").path
        let clientCert = directory.appendingPathComponent("client.pem").path
        let clientBundle = directory.appendingPathComponent("client.p12").path
        for (name, key, cert) in [("server", serverKey, serverCert), ("client", clientKey, clientCert)] {
            try openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                         "-days", "1", "-subj", "/CN=\(name)"])
        }
        try openssl(["pkcs12", "-export", "-inkey", clientKey, "-in", clientCert, "-out", clientBundle,
                     "-passout", "pass:test-password"])
        let identity = try Identity.fromPKCS12(Data(contentsOf: URL(fileURLWithPath: clientBundle)), password: "test-password")
        let pem = try String(contentsOfFile: serverCert, encoding: .utf8)
        let base64 = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: base64) else { XCTFail("Invalid certificate"); return }
        let pin = Data(SHA256.hash(data: der))
        let probe = try XCTUnwrap(NWListener(using: .tcp, on: .any))
        probe.newConnectionHandler = { $0.cancel() }
        let ready = expectation(description: "allocate port")
        probe.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        let queue = DispatchQueue(label: "tls-test")
        probe.start(queue: queue)
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(probe.port?.rawValue)
        probe.cancel()
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        server.arguments = ["s_server", "-accept", String(port), "-cert", serverCert, "-key", serverKey,
                            "-Verify", "1", "-CAfile", clientCert, "-tls1_3", "-quiet"]
        server.standardInput = Pipe()
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        // Server startup races are avoided by retrying separate connections below.
        func attempt(pin: Data, shouldSucceed: Bool) throws {
            let finished = expectation(description: shouldSucceed ? "trusted" : "rejected")
            let connection = try SecureTransport.client(host: "127.0.0.1", port: port, fingerprint: pin,
                                                        identity: identity, callbackQueue: queue)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    XCTAssertTrue(shouldSucceed, "Unexpected trust")
                    connection.cancel(); finished.fulfill()
                case .waiting, .failed:
                    XCTAssertFalse(shouldSucceed, "Trusted connection failed")
                    connection.cancel(); finished.fulfill()
                default: break
                }
            }
            connection.start(queue: queue)
            wait(for: [finished], timeout: 10)
            connection.cancel()
        }
        try attempt(pin: pin, shouldSucceed: true)
        try attempt(pin: Data(repeating: 0, count: 32), shouldSucceed: false)
    }
}

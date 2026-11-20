import XCTest
import Foundation
@testable import InputBridge

final class DeviceIdentityTests: XCTestCase {
    func testGeneratedCertificateIsValidX509() throws {
        let created = try SelfSignedCertificate.make(commonName: "CursorLoom Test Device")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let derURL = directory.appendingPathComponent("cert.der")
        try created.der.write(to: derURL)

        func run(_ arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: output, as: UTF8.self)
        }

        let text = try run(["x509", "-inform", "DER", "-in", derURL.path, "-noout", "-text"])
        XCTAssertTrue(text.contains("X509v3 Extended Key Usage"), "openssl could not parse certificate: \(text)")
        XCTAssertTrue(text.contains("TLS Web Client Authentication"), text)

        XCTAssertTrue(text.contains("Not Before"), text)
        XCTAssertTrue(text.contains("Not After"), text)

        let details = try run(["x509", "-inform", "DER", "-in", derURL.path, "-noout", "-subject"])
        XCTAssertTrue(details.contains("CursorLoom Test Device"), details)

        // The leaf is CA:FALSE, so openssl verify against itself is expected to fail;
        // instead confirm openssl reads the same bytes we hashed for pinning.
        let printed = try run(["x509", "-inform", "DER", "-in", derURL.path, "-noout", "-fingerprint", "-sha256"])
        let expected = created.fingerprint.map { String(format: "%02X", $0) }.joined(separator: ":")
        XCTAssertTrue(printed.uppercased().contains(expected), printed)

        XCTAssertNotNil(created.identity)
        XCTAssertEqual(created.fingerprint.count, 32)
    }

    func testIdentityPersistsAcrossReloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileIdentityStorage(url: directory.appendingPathComponent("identity.json"))
        let first = try DeviceIdentity.loadOrCreate(storage: storage, name: "Test Mac")
        let second = try DeviceIdentity.loadOrCreate(storage: storage, name: "Ignored On Reload")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(second.name, "Test Mac")
        XCTAssertEqual(first.fingerprintHex().count, 64)
        try storage.clear()
        let third = try DeviceIdentity.loadOrCreate(storage: storage, name: "Test Mac")
        XCTAssertNotEqual(third.id, first.id, "Clearing storage must create a fresh identity")
    }
}

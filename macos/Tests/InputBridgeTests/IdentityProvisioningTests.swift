import XCTest
@testable import InputBridge

final class IdentityProvisioningTests: XCTestCase {
    func testEphemeralKeysHaveDistinctPublicFingerprints() throws {
        let first = try IdentityProvisioning.createKey(label: "one")
        let second = try IdentityProvisioning.createKey(label: "two")
        let firstPin = try IdentityProvisioning.publicKeyFingerprint(first)
        XCTAssertEqual(firstPin.count, 32)
        XCTAssertEqual(try IdentityProvisioning.publicKeyFingerprint(first), firstPin)
        XCTAssertNotEqual(try IdentityProvisioning.publicKeyFingerprint(second), firstPin)
        XCTAssertThrowsError(try IdentityProvisioning.createKey(label: " "))
    }
}

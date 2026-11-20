import Foundation
import Security
import CryptoKit

/// Generates an ephemeral P-256 key. This is not a persistent or non-exportable identity.
/// Certificate creation and enrollment are intentionally not implemented here.
/// Not yet used by the app's PKCS#12-based transport.
public enum IdentityProvisioning {
    public enum ProvisionError: Error { case invalidLabel, creationFailed, publicKeyMissing, exportFailed }

    public static func createKey(label: String) throws -> SecKey {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, label.utf8.count <= 128 else {
            throw ProvisionError.invalidLabel
        }
        let parameters: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false,
                kSecAttrLabel as String: label
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(parameters as CFDictionary, &error) else {
            if let error { throw error.takeRetainedValue() as Error }
            throw ProvisionError.creationFailed
        }
        return key
    }

    public static func publicKeyFingerprint(_ key: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(key) else { throw ProvisionError.publicKeyMissing }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            if let error { throw error.takeRetainedValue() as Error }
            throw ProvisionError.exportFailed
        }
        return Data(SHA256.hash(data: data))
    }
}

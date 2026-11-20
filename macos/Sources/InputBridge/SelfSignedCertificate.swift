import CryptoKit
import Foundation
import Security

/// Builds a short-lived self-signed P-256 certificate so the app can create its own
/// device identity without any user-managed certificate files.
/// The certificate is not trusted by any CA; peers authenticate it by pinned fingerprint.
public enum SelfSignedCertificate {
    public enum CertificateError: Error { case keyGenerationFailed, publicKeyUnavailable, signingFailed, invalidCertificate, identityUnavailable }

    public struct Created {
        public let key: SecKey
        public let certificate: SecCertificate
        public let der: Data
        public var fingerprint: Data { Data(SHA256.hash(data: der)) }
        public var identity: SecIdentity? { SecIdentityCreate(kCFAllocatorDefault, certificate, key) }
    }

    public static func make(commonName: String, validDays: Int = 825) throws -> Created {
        guard (1...825).contains(validDays) else { throw CertificateError.invalidCertificate }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: false]
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw CertificateError.keyGenerationFailed
        }
        guard let publicKey = SecKeyCopyPublicKey(key),
              let raw = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw CertificateError.publicKeyUnavailable
        }

        let name = DER.sequence([DER.set([DER.sequence([DER.oid(OID.commonName), DER.utf8String(commonName)])])])
        let algorithm = DER.sequence([DER.oid(OID.ecdsaWithSHA256)])
        let now = Date()
        let validity = DER.sequence([DER.utcTime(now.addingTimeInterval(-60)),
                                     DER.utcTime(now.addingTimeInterval(Double(validDays) * 86_400))])
        let spki = DER.sequence([
            DER.sequence([DER.oid(OID.ecPublicKey), DER.oid(OID.prime256v1)]),
            DER.bitString(Array(raw))
        ])

        let basicConstraints = DER.sequence([DER.oid(OID.basicConstraints), DER.boolean(true),
                                             DER.octetString(DER.sequence([]))])
        let keyUsage = DER.sequence([DER.oid(OID.keyUsage), DER.boolean(true),
                                     DER.octetString(DER.bitString([0x80]))])
        let eku = DER.sequence([DER.oid(OID.extendedKeyUsage),
                                DER.octetString(DER.sequence([DER.oid(OID.clientAuth), DER.oid(OID.serverAuth)]))])
        let extensions = DER.explicit(0xA3, DER.sequence([basicConstraints, keyUsage, eku]))

        var serial = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] &= 0x7F
        if serial[0] == 0 { serial[0] = 1 }

        let tbs = DER.sequence([
            DER.explicit(0xA0, DER.integer([0x02])),
            DER.integer(serial),
            algorithm,
            name, validity, name, spki, extensions
        ])

        guard let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256,
                                                    Data(tbs) as CFData, &error) as Data? else {
            throw CertificateError.signingFailed
        }
        let certificateDER = Data(DER.sequence([tbs, algorithm, DER.bitString(Array(signature))]))
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw CertificateError.invalidCertificate
        }
        return Created(key: key, certificate: certificate, der: certificateDER)
    }
}

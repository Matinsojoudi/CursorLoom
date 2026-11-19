import Foundation
import Security
import CryptoKit

/// Imports an explicitly chosen PKCS#12 identity for one session. The caller owns
/// the passphrase and must not log it or persist it in application preferences.
public enum Identity {
    public enum ImportError: Error { case failed(OSStatus), noIdentity }

    public static func fromPKCS12(_ bytes: Data, password: String) throws -> SecIdentity {
        var imported: CFArray?
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        let status = SecPKCS12Import(bytes as CFData, options, &imported)
        guard status == errSecSuccess else { throw ImportError.failed(status) }
        guard let entries = imported as? [[String: Any]],
              let item = entries.first?[kSecImportItemIdentity as String],
              CFGetTypeID(item as CFTypeRef) == SecIdentityGetTypeID() else { throw ImportError.noIdentity }
        // Core Foundation type ID check above proves this cast.
        return (item as! SecIdentity)
    }

    public static func fingerprint(of identity: SecIdentity) throws -> Data {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate else { throw ImportError.failed(status) }
        return Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
    }
}

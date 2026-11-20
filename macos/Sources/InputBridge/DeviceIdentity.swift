import CryptoKit
import Foundation
import Security

/// Persists the generated identity. The private key is exported only to be stored
/// in the login keychain; it must never be written to a world-readable location.
public protocol IdentityStorage {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func clear() throws
}

public struct KeychainIdentityStorage: IdentityStorage {
    private let service: String
    private let account: String

    public init(service: String = "com.cursorloom.identity", account: String = "device") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() throws -> Data? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw IdentityError.storage(status) }
        return data
    }

    public func save(_ data: Data) throws {
        try clear()
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw IdentityError.storage(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw IdentityError.storage(status) }
    }
}

/// Test-only storage. File permissions are 0600, but this is not suitable for
/// production because an unencrypted key file is easy to exfiltrate.
public struct FileIdentityStorage: IdentityStorage {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

public enum IdentityError: Error { case storage(OSStatus), corrupt, creationFailed }

/// The user-visible device identity. Created automatically on first launch so that
/// nobody has to manage certificate files, passwords or fingerprints.
public final class DeviceIdentity {
    public let id: String
    public let name: String
    public let certificate: SecCertificate
    public let identity: SecIdentity
    public let fingerprint: Data

    private struct Blob: Codable {
        let id: String
        let name: String
        let key: Data
        let certificate: Data
    }

    private init(id: String, name: String, certificate: SecCertificate, identity: SecIdentity, fingerprint: Data) {
        self.id = id
        self.name = name
        self.certificate = certificate
        self.identity = identity
        self.fingerprint = fingerprint
    }

    public static func loadOrCreate(storage: IdentityStorage = DeviceIdentity.defaultStorage(),
                                    name: String = DeviceIdentity.defaultName()) throws -> DeviceIdentity {
        if let data = try storage.load(), let stored = try? JSONDecoder().decode(Blob.self, from: data),
           let restored = try? restore(stored) {
            return restored
        }
        let created = try SelfSignedCertificate.make(commonName: "CursorLoom \(UUID().uuidString.prefix(8))")
        guard let identity = created.identity else { throw IdentityError.creationFailed }
        let newID = UUID().uuidString
        let blob = Blob(id: newID, name: name, key: try exportKey(created.key), certificate: created.der)
        try storage.save(try JSONEncoder().encode(blob))
        return DeviceIdentity(id: newID, name: name, certificate: created.certificate,
                              identity: identity, fingerprint: created.fingerprint)
    }

    private static func restore(_ blob: Blob) throws -> DeviceIdentity {
        guard let certificate = SecCertificateCreateWithData(nil, blob.certificate as CFData) else {
            throw IdentityError.corrupt
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(blob.key as CFData, attributes as CFDictionary, &error) else {
            throw IdentityError.corrupt
        }
        guard let identity = SecIdentityCreate(kCFAllocatorDefault, certificate, key) else {
            throw IdentityError.creationFailed
        }
        let der = SecCertificateCopyData(certificate) as Data
        let fingerprint = Data(SHA256.hash(data: der))
        return DeviceIdentity(id: blob.id, name: blob.name, certificate: certificate,
                              identity: identity, fingerprint: fingerprint)
    }

    private static func exportKey(_ key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw IdentityError.creationFailed
        }
        return data
    }

    /// Alpha builds are re-signed on every install, which invalidates keychain ACLs
    /// for an ad-hoc signature. The key therefore lives in a 0600 file inside the app's
    /// Application Support directory. This is weaker than the keychain and must be
    /// replaced once the app is signed with a stable identity.
    public static func defaultStorage() -> IdentityStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileIdentityStorage(url: base.appendingPathComponent("CursorLoom/identity.json"))
    }

    public static func defaultName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    public func fingerprintHex() -> String {
        fingerprint.map { String(format: "%02x", $0) }.joined()
    }
}

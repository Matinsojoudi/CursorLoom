import Foundation
import Network
import Security
import CryptoKit

/// Creates a TLS 1.3 client that accepts exactly one SHA-256 certificate fingerprint.
/// Fingerprint must be verified out-of-band before connection. No TOFU fallback.
public enum SecureTransport {
    public enum ConfigurationError: Error { case invalidFingerprint, invalidPort, invalidIdentity }

    public static func parseFingerprint(_ value: String) throws -> Data {
        let compact = value.filter { $0 != ":" && !$0.isWhitespace }
        guard compact.utf8.count == 64, compact.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw ConfigurationError.invalidFingerprint
        }
        var result = Data()
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else { throw ConfigurationError.invalidFingerprint }
            result.append(byte)
            index = next
        }
        return result
    }

    /// Creates a connection but does not start it. User must explicitly start.
    public static func client(host: String, port: UInt16, fingerprint: Data,
                              identity: SecIdentity, callbackQueue: DispatchQueue) throws -> NWConnection {
        guard fingerprint.count == 32 else { throw ConfigurationError.invalidFingerprint }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw ConfigurationError.invalidPort }
        let tls = NWProtocolTLS.Options()
        guard let localIdentity = sec_identity_create(identity) else { throw ConfigurationError.invalidIdentity }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, localIdentity)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let reference = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(reference) as? [SecCertificate],
                  let leaf = chain.first else { complete(false); return }
            let actual = Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data))
            complete(constantTimeEqual(actual, fingerprint))
        }, callbackQueue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        return NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

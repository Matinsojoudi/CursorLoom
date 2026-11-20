import Foundation

/// Minimal DER encoder used only to build a self-signed device certificate.
/// Not a general-purpose ASN.1 library.
enum DER {
    static func length(_ count: Int) -> [UInt8] {
        precondition(count >= 0)
        if count < 0x80 { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func sequence(_ items: [[UInt8]]) -> [UInt8] {
        tlv(0x30, items.flatMap { $0 })
    }

    static func set(_ items: [[UInt8]]) -> [UInt8] {
        tlv(0x31, items.flatMap { $0 })
    }

    static func integer(_ bytes: [UInt8]) -> [UInt8] {
        var value = bytes
        while value.count > 1 && value[0] == 0 && value[1] < 0x80 { value.removeFirst() }
        if let first = value.first, first >= 0x80 { value.insert(0, at: 0) }
        return tlv(0x02, value)
    }

    static func octetString(_ bytes: [UInt8]) -> [UInt8] { tlv(0x04, bytes) }

    static func bitString(_ bytes: [UInt8]) -> [UInt8] { tlv(0x03, [0x00] + bytes) }

    static func boolean(_ value: Bool) -> [UInt8] { tlv(0x01, [value ? 0xFF : 0x00]) }

    static func utf8String(_ value: String) -> [UInt8] { tlv(0x0C, Array(value.utf8)) }

    static func null() -> [UInt8] { tlv(0x05, []) }

    static func oid(_ dotted: String) -> [UInt8] {
        let parts = dotted.split(separator: ".").compactMap { Int($0) }
        precondition(parts.count >= 2 && parts[0] < 3 && parts[1] < 40)
        var body: [UInt8] = [UInt8(parts[0] * 40 + parts[1])]
        for value in parts.dropFirst(2) {
            var stack: [UInt8] = [UInt8(value & 0x7F)]
            var remaining = value >> 7
            while remaining > 0 {
                stack.insert(UInt8((remaining & 0x7F) | 0x80), at: 0)
                remaining >>= 7
            }
            body.append(contentsOf: stack)
        }
        return tlv(0x06, body)
    }

    /// UTCTime is valid for years 1950...2049; CursorLoom certificates are short-lived.
    static func utcTime(_ date: Date) -> [UInt8] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Array(formatter.string(from: date).utf8))
    }

    static func explicit(_ tag: UInt8, _ inner: [UInt8]) -> [UInt8] { tlv(tag, inner) }
}

enum OID {
    static let ecdsaWithSHA256 = "1.2.840.10045.4.3.2"
    static let ecPublicKey = "1.2.840.10045.2.1"
    static let prime256v1 = "1.2.840.10045.3.1.7"
    static let commonName = "2.5.4.3"
    static let basicConstraints = "2.5.29.19"
    static let keyUsage = "2.5.29.15"
    static let extendedKeyUsage = "2.5.29.37"
    static let serverAuth = "1.3.6.1.5.5.7.3.1"
    static let clientAuth = "1.3.6.1.5.5.7.3.2"
}

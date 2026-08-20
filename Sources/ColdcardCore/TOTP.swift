import Foundation

/// RFC-6238 TOTP (HMAC-SHA1) used as the simulator stand-in for firmware `web2fa`.
public enum TOTP {
    public static func code(secret: Data, unixTime: TimeInterval, digits: Int = 6, period: TimeInterval = 30) -> String {
        let counter = UInt64(floor(unixTime / period))
        return hotp(secret: secret, counter: counter, digits: digits)
    }

    public static func verify(_ entered: String, secret: Data, unixTime: TimeInterval = Date().timeIntervalSince1970,
                              digits: Int = 6, window: Int = 1) -> Bool {
        let trimmed = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for offset in -window...window {
            let time = unixTime + TimeInterval(offset) * 30
            if Self.code(secret: secret, unixTime: time, digits: digits) == trimmed { return true }
        }
        return false
    }

    public static func secretFromBase32(_ text: String) throws -> Data {
        try Base32.decode(text)
    }

    public static func otpauthURL(secretBase32: String, label: String = "COLDCARD") -> String {
        "otpauth://totp/\(label)?secret=\(secretBase32)"
    }

    private static func hotp(secret: Data, counter: UInt64, digits: Int) -> String {
        var message = Data()
        message.appendUInt64BE(counter)
        let digest = HMAC.sha1(key: secret, message: message)
        let offset = Int(digest[digest.count - 1] & 0x0f)
        let binary = (UInt32(digest[offset] & 0x7f) << 24)
            | (UInt32(digest[offset + 1]) << 16)
            | (UInt32(digest[offset + 2]) << 8)
            | UInt32(digest[offset + 3])
        let modulus = UInt32(pow(10, Double(digits)))
        return String(format: "%0\(digits)u", binary % modulus)
    }
}

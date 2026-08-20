import Foundation

/// Firmware anti-phishing prefix words (`pincodes.prefix_words` / bootrom `pin_hash`).
///
/// Software stand-in for the SE pairing secret: `SHA256(SHA256(pairing_secret + PURPOSE_WORDS + pin_prefix))`,
/// then the 22-bit BIP-39 unpack. Does not emulate ATECC HMAC stretching (`pin_stretch`).
public enum PinPrefixWords {
    /// Firmware `rom_secrets->pairing_secret` length.
    public static let pairingSecretLength = 32

    /// `PIN_PURPOSE_WORDS` 0x2e6d6773 as little-endian bytes (`docs/pin-entry.md` PURPOSE_WORDS `73676d2e`).
    public static let purposeWords = Data([0x73, 0x67, 0x6d, 0x2e])

    /// Bootrom `pin_hash(..., PIN_PURPOSE_WORDS)` as documented in `docs/pin-entry.md` / `mathcheck.py`.
    public static func pinHash(pairingSecret: Data, pinPrefix: Data) -> Data {
        SHA2.doubleSHA256(pairingSecret + purposeWords + pinPrefix)
    }

    /// `pincodes.prefix_words`: little-endian uint32 of the first four digest bytes, then 22 bits.
    public static func wordIndices(digest: Data) -> (Int, Int)? {
        guard digest.count >= 4 else { return nil }
        let bits = UInt32(digest[0]) | UInt32(digest[1]) << 8 | UInt32(digest[2]) << 16 | UInt32(digest[3]) << 24
        let w1 = Int((bits >> 11) & 0x7ff)
        let w2 = Int(bits & 0x7ff)
        return (w1, w2)
    }

    public static func words(pairingSecret: Data, pinPrefix: String) -> (String, String)? {
        guard !pinPrefix.isEmpty else { return nil }
        let digest = pinHash(pairingSecret: pairingSecret, pinPrefix: Data(pinPrefix.utf8))
        guard let (w1, w2) = wordIndices(digest: digest) else { return nil }
        let list = BIP39EnglishWords.all
        guard list.indices.contains(w1), list.indices.contains(w2) else { return nil }
        return (list[w1], list[w2])
    }

    public static func displayString(pairingSecret: Data, pinPrefix: String) -> String {
        guard let pair = words(pairingSecret: pairingSecret, pinPrefix: pinPrefix) else { return "" }
        return "\(pair.0)  \(pair.1)"
    }
}

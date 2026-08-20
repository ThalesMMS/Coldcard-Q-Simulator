import Foundation

/// Firmware `decoders.decode_qr_result` type tags used by `ux_q1.scan_anything`.
public enum ScanAnythingKind: String, Equatable, Sendable {
    case psbt
    case addr
    case vmsg
    case text
    case xpub
    case teleport
    case xprv
    case words
    case wif
    case txn
    case multi
    case smsg
    case json
}

/// Firmware `QRScannerInteraction.scan_anything` (`shared/ux_q1.py`).
public enum ScanAnything {
    /// `ux_show_story(..., title='Sorry')`.
    public static let hobbledBlockedTitle = "Sorry"
    /// Exact firmware body when `what not in whitelist`.
    public static let hobbledBlockedBody = "Blocked when Spending Policy is in force."

    /// Always allowed while `pa.hobbled_mode`.
    public static let hobbledWhitelist: Set<ScanAnythingKind> = [
        .psbt, .addr, .vmsg, .text, .xpub, .teleport
    ]

    /// Firmware `decode_qr_result` else-branch: `Sorry, %s not useful.`
    public static func bbqrNotUsefulMessage(fileType: Character) -> String {
        let label = BBQrFileType(rawValue: fileType)?.label ?? "Unknown FileType"
        return "Sorry, \(label) not useful."
    }

    /// Firmware `decode_qr_result(expect_text=True)`: `Expected text, got ` + TYPE_LABELS.
    public static func bbqrExpectedTextMessage(fileType: Character) -> String {
        let label = BBQrFileType(rawValue: fileType)?.label ?? String(fileType)
        return "Expected text, got \(label)"
    }

    /// Added when `sssp_spending_policy('okeys')` (Related Keys).
    public static let relatedKeysKinds: Set<ScanAnythingKind> = [.xprv, .words]

    public static func allowsHobbled(_ kind: ScanAnythingKind, relatedKeys: Bool) -> Bool {
        if hobbledWhitelist.contains(kind) { return true }
        return relatedKeys && relatedKeysKinds.contains(kind)
    }

    /// BBQr file types from `decode_qr_result`. `U` re-enters text classification.
    public static func classifyBBQr(fileType: Character, utf8Body: String = "") -> ScanAnythingKind? {
        switch fileType {
        case "P": return .psbt
        case "T": return .txn
        case "R", "S", "E": return .teleport
        case "J":
            return BitcoinMessageSigner.isQRSignMessagePayload(utf8Body) ? .smsg : .json
        case "U":
            return classifyText(utf8Body)
        default:
            return nil
        }
    }

    public static func classifyText(_ raw: String) -> ScanAnythingKind {
        if let secret = classifySecret(raw) { return secret }
        if BitcoinMessageSigner.isQRSignMessagePayload(raw) { return .smsg }
        return classifyShortText(raw)
    }

    /// Firmware `decode_secret`.
    private static func classifySecret(_ raw: String) -> ScanAnythingKind? {
        guard raw.count <= 300 else { return nil }
        var got = raw
        if let colon = got.firstIndex(of: ":") {
            got = String(got[got.index(after: colon)...])
        }
        if got.count >= 4, got.dropFirst().prefix(3) == "prv" {
            return (try? HDKey.parseExtendedKey(got)) != nil ? .xprv : nil
        }
        if got.count == 51 || got.count == 52, (try? WIF.decode(got)) != nil {
            return .wif
        }
        let taste = got.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !taste.isEmpty, taste.allSatisfy(\.isNumber) {
            return (try? BIP39Mnemonic.fromSeedQR(taste)) != nil ? .words : nil
        }
        let tokens = taste.split(whereSeparator: \.isWhitespace).map(String.init)
        if [12, 18, 24].contains(tokens.count), tokens.allSatisfy(isFirmwareBIP39Token) {
            return .words
        }
        if [15, 21].contains(tokens.count), (try? BIP39Mnemonic(words: tokens)) != nil {
            return .words
        }
        return nil
    }

    /// Firmware `bip39.get_word_index`: full word or first four letters.
    private static func isFirmwareBIP39Token(_ token: String) -> Bool {
        guard (3...8).contains(token.count) else { return false }
        return BIP39EnglishWords.all.contains { word in
            token == word || token == String(word.prefix(4))
        }
    }

    /// Firmware `decode_short_text`.
    private static func classifyShortText(_ got: String) -> ScanAnythingKind {
        if got.count > 100 {
            if got.drop(while: { $0.isWhitespace }).hasPrefix("-----BEGIN BITCOIN SIGNED MESSAGE-----") {
                return .vmsg
            }
            if (try? PSBT.decodeText(got)) != nil { return .psbt }
            if looksLikeTransaction(got) { return .txn }
        }
        if got.contains("multi(") { return .multi }
        if got.contains("\n"), got.contains("pub"), legacyMultisigMatches(got) > 1 {
            return .multi
        }
        if got.count > 4096 || got.contains("\n") { return .text }
        if let bip21 = classifyBIP21(got) { return bip21 }
        return .text
    }

    private static func looksLikeTransaction(_ txt: String) -> Bool {
        if txt.hasPrefix("01000000") || txt.hasPrefix("02000000") {
            guard let data = try? Data(hex: txt) else { return false }
            return (try? BitcoinTransaction(data: data)) != nil
        }
        if txt.hasPrefix("AQAA") || txt.hasPrefix("AgAA") {
            guard let data = Data(base64Encoded: txt, options: [.ignoreUnknownCharacters]) else { return false }
            return (try? BitcoinTransaction(data: data)) != nil
        }
        return false
    }

    private static func legacyMultisigMatches(_ got: String) -> Int {
        got.split(separator: "\n", omittingEmptySubsequences: false).reduce(into: 0) { count, line in
            let text = String(line)
            guard text.count <= 150 else { return }
            if text.contains(/[0-9a-fA-F]+\s*:\s*[xtyYzZuUvV]pub[1-9A-HJ-NP-Za-km-z]+/) {
                count += 1
            }
        }
    }

    /// Firmware `utils.decode_bip21_text`.
    private static func classifyBIP21(_ raw: String) -> ScanAnythingKind? {
        var got = raw
        if let query = got.firstIndex(of: "?") {
            got = String(got[..<query])
        }
        if let colon = got.firstIndex(of: ":") {
            guard got[..<colon].lowercased() == "bitcoin" else { return nil }
            got = String(got[got.index(after: colon)...])
        }
        let addr = got
        if addr.count >= 4 {
            let mid = addr.dropFirst().prefix(3)
            if mid == "pub" {
                return (try? Base58.checkDecode(addr)) != nil ? .xpub : nil
            }
            if mid == "prv" {
                return (try? Base58.checkDecode(addr)) != nil ? .xprv : nil
            }
        }
        if (try? Base58.checkDecode(addr)) != nil { return .addr }
        if (try? Bech32.decodeSegwit(addr)) != nil { return .addr }
        return nil
    }
}

import Foundation

/// Firmware `nfc.share_file` / `nfc.import_ephemeral_seed_words_nfc` (not tag emulation).
public enum NFCShareKind: Equatable, Sendable {
    case psbt
    case txn
    case text
    case json
}

public enum NFCShare {
    /// Firmware `nfc.MAX_NFC_SIZE`.
    public static let maxSize = 8000
    /// Firmware `nfc.share_file` `file_picker(min_size=10)`.
    public static let minSize = 10
    /// Firmware `stash.SEED_LEN_OPTS`.
    public static let ephemeralWordCounts: Set<Int> = [12, 18, 24]

    /// Firmware `nfc.share_file` taster: `.psbt` / `.txn` / `.txt` / `.json` / `.sig`.
    public static func isSuitableFilename(_ name: String) -> Bool {
        kind(forFilename: name) != nil
    }

    public static func kind(forFilename name: String) -> NFCShareKind? {
        let ext = name.split(separator: ".").last.map { String($0).lowercased() } ?? ""
        switch ext {
        case "psbt": return .psbt
        case "txn": return .txn
        case "txt", "sig": return .text
        case "json": return .json
        default: return nil
        }
    }

    /// Firmware `nfc.import_ephemeral_seed_words_nfc` record filter: `strip().split(" ")`.
    public static func seedWordList(from text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard ephemeralWordCounts.contains(tokens.count) else { return nil }
        return tokens
    }

    public static func seedWordList(fromUTF8 data: Data) -> [String]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return seedWordList(from: text)
    }

    /// Firmware `NFC.start_msg_sign` NDEF filter: `split("\n")` length 1...3.
    public static func nfcSignMessagePayload(from text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard (1...3).contains(lines.count) else { return nil }
        return text
    }

    /// Expand 4-letter (or longer unique) prefixes the way firmware `bip39.a2b_words` accepts.
    public static func expandBIP39Words(_ tokens: [String]) throws -> [String] {
        try tokens.map { token in
            let needle = token.lowercased()
            if BIP39EnglishWords.all.contains(needle) { return needle }
            let prediction = BIP39Mnemonic.predict(prefix: needle)
            if let word = prediction.completedWord, prediction.nextCharacters.isEmpty {
                return word
            }
            throw BIP39Error.unknownWord(token)
        }
    }
}

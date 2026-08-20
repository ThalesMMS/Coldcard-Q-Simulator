import Foundation

/// Firmware `shared/backups.py` text archive, password UX copy, and restore/verify stories.
public enum BackupFile {
    public static let header = "# Coldcard backup file! DO NOT CHANGE."
    public static let eofMarker = "# EOF"
    public static let encryptedFilename = "backup.7z"
    public static let cleartextFilename = "backup.txt"
    public static let maxFileSize = 128 * 1024
    public static let passwordWordCount = 12
    public static let maxCopies = 25
    public static let hardwareLabel = "q1"
    public static let unixSerial = "F1F1F1F1F1F1"
    public static let fwDate = "2026-07-31"
    public static let fwTimestamp = "260731000000"

    public static let skippedSettingKeys: Set<String> = [
        "xpub", "xfp", "bkpw", "sd2fa", "words", "ccc", "ktrx", "lfr"
    ]

    public static let moneyForFree = "money for free"
    public static let notesAndPasswords = "notes & passwords"
    public static let customPasswordTitle = "Custom PWD?"
    public static let backupPasswordPrompt = "Your Backup Password"
    public static let recordPasswordPrompt = "Record this (12 word) backup file password:"
    public static let cleartextKeyHint = "Press (6) for cleartext backup. "
    public static let unableToOpen = "Unable to open backup file."
    public static let unableToReadHeaders = "Unable to read backup file headers. Might be truncated."
    public static let unableToVerifyContents = "Unable to verify backup file contents."
    public static let invalidBackupFile = "Invalid backup file."
    public static let crcOKStory = """
    Backup file CRC checks out okay.

    Please note this is only a check against accidental truncation and similar. Targeted modifications can still pass this test. You may further verify this backup file by starting the normal restore process (Restore Backup) and aborting it once decryption has been achieved.
    """

    public static let customPasswordStory =
        "Press (1) if your password is custom string, press ENTER for 12 word password."

    public static let reusePasswordLeadIn = "Use same backup file password as last time?\n\n"

    /// Setting keys firmware never writes (`backups.py` `render_backup_contents`).
    public static func shouldSkipSettingKey(_ key: String) -> Bool {
        if key.hasPrefix("_") { return true }
        return skippedSettingKeys.contains(key)
    }

    public static func jsonDump(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        guard let text = String(data: data, encoding: .utf8) else {
            throw BackupFileError.jsonEncoding
        }
        return text
    }

    public static func jsonLoad(_ text: String) throws -> Any {
        guard let data = text.data(using: .utf8) else { throw BackupFileError.jsonEncoding }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    public static func render(
        mnemonic: String? = nil,
        bip32MasterKeyHex: String? = nil,
        chain: String,
        chainName: String,
        xprv: String,
        xpub: String,
        rawSecretHex: String,
        fwDate: String = fwDate,
        fwVersion: String = WalletExporter.coldcardFirmwareVersion,
        fwTimestamp: String = fwTimestamp,
        serial: String = unixSerial,
        hardware: String = hardwareLabel,
        settings: [(key: String, value: Any)] = []
    ) throws -> String {
        var lines: [String] = [header, "", "# Private key details: \(chainName)"]
        if let mnemonic, !mnemonic.isEmpty {
            try lines.append(field("mnemonic", mnemonic))
        }
        if let bip32MasterKeyHex, !bip32MasterKeyHex.isEmpty {
            try lines.append(field("bip32_master_key", bip32MasterKeyHex))
        }
        try lines.append(field("chain", chain))
        try lines.append(field("xprv", xprv))
        try lines.append(field("xpub", xpub))
        try lines.append(field("raw_secret", strippedRawSecretHex(rawSecretHex)))
        lines.append("")
        lines.append("# Firmware version (informational)")
        try lines.append(field("fw_date", fwDate))
        try lines.append(field("fw_version", fwVersion))
        try lines.append(field("fw_timestamp", fwTimestamp))
        lines.append("# Coldcard Hardware")
        try lines.append(field("serial", serial))
        try lines.append(field("hardware", hardware))
        lines.append("")
        lines.append("# User preferences")
        for pair in settings {
            if shouldSkipSettingKey(pair.key) { continue }
            if pair.key == "seedvault", isJSONFalse(pair.value) { continue }
            if pair.key == "seeds", isJSONEmpty(pair.value) { continue }
            try lines.append(field("setting.\(pair.key)", pair.value))
        }
        lines.append("")
        lines.append(eofMarker)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Firmware `text_bk_parser`.
    public static func parse(_ text: String) -> [String: Any] {
        var values: [String: Any] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty { continue }
            if line.first == "#" { continue }
            guard let split = line.range(of: " = ") else { continue }
            let key = String(line[..<split.lowerBound])
            let raw = String(line[split.upperBound...])
            if let decoded = try? jsonLoad(raw) {
                values[key] = decoded
            }
        }
        return values
    }

    public static func looksLikeBackupText(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix(header) || trimmed.hasPrefix("# Coldcard backup file!")
    }

    public static func innerFilename(word: String, number: Int, ext: String = "txt") -> String {
        "\(word)\(number).\(ext)"
    }

    public static func isWordPassword(_ password: String) -> Bool {
        let words = password.split(whereSeparator: \.isWhitespace)
        return words.count == passwordWordCount
    }

    /// Firmware `bkpw_workflow` hint after the reuse question.
    public static func passwordReuseHint(_ password: String) -> String {
        let words = password.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count == passwordWordCount {
            return " 1: \(words[0])\n   ...\n\(words.count): \(words[words.count - 1])"
        }
        guard let first = password.first, let last = password.last else { return "" }
        return " \(first)...\(last)"
    }

    public static func reusePasswordStory(_ password: String) -> String {
        reusePasswordLeadIn + passwordReuseHint(password)
    }

    public static func cleartextConfirm(what: String) -> String {
        "The file will **NOT** be encrypted and anyone who finds the file will get all of your \(what)!"
    }

    public static func firstCopyWritten(_ filename: String) -> String {
        """
        Backup file written:

        \(filename)

        To view or restore the file, you must have the full password.

        Insert another SD card and press (2) to make another copy.
        """
    }

    public static func subsequentCopyWritten(copyNumber: Int, filename: String) -> String {
        """
        File (#\(copyNumber)) written:

        \(filename)

        Press ENTER for another copy, or press CANCEL to stop.
        """
    }

    public static func verifyFailure(problem: String, error: String) -> String {
        "\(problem)\n\nError: \(error)"
    }

    public static func decryptFailed(tried: String) -> String {
        "Unable to decrypt backup file. Incorrect password?\n\nTried:\n\n\(tried)"
    }

    public static func unableToOpenPath(_ path: String) -> String {
        "\(unableToOpen)\n\n\(path)"
    }

    public static func touchedFileError(_ detail: String) -> String {
        "Unable to read backup file. Has it been touched?\n\nError: \(detail)"
    }

    public static func invalidBackupFileDetail(_ detail: String) -> String {
        "Invalid backup file: \(detail)"
    }

    public static func decodeRawSecretFailed(_ detail: String) -> String {
        "Unable to decode raw_secret and restore the seed value!\n\n\n\(detail)"
    }

    public static func restoreTitle(xfp: String) -> String {
        "[\(xfp)]"
    }

    public static func isEncryptedBackupFilename(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".7z")
    }

    public static func isCleartextBackupFilename(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".txt")
    }

    public static func innerNameIsText(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".txt")
    }

    public static func innerNameIsJSON(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".json")
    }

    public static func isPlausibleInnerSize(_ size: Int) -> Bool {
        (400..<maxFileSize).contains(size)
    }

    /// Firmware `b2a_hex(sv.secret).rstrip(b'0')`.
    public static func strippedRawSecretHex(_ hex: String) -> String {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.last == "0" { text.removeLast() }
        return text
    }

    public static func deserializeSecret(_ hex: String) throws -> Data {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count % 2 == 1 { text.append("0") }
        var raw = try Data(hex: text)
        if raw.count < SecretStash.encodedLength {
            raw.append(Data(count: SecretStash.encodedLength - raw.count))
        }
        return raw
    }

    public static func network(fromChain ctype: String) -> BitcoinNetwork {
        switch ctype.uppercased() {
        case "BTC": return .mainnet
        case "XRT": return .regtest
        default: return .testnet
        }
    }

    public static func stringValue(_ values: [String: Any], _ key: String) -> String? {
        guard let value = values[key] else { return nil }
        if let text = value as? String { return text }
        return nil
    }

    public static func settingValues(_ values: [String: Any]) -> [String: Any] {
        var settings: [String: Any] = [:]
        for (key, value) in values where key.hasPrefix("setting.") {
            settings[String(key.dropFirst("setting.".count))] = value
        }
        return settings
    }

    public static func jsonBool(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        if let number = value as? Int { return number != 0 }
        if let text = value as? String {
            return text == "1" || text.lowercased() == "true"
        }
        return false
    }

    public static func jsonInt(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private static func field(_ key: String, _ value: Any) throws -> String {
        "\(key) = \(try jsonDump(value))"
    }

    private static func isJSONFalse(_ value: Any) -> Bool {
        !jsonBool(value)
    }

    private static func isJSONEmpty(_ value: Any) -> Bool {
        if let array = value as? [Any] { return array.isEmpty }
        if let text = value as? String { return text.isEmpty }
        return false
    }
}

public enum BackupFileError: Error, Equatable, Sendable {
    case jsonEncoding
    case missingRawSecret
    case malformed
}

extension BackupFileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .jsonEncoding: "Unable to encode backup field."
        case .missingRawSecret: BackupFile.decodeRawSecretFailed("missing raw_secret")
        case .malformed: BackupFile.invalidBackupFile
        }
    }
}

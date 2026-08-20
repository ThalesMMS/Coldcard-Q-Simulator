import Foundation

/// Title and field limits from firmware `shared/notes.py` (`ONE_LINE`, `quick_create`).
public enum SecureNotes {
    public static let oneLineLimit = 32
    public static let passwordLimit = 128
    /// Firmware `seed.MAX_PASS_LEN`.
    public static let maxPassphraseLength = 100
    public static let importMinSize = 8
    public static let importMaxSize = 100_000
    public static let customPasswordMinLength = 32
    public static let customPasswordMaxLength = 128

    /// Firmware `get_a_password` `fmsg` (F6 is handled but not shown).
    public static let passwordFunctionKeyLegend = "F1 12  F2 24 word  F3 F4 random  F5 B85"
    public static let qrExportWarning = "WARNING: QR exports are NOT encrypted!"
    public static let exportTitle = "Data Export"
    public static let importTitle = "Data Import"
    public static let importWhat = "secure notes and/or passwords"
    public static let customPWDTitle = "Custom PWD?"
    public static let sendPasswordUntypeable =
        "Sorry, your password contains a character that we cannot type at this time."
    public static let bbqrScanPrompt = "Scan BBQr from other COLDCARD."
    public static let bbqrExportTitle = "Notes & Passwords Export"
    public static let savedPause = "Saved."
    public static let customPWDBody =
        "Press (1) if your password is custom string, press ENTER for 12 word password."
    public static let decryptFailedPrefix =
        "Unable to decrypt backup file. Incorrect password?\n\nTried:\n\n"
    /// Firmware `import_from_json` `assert …, 'Incorrect format'`.
    public static let incorrectFormatMessage = "Incorrect format"
    public static let cleartextConfirm =
        "The file will **NOT** be encrypted and anyone who finds the file will get all of your notes & passwords!"

    public static func titleForScannedText(_ got: String) -> String {
        if got.hasPrefix("otpauth://totp/") {
            let rest = String(got.dropFirst("otpauth://totp/".count))
            let label = rest.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rest
            return label.removingPercentEncoding ?? label
        }
        if got.hasPrefix("otpauth-migration://offline") { return "Google Auth" }
        if got.prefix(20).contains("://") {
            let afterScheme = got.split(separator: "://", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            let host = afterScheme.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            if host.isEmpty { return "Scanned URL" }
            return String(host.prefix(oneLineLimit))
        }
        return "Scanned"
    }

    public static func exportItemLabel(count: Int, kind: String?) -> String {
        if count == 1 { return kind == "password" ? "password" : "note" }
        return "all notes & passwords"
    }

    public static func jsonFilename(all: Bool, isPassword: Bool) -> String {
        if all { return "cc-notes.json" }
        return isPassword ? "cc-password.json" : "cc-note.json"
    }

    public static func sevenZipFilename(jsonName: String) -> String {
        jsonName.replacingOccurrences(of: ".json", with: ".7z")
    }

    public static func exportPrompt(
        item: String,
        virtualDiskEnabled: Bool
    ) -> String {
        let prompt = ExportPromptBuilder.prompt(
            whatItIs: item,
            dualSDSlots: true,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: false,
            qrEnabled: true,
            qwerty: true,
            noNFC: true
        ) ?? "Press (1) to save \(item) to SD Card, QR to show QR code."
        return prompt + "\n\n" + qrExportWarning
    }

    public static func importPrompt(virtualDiskEnabled: Bool) -> String {
        FirmwareImportPrompt.qImportPrompt(
            title: importWhat,
            slotBOnly: false,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: false,
            includeQR: true
        )
    }

    public static func successStory(encrypted: Bool, filename: String, signatureFilename: String?) -> String {
        var msg = "\(encrypted ? "Encrypted e" : "E")xport file written:\n\n\(filename)"
        if let signatureFilename {
            msg += "\n\nSignature file written:\n\n\(signatureFilename)"
        }
        return msg
    }

    /// Firmware `_pick_dense`: `bip85_pwd(generate_seed() + generate_seed())` then `+/` remap.
    public static func densePassword(from secret64: Data) -> String {
        BIP85.password(from: secret64)
            .replacingOccurrences(of: "+", with: "P")
            .replacingOccurrences(of: "/", with: "s")
    }

    /// Firmware `_toggle_case`.
    public static func toggleCase(_ value: String) -> String {
        guard let first = value.first else { return "" }
        return first.isLowercase ? value.uppercased() : value.lowercased()
    }

    /// Firmware `utils.is_printable`.
    public static func isPrintable(_ string: String) -> Bool {
        string.unicodeScalars.allSatisfy { (32...126).contains($0.value) }
    }

    /// Firmware `NoteContentBase.is_b39pass_applicable` — untrimmed `data`.
    public static func isB39PassApplicable(
        _ data: String,
        readOnly: Bool,
        relatedKeys: Bool,
        wordBased: Bool
    ) -> Bool {
        if readOnly && !relatedKeys { return false }
        return data.count <= maxPassphraseLength && isPrintable(data) && wordBased
    }

    /// Firmware `apply_as_b39_pass` rstrip of trailing whitespace only.
    public static func rstripPassphrase(_ data: String) -> String {
        var end = data.endIndex
        while end > data.startIndex {
            let previous = data.index(before: end)
            if data[previous].isWhitespace { end = previous } else { break }
        }
        return String(data[..<end])
    }

    public static func compareTitles(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased() < rhs.lowercased()
    }

    public static func compareGroups(_ lhs: String, _ rhs: String) -> Bool {
        lhs < rhs
    }

    public static func sortedGroupNames<S: Sequence>(_ names: S) -> [String] where S.Element == String {
        Array(Set(names.filter { !$0.isEmpty })).sorted(by: <)
    }

    /// Firmware `file_picker(min_size=8, max_size=100000)`.
    public static func isImportSizeOK(_ count: Int) -> Bool {
        (importMinSize...importMaxSize).contains(count)
    }

    /// Firmware `file_picker` taster (`notes.import_from_other.suitable`).
    public static func isImportCandidate(filename: String, data: Data) -> Bool {
        let lower = filename.lowercased()
        if lower.hasSuffix(".7z") { return true }
        guard lower.hasSuffix(".json") else { return false }
        return containsColdcardNotes(data)
    }

    public static func containsColdcardNotes(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["coldcard_notes"] != nil
    }

    public static func decodeNotesJSON(_ data: Data) throws -> [[String: String]] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["coldcard_notes"] as? [[String: Any]] else {
            throw SecureNotesImportError.incorrectFormat
        }
        return rows.map { row in
            var mapped: [String: String] = [:]
            for (key, value) in row {
                mapped[key] = value as? String ?? ""
            }
            return mapped
        }
    }

    public static func encodeNotesJSON(_ records: [[String: String]]) throws -> Data {
        let envelope: [String: Any] = ["coldcard_notes": records]
        guard JSONSerialization.isValidJSONObject(envelope) else {
            throw SecureNotesImportError.incorrectFormat
        }
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    public static func decryptFailureMessage(password: String) -> String {
        decryptFailedPrefix + password
    }
}

public enum SecureNotesImportError: Error, Equatable, Sendable {
    case incorrectFormat
}

/// Firmware `NotesAndPasswordsMenu.construct_note_items` (`notes.py`).
public enum NoteMenuCopy {
    /// `'%d: %s' % (note.idx+1, note.title)` — unpadded, unlike Seed Vault `%2d`.
    public static func parentRowLabel(index: Int, title: String) -> String {
        "\(index + 1): \(title)"
    }
}

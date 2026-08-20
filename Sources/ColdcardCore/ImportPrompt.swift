import Foundation

/// Firmware `ux._import_prompt_builder` for Coldcard Q (qwerty, dual MicroSD).
///
/// Hardware renders `KEY_NFC` / `KEY_QR` as icons; the simulator uses the labels `NFC` and `QR`.
public enum FirmwareImportPrompt {
    public static let nfcKeyLabel = "NFC"
    public static let qrKeyLabel = "QR"
    /// Firmware `actions.import_xprv` → `import_extended_key_as_secret(..., origin='Imported XPRV')`.
    public static let importedXPRVOrigin = "Imported XPRV"
    /// Firmware `import_xprv` `label` interpolated as `"%s file" % "extended private key"`.
    public static let extendedPrivateKeyFileTitle = "extended private key file"
    /// Firmware `nfc.read_extended_private_key` miss story.
    public static let xprvNFCMissing = "Unable to find extended private key."
    /// Firmware `file_picker` `none_msg` for Import XPRV.
    public static let xprvFileNoneMsg = "Must contain extended private key."
    /// Firmware `QRScannerInteraction.scan('Scan XPRV from a QR code')`.
    public static let scanXPRVPrompt = "Scan XPRV from a QR code"

    /// Firmware `utils.parse_extended_key` private regex `.prv[A-Za-z0-9]+`.
    public static func parseExtendedPrivateKeyToken(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: ".prv[A-Za-z0-9]+") else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let token = Range(match.range, in: text) else { return nil }
        return String(text[token])
    }

    /// Firmware `import_xprv` file read: first line containing `prv`.
    public static func firstPrivateKeyLine(in text: String) -> String? {
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.contains("prv") { return String(line) }
        }
        return nil
    }

    /// Firmware `NFC.read_extended_private_key`: NDEF payload contains `prv`, then `decode().strip()`.
    public static func extendedPrivateKey(fromNFCPayloads payloads: [Data]) -> String? {
        let marker = Data("prv".utf8)
        for payload in payloads {
            guard payload.range(of: marker) != nil else { continue }
            guard let text = String(data: payload, encoding: .utf8) else { continue }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Ready To Sign empty import uses `slot_b_only=True` (`actions.ready2sign`).
    /// Q always has two SD slots, so the (B) line is present even when NFC and Virtual Disk are off.
    public static func qImportPrompt(
        title: String,
        slotBOnly: Bool,
        virtualDiskEnabled: Bool,
        nfcEnabled: Bool,
        includeQR: Bool = true
    ) -> String {
        var prompt: String
        if slotBOnly {
            prompt = "Press (B) to import \(title) from lower slot SD Card"
        } else {
            prompt = "Press (1) to import \(title) from SD Card, (B) for lower slot"
        }
        if virtualDiskEnabled {
            prompt += ", press (2) to import from Virtual Disk"
        }
        if nfcEnabled {
            prompt += ", press \(nfcKeyLabel) to import via NFC"
        }
        if includeQR {
            prompt += ", \(qrKeyLabel) to scan QR code"
        }
        prompt += "."
        return prompt
    }
}

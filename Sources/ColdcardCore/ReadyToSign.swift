import Foundation

/// Firmware `actions.ready2sign` / `nfc_sign_psbt` / `NFC.start_psbt_rx`.
public enum ReadyToSign {
    /// Firmware `file_picker(..., allow_batch=("[Sign All]", batch_sign))`.
    public static let signAllLabel = "[Sign All]"
    /// Firmware `NFC.ux_animation` default prompt (`nfc.py`).
    public static let nfcReceivePrompt = "Tap phone to screen, or CANCEL."
    /// Firmware `NFC.start_psbt_rx`: `len(msg) > 100` before `psbt_encoding_taster`.
    public static let nfcMinRecordSize = 101
    public static let nfcMissingPSBT = "Could not find PSBT in what was written."
    public static let nfcNoTagData = "No tag data was written?"
    public static let nfcSorryTitle = "Sorry!"
    public static let nfcFailedTitle = "ERROR"
    /// Firmware `ready2sign` intro (`actions.py`).
    public static let emptyIntro = """
    Coldcard is ready to sign spending transactions!

    Put the proposed transaction onto MicroSD card in PSBT format (Partially Signed Bitcoin Transaction) or upload a transaction to be signed from your desktop wallet software or command line tools.
    """
    /// Firmware `ready2sign` footnotes passed to `import_export_prompt`.
    public static let emptyFootnotes = "You will always be prompted to confirm the details before any signature is performed."

    /// Firmware `ready2sign`: `title = '[%s]' % xfp` when a temporary seed is active, else `None`.
    public static func emptyTitle(temporarySeed: Bool, xfp: String?) -> String {
        if temporarySeed, let xfp, !xfp.isEmpty { return "[\(xfp)]" }
        return ""
    }

    /// Firmware `import_export_prompt` body: intro, Q import prompt, footnotes (`ux.py:518`).
    public static func emptyStory(virtualDiskEnabled: Bool, nfcEnabled: Bool) -> String {
        """
        \(emptyIntro)

        \(FirmwareImportPrompt.qImportPrompt(title: "PSBT", slotBOnly: true, virtualDiskEnabled: virtualDiskEnabled, nfcEnabled: nfcEnabled))

        \(emptyFootnotes)
        """
    }

    public enum SilentOutcome: Equatable, Sendable {
        case empty
        case autoOpen
        case picker
    }

    /// Firmware `ready2sign` after silent `file_picker(suffix='.psbt', ux=False)`.
    public static func silentOutcome(fileCount: Int) -> SilentOutcome {
        switch fileCount {
        case 0: return .empty
        case 1: return .autoOpen
        default: return .picker
        }
    }

    /// Firmware `file_picker` menu: `[Sign All]` inserted at index 0, then sorted file labels.
    public static func pickerTitles(filenames: [String]) -> [String] {
        [signAllLabel] + filenames.sorted()
    }

    /// Firmware `nfc_sign_psbt` exception story.
    public static func nfcSignFailedBody(_ detail: String) -> String {
        "Failed to sign PSBT.\n\n\(detail)"
    }

    /// Firmware `psbt_encoding_taster` on the first 10 bytes (`auth.py`).
    public static func encodingTaste(_ data: Data) -> Bool {
        PSBT.isPSBTTaste(filename: "payload.psbt", data: data)
    }

    /// Firmware `NFC.start_psbt_rx` NDEF scan: last large record that tastes as a PSBT.
    public static func psbtPayload(fromNDEF payloads: [Data]) -> Data? {
        var found: Data?
        for payload in payloads where payload.count >= nfcMinRecordSize {
            if encodingTaste(payload) {
                found = payload
            }
        }
        return found
    }
}

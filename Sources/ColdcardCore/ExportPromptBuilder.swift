import Foundation

/// Firmware `ux.export_prompt_builder` (Q: qwerty, dual SD slots).
/// Hardware renders `KEY_NFC` / `KEY_QR` as icons; the simulator uses `NFC` / `QR`.
public enum ExportPromptBuilder {
    public static let nfcKeyLabel = "NFC"
    public static let qrKeyLabel = "QR"

    public static func prompt(
        whatItIs: String,
        dualSDSlots: Bool = true,
        virtualDiskEnabled: Bool,
        nfcEnabled: Bool,
        qrEnabled: Bool = true,
        qwerty: Bool = true,
        key0: String? = nil,
        key6: String? = nil,
        offerKT: String? = nil,
        forcePrompt: Bool = false,
        noNFC: Bool = false
    ) -> String? {
        let showNFC = nfcEnabled && !noNFC
        guard virtualDiskEnabled || dualSDSlots || key0 != nil || forcePrompt
                || offerKT != nil || key6 != nil || qrEnabled else {
            return nil
        }

        var prompt = "Press (1) to save \(whatItIs) to SD Card"
        if dualSDSlots {
            prompt += ", (B) for lower slot"
        }
        if virtualDiskEnabled {
            prompt += ", press (2) to save to Virtual Disk"
        }
        if showNFC {
            if qwerty {
                prompt += ", press \(nfcKeyLabel) to share via NFC"
            } else {
                prompt += ", press (3) to share via NFC"
            }
        }
        if qrEnabled {
            if qwerty {
                prompt += ", \(qrKeyLabel) to show QR code"
            } else {
                prompt += ", (4) to show QR code"
            }
        }
        if let offerKT {
            prompt += ", (T) to " + offerKT
        }
        if let key0 {
            prompt += ", (0) " + key0
        }
        if let key6 {
            prompt += ", (6) " + key6
        }
        prompt += "."
        return prompt
    }
}

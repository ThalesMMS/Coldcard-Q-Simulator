import Foundation

/// Firmware `auth.done_signing` / `_save_to_disk` / `TXExplorer` / `_batch_sign`.
public enum DoneSigning {
    public static let signedTitle = "PSBT Signed"
    public static let pushedTitle = "TX Pushed"
    public static let sentByTeleportTitle = "Sent by Teleport"
    public static let failedToTeleportTitle = "Failed to Teleport"
    public static let needCard = "Need a card!\n\n"
    public static let noPSBTsFound = "No PSBTs found. Need to have '.psbt' suffix."
    public static let fallbackBaseName = "recent-txn"
    public static let offerKT = "use Key Teleport to send PSBT to other co-signers"
    public static let txidQRHint = "for QR Code of TXID"
    public static let plainQRByteLimit = 920
    public static let inputQRLabels = ["TXID", "UTXO ADDR"]
    public static let wifStoreNote = "(WIF Store)"

    public static func noun(isComplete: Bool, isBIP322: Bool) -> String {
        if isBIP322 { return "Signed BIP-322 PSBT" }
        return isComplete ? "Finalized TX ready for broadcast" : "Partly Signed PSBT"
    }

    /// Firmware `basename.rsplit('.', 1)[0]`; missing file → `recent-txn`.
    public static func baseName(from filename: String?) -> String {
        guard let filename, !filename.isEmpty else { return fallbackBaseName }
        let basename = filename.split(separator: "/").last.map(String.init) ?? filename
        guard let dot = basename.lastIndex(of: ".") else { return basename }
        let stem = String(basename[..<dot])
        return stem.isEmpty ? fallbackBaseName : stem
    }

    public static func psbtFilename(base: String, isComplete: Bool) -> String {
        if isComplete { return base + "-signed.psbt" }
        return base.replacingOccurrences(of: "-part", with: "") + "-part.psbt"
    }

    public static func txnFilename(base: String, txid: String?, deleteAfter: Bool) -> String {
        if deleteAfter { return (txid ?? base) + ".txn" }
        return base + "-final.txn"
    }

    public static func saveStory(psbtFilename: String?, txnFilename: String?) -> String {
        var msg = ""
        if let psbtFilename {
            msg = "Updated PSBT is:\n\n\(psbtFilename)"
            if txnFilename != nil { msg += "\n\n" }
        }
        if let txnFilename {
            msg += "Finalized transaction (ready for broadcast):\n\n\(txnFilename)"
        }
        return msg
    }

    public static func txidIntro(_ txid: String) -> String { "TXID:\n\(txid)" }

    public static func composeIntro(prior: String?, txid: String?) -> String {
        var parts: [String] = []
        if let prior, !prior.isEmpty { parts.append(prior) }
        if let txid { parts.append(txidIntro(txid)) }
        return parts.joined(separator: "\n\n")
    }

    public static func qrCaption(txid: String?, noun: String) -> String { txid ?? noun }

    public static func usesPlainHexQR(byteCount: Int) -> Bool { byteCount <= plainQRByteLimit }

    public static func remainingSignaturesNeeded(_ count: Int) -> String {
        let s = count == 1 ? "" : "s"
        let aux = count == 1 ? "is" : "are"
        return "\(count) more signature\(s) \(aux) still required."
    }

    /// Firmware `kt_send_psbt`: `M - (N - len(need))`.
    public static func signaturesStillNeeded(required: Int, total: Int, stillNeededAmongWallet: Int) -> Int {
        required - (total - stillNeededAmongWallet)
    }

    public static func failedToWrite(_ detail: String) -> String {
        "Failed to write!\n\n\(detail)\n\n"
    }

    public static func inputFullySigned(partialSignatureCount: Int, requiredM: Int?, subpathCount: Int) -> Bool {
        if let requiredM { return partialSignatureCount >= requiredM }
        return partialSignatureCount > 0 && partialSignatureCount >= subpathCount
    }

    public static func ourKeyLabel(xfp: String, path: DerivationPath) -> String {
        let rest = path.components.map { component in
            let hardened = component & DerivationPath.hardened != 0
            return "\(component & ~DerivationPath.hardened)\(hardened ? "h" : "")"
        }.joined(separator: "/")
        if rest.isEmpty { return xfp }
        return "\(xfp)/\(rest)"
    }

    public static func sighashNote(_ flag: UInt32) -> String? {
        if flag == 1 { return nil }
        let name: String
        switch flag {
        case 1: name = "ALL"
        case 2: name = "NONE"
        case 3: name = "SINGLE"
        case 1 | 0x80: name = "ALL|ANYONECANPAY"
        case 2 | 0x80: name = "NONE|ANYONECANPAY"
        case 3 | 0x80: name = "SINGLE|ANYONECANPAY"
        default: name = String(format: "0x%02x (non-standard)", flag)
        }
        return "sighash: \(name)"
    }

    public static func outputTitle(offset: Int, endExclusive: Int) -> String {
        "\(offset)-\(max(offset, endExclusive - 1))"
    }

    public static func startIdxPrompt(maxIndex: Int) -> String {
        "Start Idx (0-\(maxIndex)):"
    }

    public static func qExplorerHints(hasNext: Bool, hasPrev: Bool, canGoto: Bool) -> String {
        var hints: [String] = []
        if hasNext { hints.append("RIGHT to see next group") }
        if hasPrev { hints.append("LEFT to go back") }
        if canGoto { hints.append("(2) to go to index") }
        if hints.isEmpty { return "Press CANCEL to quit." }
        return "Press " + hints.joined(separator: ", ") + ". CANCEL to quit."
    }

    /// Firmware `CardSlot.pick_filename`.
    public static func pickFilename(_ pattern: String, existing: Set<String>, overwrite: Bool = false) -> String {
        if overwrite || !existing.contains(pattern) { return pattern }
        guard let dot = pattern.lastIndex(of: ".") else { return pattern }
        let basename = String(pattern[..<dot])
        let ext = String(pattern[dot...])
        var highest = 1
        let prefix = basename + "-"
        for name in existing {
            guard name.hasPrefix(prefix), name.hasSuffix(ext) else { continue }
            let middle = name.dropFirst(prefix.count).dropLast(ext.count)
            if let value = Int(middle) { highest = max(highest, value) }
        }
        return "\(basename)-\(highest + 1)\(ext)"
    }

    public static func addressFormatName(scriptPubKey: Data, redeem: Data?, witness: Data?) -> String? {
        if let redeem {
            if redeem.count == 22, redeem.starts(with: [0x00, 0x14]) { return "p2sh-p2wpkh" }
            if redeem.count == 34, redeem.starts(with: [0x00, 0x20]) { return "p2sh-p2wsh" }
        }
        if witness != nil, BitcoinScript.classify(scriptPubKey) == .unknown {
            return "p2wsh"
        }
        return BIP322.addressFormatName(scriptPubKey)
    }

    public static func sharedVia(_ noun: String, channel: String) -> String {
        "\(noun) shared via \(channel)."
    }
}

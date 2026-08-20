import Foundation

/// Firmware `psbt.py` BIP-322 / Proof of Reserves helpers.
public enum BIP322 {
    /// Single SHA256 of `BIP0322-signed-message` (`psbt.BIP322_TAG_HASH`).
    public static let tagHash = SHA2.sha256(Data("BIP0322-signed-message".utf8))

    /// `ngu.hash.sha256t(tag_hash, msg, True)` = SHA256(tag || tag || msg).
    public static func messageHash(_ message: String) -> Data {
        SHA2.sha256(tagHash + tagHash + Data(message.utf8))
    }

    /// Firmware `build_bip322_to_spend`.
    public static func toSpend(messageHash: Data, challenge: Data) -> BitcoinTransaction {
        var scriptSig = Data([0x00, 0x20])
        scriptSig.append(messageHash)
        let input = TransactionInput(previousTxID: Data(repeating: 0, count: 32),
                                     previousOutputIndex: 0xffff_ffff,
                                     scriptSig: scriptSig,
                                     sequence: 0xffff_ffff)
        let output = TransactionOutput(value: 0, scriptPubKey: challenge)
        return BitcoinTransaction(version: 0, inputs: [input], outputs: [output], lockTime: 0)
    }

    public static func relativeTimelock(sequence: UInt32) -> (isTimeBased: Bool, value: UInt32)? {
        let disable: UInt32 = 1 << 31
        let typeFlag: UInt32 = 1 << 22
        let mask: UInt32 = 0x0000_ffff
        if sequence & disable != 0 { return nil }
        if sequence & typeFlag != 0 {
            let seconds = (sequence & mask) << 9
            return seconds == 0 ? nil : (true, seconds)
        }
        let blocks = sequence & mask
        return blocks == 0 ? nil : (false, blocks)
    }

    public static func humanSeconds(_ seconds: UInt32) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let secs = seconds % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if secs > 0 || parts.isEmpty { parts.append("\(secs)s") }
        return parts.joined(separator: " ")
    }

    public static func addressFormatName(_ script: Data) -> String? {
        switch BitcoinScript.classify(script) {
        case .p2pkh: "p2pkh"
        case .p2sh: "p2sh"
        case .p2wpkh: "p2wpkh"
        case .p2wsh: "p2wsh"
        case .p2tr: "p2tr"
        default: nil
        }
    }
}

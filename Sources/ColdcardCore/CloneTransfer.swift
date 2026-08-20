import Foundation

public enum CloneTransferError: Error, Equatable, Sendable {
    case invalidStartFile
    case invalidCloneFilename
    case invalidPublicKey
}

/// Clone/Migrate MicroSD handshake from firmware `backups.clone_start` / `clone_write_data`.
/// Simulator clone archives use the CryptoKit AES-GCM envelope around firmware backup
/// text; filenames keep `{compressed-pubkey-hex}-ccbk.7z` and still accept a `.json` stand-in.
public enum CloneTransfer {
    public static let startFilename = "ccbk-start.json"
    public static let cloneSuffixJSON = "-ccbk.json"
    public static let cloneSuffix7z = "-ccbk.7z"

    public static func startFile(compressedPubkey: Data) throws -> Data {
        try validateCompressed(compressedPubkey)
        let object: [String: String] = ["pubkey": compressedPubkey.hexString]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func parseStartFile(_ data: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hex = object["pubkey"] as? String else {
            throw CloneTransferError.invalidStartFile
        }
        let pubkey = try Data(hex: hex)
        try validateCompressed(pubkey)
        return pubkey
    }

    public static func cloneFilename(compressedPubkey: Data) -> String {
        compressedPubkey.hexString + cloneSuffix7z
    }

    public static func parseCloneFilename(_ name: String) throws -> Data {
        let lower = name.lowercased()
        guard lower.hasSuffix(cloneSuffixJSON) || lower.hasSuffix(cloneSuffix7z) else {
            throw CloneTransferError.invalidCloneFilename
        }
        let stem = URL(fileURLWithPath: name).lastPathComponent
        guard stem.count >= 66 else { throw CloneTransferError.invalidCloneFilename }
        let pubkey = try Data(hex: String(stem.prefix(66)))
        try validateCompressed(pubkey)
        return pubkey
    }

    public static func sessionPasswordHex(privateKey: Data, theirPubkey: Data) throws -> String {
        try Secp256k1.ecdhHash(privateKey: privateKey, otherPublicKey: theirPubkey).hexString
    }

    private static func validateCompressed(_ pubkey: Data) throws {
        guard pubkey.count == 33, pubkey[0] == 0x02 || pubkey[0] == 0x03 else {
            throw CloneTransferError.invalidPublicKey
        }
    }
}

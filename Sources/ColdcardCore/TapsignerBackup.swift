import Foundation

public enum TapsignerBackupError: Error, Equatable, Sendable {
    case invalidKey
    case decryptionFailed
    case invalidPayload
}

/// TAPSIGNER encrypted backup (`shared/tapsigner.py`): AES-128-CTR, zero IV, first line is an XPRV.
public struct TapsignerBackup: Equatable, Sendable {
    public let extendedPrivateKey: String
    public let derivation: String

    public static func decrypt(backupKeyHex: String, data: Data) throws -> TapsignerBackup {
        let hex = backupKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count == 32, hex.allSatisfy(\.isHexDigit) else { throw TapsignerBackupError.invalidKey }
        let key = try Data(hex: hex)
        let clear = try AESCTR.crypt(key: key, nonce: Data(repeating: 0, count: 16), data: data)
        guard let text = String(data: clear, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.count >= 4,
              Array(text.utf8).dropFirst().prefix(3).elementsEqual(Array("prv".utf8)) else {
            throw TapsignerBackupError.decryptionFailed
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let extended = lines.first, extended.lowercased().contains("prv") else {
            throw TapsignerBackupError.decryptionFailed
        }
        let derivation = lines.count > 1 ? lines[1] : ""
        return TapsignerBackup(extendedPrivateKey: extended, derivation: derivation)
    }

    /// Firmware QR path: hex digits first, otherwise Base64 (`tapsigner.py`).
    public static func payload(fromQR text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hex = try? Data(hex: trimmed), !hex.isEmpty { return hex }
        if let base64 = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]), !base64.isEmpty {
            return base64
        }
        throw TapsignerBackupError.invalidPayload
    }
}

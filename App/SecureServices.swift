import Foundation
import Security
import CryptoKit
import ColdcardCore

nonisolated enum SecureServiceError: LocalizedError {
    case randomFailure(OSStatus)
    case keychainFailure(OSStatus)
    case invalidBackup
    case wrongPassword
    case truncatedHeaders
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .randomFailure(let status): "Unable to obtain secure system entropy (OSStatus \(status))."
        case .keychainFailure(let status): "Unable to access the iOS Keychain (OSStatus \(status))."
        case .invalidBackup: "This file is not a valid simulator backup."
        case .wrongPassword: "Incorrect password or corrupted backup."
        case .truncatedHeaders: BackupFile.unableToReadHeaders
        case .verifyFailed(let detail): BackupFile.verifyFailure(problem: BackupFile.unableToVerifyContents, error: detail)
        }
    }
}

nonisolated enum SecureRandom {
    static func bytes(count: Int) throws -> Data {
        var data = Data(repeating: 0, count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw SecureServiceError.randomFailure(status) }
        return data
    }
}

nonisolated enum KeychainStore {
    private static let service = "dev.thales.ColdcardQSimulator"
    private static let walletAccount = "wallet-record"
    /// Firmware `rom_secrets->pairing_secret` analogue (32 bytes); not the wallet seed.
    private static let pairingAccount = "pairing-secret"

    static func save(_ data: Data) throws { try save(data, account: walletAccount) }
    static func load() throws -> Data? { try load(account: walletAccount) }
    static func delete() throws { try delete(account: walletAccount) }

    static func savePairingSecret(_ data: Data) throws { try save(data, account: pairingAccount) }
    static func loadPairingSecret() throws -> Data? { try load(account: pairingAccount) }

    private static func save(_ data: Data, account: String) throws {
        let query = itemQuery(account: account)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecureServiceError.keychainFailure(status) }
    }

    private static func load(account: String) throws -> Data? {
        var query = itemQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecureServiceError.keychainFailure(status) }
        return data
    }

    private static func delete(account: String) throws {
        let status = SecItemDelete(itemQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureServiceError.keychainFailure(status) }
    }

    private static func itemQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

nonisolated enum BackupCrypto {
    private static let iterations = 100_000

    static func encrypt(_ payload: WalletBackupPayload, password: String) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encryptBytes(try encoder.encode(payload), password: password, innerExt: "txt")
    }

    static func encryptBytes(_ plaintext: Data, password: String, innerExt: String = "txt") throws -> Data {
        let salt = try SecureRandom.bytes(count: 16)
        let keyData = pbkdf2SHA256(password: Data(password.utf8), salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: keyData))
        guard let combined = box.combined else { throw SecureServiceError.invalidBackup }
        let word = BIP39EnglishWords.all[Int.random(in: 0..<BIP39EnglishWords.all.count)]
        let number = Int.random(in: 0..<1000)
        let inner = BackupFile.innerFilename(word: word, number: number, ext: innerExt)
        let envelope = BackupEnvelope(iterations: iterations, salt: salt, sealedBox: combined,
                                      innerFilename: inner)
        let out = JSONEncoder(); out.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try out.encode(envelope)
    }

    static func decryptBytes(_ data: Data, password: String) throws -> Data {
        let envelope: BackupEnvelope
        do {
            envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        } catch {
            throw SecureServiceError.invalidBackup
        }
        guard envelope.format == "coldcard-q-swift-simulator-encrypted/1",
              envelope.iterations >= 10_000, envelope.salt.count >= 16 else { throw SecureServiceError.invalidBackup }
        let keyData = pbkdf2SHA256(password: Data(password.utf8), salt: envelope.salt, iterations: envelope.iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.sealedBox)
            return try AES.GCM.open(box, using: SymmetricKey(data: keyData))
        } catch {
            throw SecureServiceError.wrongPassword
        }
    }

    static func verifyEnvelope(_ data: Data, innerExt: String = "txt") throws {
        let envelope: BackupEnvelope
        do {
            envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        } catch {
            throw SecureServiceError.truncatedHeaders
        }
        guard envelope.format == "coldcard-q-swift-simulator-encrypted/1",
              envelope.iterations >= 10_000, envelope.salt.count >= 16,
              envelope.sealedBox.count >= 28 else {
            throw SecureServiceError.truncatedHeaders
        }
        do {
            _ = try AES.GCM.SealedBox(combined: envelope.sealedBox)
        } catch {
            throw SecureServiceError.verifyFailed("malformed")
        }
        if let inner = envelope.innerFilename, !inner.lowercased().hasSuffix(".\(innerExt)") {
            throw SecureServiceError.verifyFailed("not \(innerExt)")
        }
        let plaintextGuess = envelope.sealedBox.count - 28
        if innerExt == "txt", plaintextGuess > 0, !BackupFile.isPlausibleInnerSize(plaintextGuess) {
            throw SecureServiceError.verifyFailed("size")
        }
    }

    static func decrypt(_ data: Data, password: String) throws -> WalletBackupPayload {
        do {
            let clear = try decryptBytes(data, password: password)
            let payload = try JSONDecoder().decode(WalletBackupPayload.self, from: clear)
            guard payload.format == "coldcard-q-swift-simulator-backup/1" else { throw SecureServiceError.invalidBackup }
            return payload
        } catch let error as SecureServiceError {
            throw error
        } catch {
            throw SecureServiceError.wrongPassword
        }
    }

    private static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int) -> Data {
        let key = SymmetricKey(data: password)
        var block = salt
        block.append(contentsOf: [0, 0, 0, 1])
        var u = Data(CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(for: block, using: key))
        var output = u
        if iterations > 1 {
            for _ in 2...iterations {
                u = Data(CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(for: u, using: key))
                output.withUnsafeMutableBytes { outBuffer in
                    u.withUnsafeBytes { uBuffer in
                        let out = outBuffer.bindMemory(to: UInt8.self)
                        let input = uBuffer.bindMemory(to: UInt8.self)
                        for index in 0..<out.count { out[index] ^= input[index] }
                    }
                }
            }
        }
        return output
    }
}

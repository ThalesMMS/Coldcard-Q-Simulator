import Foundation

public enum KeyTeleportError: Error, Equatable, Sendable {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidNoidKey
    case invalidPassword
    case checksumFailed
    case truncated
}

public struct KeyTeleportReceiverCode: Equatable, Sendable {
    public let numericCode: String
    public let encryptedPubkey: Data
}

public struct KeyTeleportStep1: Equatable, Sendable {
    public let sessionKey: Data
    public let senderPubkey: Data
    public let body: Data
}

public struct KeyTeleportPSBTStep1: Equatable, Sendable {
    public let nonce: UInt32
    public let sessionKey: Data
    public let body: Data
}

/// Firmware `teleport.py` / `docs/key-teleport.md`.
public enum KeyTeleport {
    /// Firmware `KT_RXPUBKEY_DERIV` (`multisig.py`).
    public static let receiverPubkeyChild: UInt32 = 20_250_317
    public static let webHost = "keyteleport.com"
    public static let noidKeyLength = 5
    public static let numericCodeLength = 8
    public static let paranoidPasswordLength = 8
    public static let pbkdf2Rounds = 5000
    /// Firmware typo in the salt (`COLCARD4EVER`).
    public static let receiverSalt = Data("COLCARD4EVER".utf8)

    public static func grouped(_ text: String) -> String {
        stride(from: 0, to: text.count, by: 2).map { start in
            let index = text.index(text.startIndex, offsetBy: start)
            let end = text.index(index, offsetBy: min(2, text.count - start))
            return String(text[index..<end])
        }.joined(separator: " ")
    }

    public static func generateReceiverCode(privateKey: Data) throws -> KeyTeleportReceiverCode {
        guard Secp256k1.privateKeyIsValid(privateKey) else { throw KeyTeleportError.invalidPrivateKey }
        var pubkey = [UInt8](try Secp256k1.publicKey(fromPrivateKey: privateKey))
        let nk = SHA2.doubleSHA256(privateKey + receiverSalt)
        pubkey[0] ^= nk[20] & 0xfe
        let numeric = UInt32(nk[4]) << 24 | UInt32(nk[5]) << 16 | UInt32(nk[6]) << 8 | UInt32(nk[7])
        let code = String(format: "%08d", numeric % 100_000_000)
        let key = SHA2.sha256(Data(code.utf8))
        let encrypted = AES256CTR.crypt(key: key, data: Data(pubkey))
        return KeyTeleportReceiverCode(numericCode: code, encryptedPubkey: encrypted)
    }

    public static func decryptReceiverPubkey(code: String, payload: Data) -> Data? {
        guard payload.count == 33, code.count == numericCodeLength, code.allSatisfy(\.isNumber) else { return nil }
        let key = SHA2.sha256(Data(code.utf8))
        var pubkey = [UInt8](AES256CTR.crypt(key: key, data: payload))
        guard pubkey.count == 33 else { return nil }
        pubkey[0] &= 0x01
        pubkey[0] |= 0x02
        let restored = Data(pubkey)
        return (try? Secp256k1.parsePublicKey(restored)) == nil ? nil : restored
    }

    public static func encodePayload(
        senderPrivateKey: Data,
        receiverPubkey: Data,
        noidKey: Data,
        body: Data,
        forPSBT: Bool = false,
        prefix: Data = Data()
    ) throws -> Data {
        guard receiverPubkey.count == 33 else { throw KeyTeleportError.invalidPublicKey }
        guard noidKey.count == noidKeyLength else { throw KeyTeleportError.invalidNoidKey }
        let sessionKey = try Secp256k1.ecdhSessionKey(privateKey: senderPrivateKey, publicKey: receiverPubkey)
        let stretched = noidStretch(sessionKey: sessionKey, noidKey: noidKey)
        var inner = AES256CTR.crypt(key: stretched, data: body)
        inner.append(SHA2.sha256(body).suffix(2))
        var outer = AES256CTR.crypt(key: sessionKey, data: inner)
        outer.append(SHA2.sha256(inner).suffix(2))
        if forPSBT { return prefix + outer }
        let senderPub = try Secp256k1.publicKey(fromPrivateKey: senderPrivateKey)
        return prefix + senderPub + outer
    }

    public static func decodeStep1(receiverPrivateKey: Data, payload: Data) throws -> KeyTeleportStep1 {
        guard payload.count >= 33 + 3 else { throw KeyTeleportError.truncated }
        let senderPubkey = Data(payload.prefix(33))
        let body = Data(payload.dropFirst(33))
        let (session, inner) = try unwrapSession(privateKey: receiverPrivateKey, publicKey: senderPubkey, body: body)
        return KeyTeleportStep1(sessionKey: session, senderPubkey: senderPubkey, body: inner)
    }

    public static func decodePSBTStep1(
        receiverPrivateKey: Data,
        senderPubkey: Data,
        payload: Data
    ) throws -> KeyTeleportPSBTStep1 {
        guard payload.count >= 4 + 3 else { throw KeyTeleportError.truncated }
        let nonce = payload.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let body = Data(payload.dropFirst(4))
        let (session, inner) = try unwrapSession(privateKey: receiverPrivateKey, publicKey: senderPubkey, body: body)
        return KeyTeleportPSBTStep1(nonce: nonce, sessionKey: session, body: inner)
    }

    public static func decodeStep2(sessionKey: Data, noidKey: Data, body: Data) throws -> Data {
        guard noidKey.count == noidKeyLength else { throw KeyTeleportError.invalidNoidKey }
        guard body.count >= 3 else { throw KeyTeleportError.truncated }
        let stretched = noidStretch(sessionKey: sessionKey, noidKey: noidKey)
        let message = AES256CTR.crypt(key: stretched, data: Data(body.dropLast(2)))
        let checksum = SHA2.sha256(message).suffix(2)
        guard checksum == body.suffix(2) else { throw KeyTeleportError.checksumFailed }
        return message
    }

    public static func noidPassword(from key: Data) -> String {
        precondition(key.count == noidKeyLength)
        return Base32.encode(key)
    }

    public static func noidKey(fromPassword password: String) throws -> Data {
        let compact = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count == paranoidPasswordLength else { throw KeyTeleportError.invalidPassword }
        let mapped = String(compact.map { character -> Character in
            switch character {
            case "0": return "O"
            case "1": return "I"
            case "8": return "B"
            default: return character
            }
        })
        let decoded = try Base32.decode(mapped)
        guard decoded.count == noidKeyLength else { throw KeyTeleportError.invalidPassword }
        return decoded
    }

    public static func derivedTeleportPubkey(from xpub: HDKey, nonce: UInt32) throws -> Data {
        try xpub.derived(index: receiverPubkeyChild).derived(index: nonce).publicKey
    }

    public static func derivedTeleportPrivateKey(root: HDKey, xpubPath: DerivationPath, nonce: UInt32) throws -> Data {
        let path = xpubPath.appending(receiverPubkeyChild).appending(nonce)
        guard let privateKey = try root.derived(path: path).privateKey else { throw KeyTeleportError.invalidPrivateKey }
        return privateKey
    }

    public static func webURL(bbqr: String) -> String {
        "https://\(webHost)/#\(bbqr)"
    }

    public static func shortBBQr(fileType: BBQrFileType, data: Data) -> String {
        "B$2\(fileType.rawValue)0100" + Base32.encode(data)
    }

    private static func unwrapSession(privateKey: Data, publicKey: Data, body: Data) throws -> (Data, Data) {
        guard body.count >= 3 else { throw KeyTeleportError.truncated }
        let session = try Secp256k1.ecdhSessionKey(privateKey: privateKey, publicKey: publicKey)
        let inner = AES256CTR.crypt(key: session, data: Data(body.dropLast(2)))
        let checksum = SHA2.sha256(inner).suffix(2)
        guard checksum == body.suffix(2) else { throw KeyTeleportError.checksumFailed }
        return (session, inner)
    }

    private static func noidStretch(sessionKey: Data, noidKey: Data) -> Data {
        PBKDF2.hmacSHA512(password: sessionKey, salt: noidKey, iterations: pbkdf2Rounds, keyLength: 32)
    }
}

extension KeyTeleportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey: "Invalid Key Teleport private key."
        case .invalidPublicKey: "Invalid Key Teleport public key."
        case .invalidNoidKey: "Invalid Teleport Password key."
        case .invalidPassword: "Incorrect Teleport Password."
        case .checksumFailed: "QR code was damaged, numeric password was wrong, or it was sent to a different user. Sender must start again."
        case .truncated: "Truncated Key Teleport payload."
        }
    }
}

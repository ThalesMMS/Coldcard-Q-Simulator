import Foundation

/// Firmware `drv_entro.py` BIP-85 derivation (`hmac_sha512("bip-entropy-from-k", privkey)`).
public enum BIP85Kind: Int, Sendable, CaseIterable {
    case words12 = 0
    case words18 = 1
    case words24 = 2
    case wif = 3
    case xprv = 4
    case hex32 = 5
    case hex64 = 6
    case password = 7

    public var menuTitle: String {
        switch self {
        case .words12: "12 words"
        case .words18: "18 words"
        case .words24: "24 words"
        case .wif: "WIF (privkey)"
        case .xprv: "XPRV (BIP-32)"
        case .hex32: "32-bytes hex"
        case .hex64: "64-bytes hex"
        case .password: "Passwords"
        }
    }

    public var wordCount: Int? {
        switch self {
        case .words12: 12
        case .words18: 18
        case .words24: 24
        default: nil
        }
    }
}

/// Firmware `drv_entro_start` kind picker (`drv_entro.py`).
public enum BIP85MenuCopy {
    /// Untitled `MenuSystem` of application types; parent Advanced row is `Derive Seeds (BIP-85)`.
    public static let kindMenuTitle = ""
}

public struct BIP85Result: Equatable, Sendable {
    public let kind: BIP85Kind
    public let index: UInt32
    public let path: String
    public let entropy: Data
    public let display: String
    public let qr: String
    public let qrAlphanumeric: Bool
    public let derivedXFP: String?
}

public enum BIP85 {
    public static let passwordLength = 21

    public static func derive(root: HDKey, kind: BIP85Kind, index: UInt32) throws -> BIP85Result {
        let path: DerivationPath
        let width: Int
        switch kind {
        case .words12: path = try DerivationPath("m/83696968h/39h/0h/12h/\(index)h"); width = 16
        case .words18: path = try DerivationPath("m/83696968h/39h/0h/18h/\(index)h"); width = 24
        case .words24: path = try DerivationPath("m/83696968h/39h/0h/24h/\(index)h"); width = 32
        case .wif: path = try DerivationPath("m/83696968h/2h/\(index)h"); width = 32
        case .xprv: path = try DerivationPath("m/83696968h/32h/\(index)h"); width = 64
        case .hex32: path = try DerivationPath("m/83696968h/128169h/32h/\(index)h"); width = 32
        case .hex64: path = try DerivationPath("m/83696968h/128169h/64h/\(index)h"); width = 64
        case .password: path = try DerivationPath("m/83696968h/707764h/\(passwordLength)h/\(index)h"); width = 64
        }
        let node = try root.derived(path: path)
        guard let privateKey = node.privateKey else { throw BIP32Error.invalidKey }
        let full = HMAC.sha512(key: Data("bip-entropy-from-k".utf8), message: privateKey)
        let entropy = Data(full.prefix(width))
        return try format(kind: kind, index: index, path: path.description, entropy: entropy, network: root.network)
    }

    public static func password(from secret: Data) -> String {
        String(secret.base64EncodedString().prefix(passwordLength))
    }

    private static func format(kind: BIP85Kind, index: UInt32, path: String, entropy: Data,
                               network: BitcoinNetwork) throws -> BIP85Result {
        switch kind {
        case .words12, .words18, .words24:
            let mnemonic = try BIP39Mnemonic(entropy: entropy)
            let seed = mnemonic.seed()
            let derived = try HDKey(seed: seed, network: network)
            let words = mnemonic.words
            let display = "Seed words (\(words.count)):\n" + words.enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
            let qr = words.map { String($0.prefix(4)) }.joined(separator: " ")
            return BIP85Result(kind: kind, index: index, path: path, entropy: entropy, display: display,
                               qr: qr, qrAlphanumeric: true, derivedXFP: derived.coldcardFingerprintHex)
        case .wif:
            var payload = entropy
            payload.append(0x01)
            let wif = Base58.checkEncode(version: Data([network.wifPrefix]), payload: payload)
            return BIP85Result(kind: kind, index: index, path: path, entropy: entropy,
                               display: "WIF (privkey):\n" + wif, qr: wif, qrAlphanumeric: false, derivedXFP: nil)
        case .xprv:
            let chain = Data(entropy.prefix(32))
            let priv = Data(entropy.suffix(32))
            let node = try HDKey.master(privateKey: priv, chainCode: chain, network: network)
            let xprv = try node.serializePrivate()
            return BIP85Result(kind: kind, index: index, path: path, entropy: entropy,
                               display: "Derived XPRV:\n" + xprv, qr: xprv, qrAlphanumeric: false,
                               derivedXFP: node.coldcardFingerprintHex)
        case .hex32, .hex64:
            let hex = entropy.hexString
            return BIP85Result(kind: kind, index: index, path: path, entropy: entropy,
                               display: "Hex (\(entropy.count) bytes):\n" + hex, qr: hex,
                               qrAlphanumeric: true, derivedXFP: nil)
        case .password:
            let pw = password(from: entropy)
            return BIP85Result(kind: kind, index: index, path: path, entropy: entropy,
                               display: "Password:\n" + pw, qr: pw, qrAlphanumeric: false, derivedXFP: nil)
        }
    }
}

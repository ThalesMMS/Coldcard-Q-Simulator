import Foundation

public enum WIFError: Error, Equatable, Sendable {
    case invalidPayload
    case invalidVersion
    case uncompressedOnly
    case wrongNetwork
    case invalidPrivateKey
    case noValidKey(duplicates: Bool)
    case capacity(attempted: Int, remaining: Int)
}

/// Decoded Wallet Import Format key. Firmware `decode_wif` in `shared/wif.py`.
public struct DecodedWIF: Equatable, Sendable {
    public let privateKey: Data
    public let publicKey: Data
    public let compressed: Bool
    public let isTestnet: Bool

    public var privateKeyHex: String { privateKey.hexString }
    public var publicKeyHex: String { publicKey.hexString }

    public func encode(network: BitcoinNetwork, compressed: Bool? = nil) -> String {
        let useCompressed = compressed ?? self.compressed
        var payload = privateKey
        if useCompressed { payload.append(0x01) }
        return Base58.checkEncode(version: Data([network.wifPrefix]), payload: payload)
    }
}

public struct WIFStoreItem: Equatable, Codable, Sendable {
    public var publicKeyHex: String
    public var privateKeyHex: String

    public init(publicKeyHex: String, privateKeyHex: String) {
        self.publicKeyHex = publicKeyHex
        self.privateKeyHex = privateKeyHex
    }

    public init(_ decoded: DecodedWIF) {
        publicKeyHex = decoded.publicKeyHex
        privateKeyHex = decoded.privateKeyHex
    }

    public var publicKey: Data? { try? Data(hex: publicKeyHex) }
    public var privateKey: Data? { try? Data(hex: privateKeyHex) }
}

public enum WIF {
    public static let maxStoreItems = 30

    public static func decode(_ wif: String) throws -> DecodedWIF {
        let raw: Data
        do {
            raw = try Base58.checkDecode(wif)
        } catch {
            throw WIFError.invalidPayload
        }
        guard raw.count >= 1 else { throw WIFError.invalidPayload }
        let version = raw[0]
        guard version == 0x80 || version == 0xef else { throw WIFError.invalidVersion }
        guard raw.count == 33 || raw.count == 34 else { throw WIFError.invalidPayload }
        var compressed = false
        if raw.count == 34 {
            guard raw[33] == 0x01 else { throw WIFError.invalidPayload }
            compressed = true
        }
        let privateKey = Data(raw[1..<33])
        guard Secp256k1.privateKeyIsValid(privateKey) else { throw WIFError.invalidPrivateKey }
        let publicKey = try Secp256k1.publicKey(fromPrivateKey: privateKey, compressed: compressed)
        return DecodedWIF(privateKey: privateKey, publicKey: publicKey, compressed: compressed,
                          isTestnet: version == 0xef)
    }

    public static func decode(_ wif: String, expectedNetwork: BitcoinNetwork) throws -> DecodedWIF {
        let decoded = try decode(wif)
        let wantsTestnet = expectedNetwork != .mainnet
        guard decoded.isTestnet == wantsTestnet else { throw WIFError.wrongNetwork }
        return decoded
    }

    /// Firmware import path: compressed keys only, must match the current chain.
    public static func decodeForStore(_ wif: String, network: BitcoinNetwork) throws -> WIFStoreItem {
        let decoded = try decode(wif)
        guard decoded.compressed else { throw WIFError.uncompressedOnly }
        let wantsTestnet = network != .mainnet
        guard decoded.isTestnet == wantsTestnet else { throw WIFError.wrongNetwork }
        return WIFStoreItem(decoded)
    }
}

public enum WIFStoreLogic {
    public static let maxItems = WIF.maxStoreItems

    public static func parseImport(_ text: String, network: BitcoinNetwork,
                                   existing: [WIFStoreItem]) throws -> [WIFStoreItem] {
        let tokens = text.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        var incoming: [WIFStoreItem] = []
        for token in tokens where !token.isEmpty {
            do {
                incoming.append(try WIF.decodeForStore(token, network: network))
            } catch let error as WIFError {
                switch error {
                case .uncompressedOnly, .wrongNetwork:
                    throw error
                default:
                    continue
                }
            } catch {
                continue
            }
        }
        return try merge(existing: existing, incoming: incoming)
    }

    public static func merge(existing: [WIFStoreItem], incoming: [WIFStoreItem]) throws -> [WIFStoreItem] {
        var unique: [WIFStoreItem] = []
        var duplicates = 0
        for item in incoming {
            if unique.contains(item) { continue }
            if existing.contains(item) {
                duplicates += 1
            } else {
                unique.append(item)
            }
        }
        guard !unique.isEmpty else { throw WIFError.noValidKey(duplicates: duplicates > 0) }
        let remaining = maxItems - existing.count
        guard existing.count + unique.count <= maxItems else {
            throw WIFError.capacity(attempted: unique.count, remaining: remaining)
        }
        return existing + unique
    }

    /// Firmware `WIFStoreMenu.construct` (`wif.py`): Import WIF, keys, else inert `(none yet)`.
    public static func rootMenuTitles(itemLabels: [String], hobbled: Bool) -> [String] {
        var titles: [String] = []
        if itemLabels.count < maxItems, !hobbled {
            titles.append("Import WIF")
        }
        if itemLabels.isEmpty {
            titles.append("(none yet)")
        } else {
            titles.append(contentsOf: itemLabels)
            if itemLabels.count > 1 {
                titles.append("Export All")
                if !hobbled {
                    titles.append("Clear All")
                }
            }
        }
        return titles
    }

    /// Firmware `"%2d: %s" % (i+1, wif[0:clen] + '⋯' + wif[-clen:])` with Q `clen=12`.
    public static func menuLabel(index: Int, wif: String, qwerty: Bool = true) -> String {
        let clen = qwerty ? 12 : 5
        let truncated: String
        if wif.count > clen * 2 {
            truncated = String(wif.prefix(clen)) + "⋯" + String(wif.suffix(clen))
        } else {
            truncated = wif
        }
        return String(format: "%2d: %@", index + 1, truncated)
    }

    public static func encodedWIF(_ item: WIFStoreItem, network: BitcoinNetwork) throws -> String {
        guard let privateKey = item.privateKey, Secp256k1.privateKeyIsValid(privateKey) else {
            throw WIFError.invalidPrivateKey
        }
        var payload = privateKey
        payload.append(0x01)
        return Base58.checkEncode(version: Data([network.wifPrefix]), payload: payload)
    }

    public static func descriptor(publicKeyHex: String, type: AddressType) throws -> String {
        let raw: String
        switch type {
        case .nativeSegwit: raw = "wpkh(\(publicKeyHex))"
        case .legacy: raw = "pkh(\(publicKeyHex))"
        case .wrappedSegwit: raw = "sh(wpkh(\(publicKeyHex)))"
        case .taproot: throw WalletExportError.unsupportedAddressType
        }
        return DescriptorChecksum.append(to: raw)
    }

    /// Firmware `wif_desc_%d.txt % af` using `public_constants` AF bit codes.
    public static func descriptorFilename(type: AddressType) -> String {
        "wif_desc_\(type.firmwareAddressFormat).txt"
    }

    public static func matchAddressHash(items: [WIFStoreItem], scriptPubKey: Data) -> Int? {
        for (index, item) in items.enumerated() {
            guard let publicKey = item.publicKey else { continue }
            if let p2wpkh = try? BitcoinAddress.scriptPubKey(publicKey: publicKey, type: .nativeSegwit),
               p2wpkh == scriptPubKey { return index }
            if let p2pkh = try? BitcoinAddress.scriptPubKey(publicKey: publicKey, type: .legacy),
               p2pkh == scriptPubKey { return index }
            if let p2sh = try? BitcoinAddress.scriptPubKey(publicKey: publicKey, type: .wrappedSegwit),
               p2sh == scriptPubKey { return index }
        }
        return nil
    }
}

extension AddressType {
    /// Firmware `public_constants` AF_* numeric codes.
    public var firmwareAddressFormat: Int {
        switch self {
        case .legacy: 0x01
        case .nativeSegwit: 0x07
        case .wrappedSegwit: 0x13
        case .taproot: 0x23
        }
    }
}

import Foundation
#if SWIFT_PACKAGE
import BigInt
#endif

public enum BIP32Error: Error, Equatable {
    case invalidSeed
    case invalidKey
    case invalidExtendedKey
    case hardenedDerivationFromPublicKey
    case invalidChild
    case invalidPath(String)
    case wrongNetwork
}

public enum BitcoinNetwork: String, Codable, CaseIterable, Sendable {
    case mainnet
    case testnet
    case regtest

    public var displayName: String {
        switch self {
        case .mainnet: "Bitcoin Mainnet"
        case .testnet: "Bitcoin Testnet 4"
        case .regtest: "Bitcoin Regtest"
        }
    }

    public var coinType: UInt32 { self == .mainnet ? 0 : 1 }
    /// Firmware `chains.ccc_min_block` (`block_height.py` / `chains.py`).
    public var cccMinBlock: UInt32 { self == .mainnet ? 960_398 : 0 }
    /// Firmware `chains.ctype` tickers used by `render_value`.
    public var ticker: String {
        switch self {
        case .mainnet: "BTC"
        case .testnet: "XTN"
        case .regtest: "XRT"
        }
    }
    public var p2pkhPrefix: UInt8 { self == .mainnet ? 0x00 : 0x6f }
    public var p2shPrefix: UInt8 { self == .mainnet ? 0x05 : 0xc4 }
    public var wifPrefix: UInt8 { self == .mainnet ? 0x80 : 0xef }
    public var bech32HRP: String {
        switch self {
        case .mainnet: "bc"
        case .testnet: "tb"
        case .regtest: "bcrt"
        }
    }

    fileprivate var xpubVersion: UInt32 { self == .mainnet ? 0x0488b21e : 0x043587cf }
    fileprivate var xprvVersion: UInt32 { self == .mainnet ? 0x0488ade4 : 0x04358394 }
}

public enum AddressType: String, Codable, CaseIterable, Sendable, Identifiable {
    case legacy
    case wrappedSegwit
    case nativeSegwit
    case taproot

    public var id: String { rawValue }
    /// Address types shown in the firmware Address Explorer (no Taproot in the pinned commit).
    public static var explorerCases: [AddressType] { [.legacy, .wrappedSegwit, .nativeSegwit] }
    /// Firmware `chains.SINGLESIG_AF` menu order: Segwit P2WPKH, Classic P2PKH, P2SH-Segwit.
    public static var singlesigExportOrder: [AddressType] { [.nativeSegwit, .legacy, .wrappedSegwit] }
    public var purpose: UInt32 {
        switch self {
        case .legacy: 44
        case .wrappedSegwit: 49
        case .nativeSegwit: 84
        case .taproot: 86
        }
    }
    public var displayName: String {
        switch self {
        case .legacy: "Classic P2PKH"
        case .wrappedSegwit: "P2SH-Segwit"
        case .nativeSegwit: "Segwit P2WPKH"
        case .taproot: "Taproot P2TR"
        }
    }
}

public struct DerivationPath: Equatable, Hashable, Codable, Sendable, CustomStringConvertible {
    public static let hardened: UInt32 = 0x8000_0000
    /// Firmware `public_constants.MAX_PATH_DEPTH` — USB/string paths (`utils.cleanup_deriv_path`).
    public static let maxDepth = 12
    public let components: [UInt32]

    public init(_ components: [UInt32] = []) { self.components = components }

    public init(_ string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BIP32Error.invalidPath(string) }
        let pieces = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        let startsAtMaster = pieces.first == "m" || pieces.first == "M"
        let values = startsAtMaster ? pieces.dropFirst() : pieces[...]
        var parsed: [UInt32] = []
        for raw in values {
            var component = String(raw)
            guard !component.isEmpty else { throw BIP32Error.invalidPath(string) }
            let isHardened = component.hasSuffix("'") || component.hasSuffix("h") || component.hasSuffix("H")
            if isHardened { component.removeLast() }
            guard let value = UInt32(component), value < Self.hardened else { throw BIP32Error.invalidPath(string) }
            parsed.append(value | (isHardened ? Self.hardened : 0))
        }
        // Firmware `cleanup_deriv_path`: `assert len(parts) <= MAX_PATH_DEPTH, "too deep"`.
        guard parsed.count <= Self.maxDepth else { throw BIP32Error.invalidPath(string) }
        self.components = parsed
    }

    public var description: String {
        "m" + components.map { component in
            let hardened = component & Self.hardened != 0
            return "/\(component & ~Self.hardened)\(hardened ? "h" : "")"
        }.joined()
    }

    public static func account(type: AddressType, network: BitcoinNetwork, account: UInt32 = 0) -> DerivationPath {
        DerivationPath([type.purpose | hardened, network.coinType | hardened, account | hardened])
    }

    public func appending(_ value: UInt32, hardened: Bool = false) -> DerivationPath {
        DerivationPath(components + [value | (hardened ? Self.hardened : 0)])
    }
}

public struct HDKey: Equatable, Sendable {
    public let privateKey: Data?
    public let publicKey: Data
    public let chainCode: Data
    public let depth: UInt8
    public let parentFingerprint: Data
    public let childNumber: UInt32
    public let network: BitcoinNetwork

    public init(seed: Data, network: BitcoinNetwork = .testnet) throws {
        guard !seed.isEmpty else { throw BIP32Error.invalidSeed }
        let digest = HMAC.sha512(key: Data("Bitcoin seed".utf8), message: seed)
        let privateKey = Data(digest.prefix(32))
        guard Secp256k1.privateKeyIsValid(privateKey) else { throw BIP32Error.invalidSeed }
        self.privateKey = privateKey
        self.publicKey = try Secp256k1.publicKey(fromPrivateKey: privateKey)
        self.chainCode = Data(digest.suffix(32))
        self.depth = 0
        self.parentFingerprint = Data(repeating: 0, count: 4)
        self.childNumber = 0
        self.network = network
    }

    private init(privateKey: Data?, publicKey: Data, chainCode: Data, depth: UInt8,
                 parentFingerprint: Data, childNumber: UInt32, network: BitcoinNetwork) throws {
        guard chainCode.count == 32, parentFingerprint.count == 4, publicKey.count == 33 else { throw BIP32Error.invalidKey }
        if let privateKey, !Secp256k1.privateKeyIsValid(privateKey) { throw BIP32Error.invalidKey }
        _ = try Secp256k1.parsePublicKey(publicKey)
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.chainCode = chainCode
        self.depth = depth
        self.parentFingerprint = parentFingerprint
        self.childNumber = childNumber
        self.network = network
    }

    /// Parse a Base58Check extended key (xpub/tpub and SLIP-132 aliases). Neutered on success
    /// if the payload is public; private keys are accepted. Testnet versions also cover regtest.
    public init(extendedKey: String, network: BitcoinNetwork? = nil) throws {
        let body = try Base58.checkDecode(extendedKey)
        guard body.count == 78 else { throw BIP32Error.invalidExtendedKey }
        var reader = ByteReader(body)
        let version = try reader.readUInt32BE()
        let depth = try reader.readByte()
        let parentFingerprint = try reader.read(4)
        let childNumber = try reader.readUInt32BE()
        let chainCode = try reader.read(32)
        let keyData = try reader.read(33)
        let inferred: BitcoinNetwork
        if Self.mainnetExtendedVersions.contains(version) {
            inferred = .mainnet
        } else if Self.testnetExtendedVersions.contains(version) {
            inferred = network == .regtest ? .regtest : .testnet
        } else {
            throw BIP32Error.invalidExtendedKey
        }
        if let network, network != inferred, !(network == .regtest && inferred == .testnet) {
            throw BIP32Error.wrongNetwork
        }
        let resolved = network ?? inferred
        if keyData.first == 0 {
            let privateKey = Data(keyData.dropFirst())
            let publicKey = try Secp256k1.publicKey(fromPrivateKey: privateKey)
            try self.init(privateKey: privateKey, publicKey: publicKey, chainCode: chainCode, depth: depth,
                          parentFingerprint: parentFingerprint, childNumber: childNumber, network: resolved)
        } else {
            try self.init(privateKey: nil, publicKey: keyData, chainCode: chainCode, depth: depth,
                          parentFingerprint: parentFingerprint, childNumber: childNumber, network: resolved)
        }
    }

    private static let mainnetExtendedVersions: Set<UInt32> = [
        0x0488b21e, 0x0488ade4, 0x049d7cb2, 0x049d7878, 0x04b24746, 0x04b2430c,
        0x0295b43f, 0x0295b005, 0x02aa7ed3, 0x02aa7a99
    ]
    private static let testnetExtendedVersions: Set<UInt32> = [
        0x043587cf, 0x04358394, 0x044a5262, 0x044a4e28, 0x045f1cf6, 0x045f18bc,
        0x024289ef, 0x024285b5, 0x02575483, 0x02575048
    ]

    /// Firmware `node_from_privkey` / BIP-85 XPRV construction.
    public static func master(privateKey: Data, chainCode: Data,
                              network: BitcoinNetwork = .testnet) throws -> HDKey {
        let publicKey = try Secp256k1.publicKey(fromPrivateKey: privateKey)
        return try HDKey(privateKey: privateKey, publicKey: publicKey, chainCode: chainCode, depth: 0,
                         parentFingerprint: Data(repeating: 0, count: 4), childNumber: 0, network: network)
    }

    /// Deserialize a Base58Check xpub/xprv (or 78-byte PSBT global XPUB key data).
    public static func parseExtendedKey(_ string: String, network: BitcoinNetwork? = nil) throws -> HDKey {
        let body = try Base58.checkDecode(string.trimmingCharacters(in: .whitespacesAndNewlines))
        return try parseExtendedKeyData(body, network: network)
    }

    public static func parseExtendedKeyData(_ body: Data, network: BitcoinNetwork? = nil) throws -> HDKey {
        guard body.count == 78 else { throw BIP32Error.invalidExtendedKey }
        let version = body.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let depth = body[4]
        let parentFingerprint = Data(body[5..<9])
        let childNumber = body[9..<13].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let chainCode = Data(body[13..<45])
        let detected: BitcoinNetwork
        if let network {
            detected = network
        } else {
            let mainnet: Set<UInt32> = [0x0488b21e, 0x0488ade4, 0x049d7cb2, 0x049d7878, 0x04b24746, 0x04b2430c]
            detected = mainnet.contains(version) ? .mainnet : .testnet
        }
        if body[45] == 0 {
            let privateKey = Data(body[46..<78])
            let publicKey = try Secp256k1.publicKey(fromPrivateKey: privateKey)
            return try HDKey(privateKey: privateKey, publicKey: publicKey, chainCode: chainCode, depth: depth,
                             parentFingerprint: parentFingerprint, childNumber: childNumber, network: detected)
        }
        let publicKey = Data(body[45..<78])
        return try HDKey(privateKey: nil, publicKey: publicKey, chainCode: chainCode, depth: depth,
                         parentFingerprint: parentFingerprint, childNumber: childNumber, network: detected)
    }

    public var fingerprint: Data { Data(BitcoinHash.hash160(publicKey).prefix(4)) }
    public var fingerprintHex: String { fingerprint.hexString.uppercased() }
    public var coldcardFingerprintHex: String { Data(fingerprint.reversed()).hexString.uppercased() }
    /// Electrum / Blue `ckcc_xfp`: little-endian uint32 of the HASH160 prefix (`export.py`).
    public var ckccXFP: UInt32 {
        fingerprint.withUnsafeBytes { raw in
            raw.loadUnaligned(as: UInt32.self).littleEndian
        }
    }
    public var isPrivate: Bool { privateKey != nil }

    public func neutered() throws -> HDKey {
        try HDKey(privateKey: nil, publicKey: publicKey, chainCode: chainCode, depth: depth,
                  parentFingerprint: parentFingerprint, childNumber: childNumber, network: network)
    }

    public func derived(index: UInt32) throws -> HDKey {
        let hardened = index & DerivationPath.hardened != 0
        if hardened && privateKey == nil { throw BIP32Error.hardenedDerivationFromPublicKey }
        var input = Data()
        if hardened {
            input.append(0)
            input.append(privateKey!)
        } else {
            input.append(publicKey)
        }
        input.appendUInt32BE(index)
        let digest = HMAC.sha512(key: chainCode, message: input)
        let tweak = Data(digest.prefix(32))
        let tweakValue = BigUInt(tweak)
        guard tweakValue < Secp256k1.curveOrder else { throw BIP32Error.invalidChild }

        let nextPrivate: Data?
        let nextPublic: Data
        if let privateKey {
            guard tweakValue != 0 else { throw BIP32Error.invalidChild }
            nextPrivate = try Secp256k1.addPrivateKeys(privateKey, tweak)
            nextPublic = try Secp256k1.publicKey(fromPrivateKey: nextPrivate!)
        } else {
            nextPrivate = nil
            nextPublic = try Secp256k1.tweakAdd(publicKey: publicKey, tweak: tweak)
        }
        return try HDKey(privateKey: nextPrivate, publicKey: nextPublic, chainCode: Data(digest.suffix(32)),
                         depth: depth &+ 1, parentFingerprint: fingerprint, childNumber: index, network: network)
    }

    public func derived(path: DerivationPath) throws -> HDKey {
        try path.components.reduce(self) { key, component in try key.derived(index: component) }
    }

    public func serializePublic(addressType: AddressType? = nil, asMainnet: Bool = false) -> String {
        serialize(version: extendedPublicVersion(addressType: addressType, asMainnet: asMainnet), privateKey: false)
    }

    /// Firmware `chain.serialize_public(node, AF_P2WSH*)` SLIP-132 versions for Unchained / dump summary.
    public func serializePublic(version: UInt32) -> String {
        serialize(version: version, privateKey: false)
    }

    public func serializePrivate(addressType: AddressType? = nil) throws -> String {
        guard privateKey != nil else { throw BIP32Error.invalidKey }
        return serialize(version: extendedPrivateVersion(addressType: addressType), privateKey: true)
    }

    public func wif(compressed: Bool = true) throws -> String {
        guard let privateKey else { throw BIP32Error.invalidKey }
        var payload = privateKey
        if compressed { payload.append(0x01) }
        return Base58.checkEncode(version: Data([network.wifPrefix]), payload: payload)
    }

    private func serialize(version: UInt32, privateKey includePrivate: Bool) -> String {
        var versionData = Data(); versionData.appendUInt32BE(version)
        var payload = Data([depth])
        payload.append(parentFingerprint)
        payload.appendUInt32BE(childNumber)
        payload.append(chainCode)
        if includePrivate {
            payload.append(0)
            payload.append(privateKey!)
        } else {
            payload.append(publicKey)
        }
        return Base58.checkEncode(version: versionData, payload: payload)
    }

    private func extendedPublicVersion(addressType: AddressType?, asMainnet: Bool = false) -> UInt32 {
        let mainnet = asMainnet || network == .mainnet
        guard let addressType else { return mainnet ? 0x0488b21e : network.xpubVersion }
        return switch (mainnet, addressType) {
        case (true, .wrappedSegwit): 0x049d7cb2
        case (true, .nativeSegwit): 0x04b24746
        case (false, .wrappedSegwit): 0x044a5262
        case (false, .nativeSegwit): 0x045f1cf6
        default: mainnet ? 0x0488b21e : network.xpubVersion
        }
    }

    private func extendedPrivateVersion(addressType: AddressType?) -> UInt32 {
        guard let addressType else { return network.xprvVersion }
        return switch (network == .mainnet, addressType) {
        case (true, .wrappedSegwit): 0x049d7878
        case (true, .nativeSegwit): 0x04b2430c
        case (false, .wrappedSegwit): 0x044a4e28
        case (false, .nativeSegwit): 0x045f18bc
        default: network.xprvVersion
        }
    }
}

import Foundation

public enum BitcoinAddressError: Error, Equatable {
    case invalidPublicKey
    case unsupportedType
}

public struct DerivedAddress: Equatable, Codable, Sendable, Identifiable {
    public let index: UInt32
    public let change: Bool
    public let path: String
    public let address: String
    public let publicKeyHex: String
    public let scriptPubKeyHex: String

    public init(index: UInt32, change: Bool, path: String, address: String,
                publicKeyHex: String, scriptPubKeyHex: String) {
        self.index = index
        self.change = change
        self.path = path
        self.address = address
        self.publicKeyHex = publicKeyHex
        self.scriptPubKeyHex = scriptPubKeyHex
    }

    public var id: String { "\(path):\(address)" }
}

public enum BitcoinAddress {
    public static func address(publicKey: Data, type: AddressType, network: BitcoinNetwork) throws -> String {
        _ = try Secp256k1.parsePublicKey(publicKey)
        let keyHash = BitcoinHash.hash160(publicKey)
        switch type {
        case .legacy:
            return Base58.checkEncode(version: Data([network.p2pkhPrefix]), payload: keyHash)
        case .wrappedSegwit:
            let redeemScript = Data([0x00, 0x14]) + keyHash
            return Base58.checkEncode(version: Data([network.p2shPrefix]), payload: BitcoinHash.hash160(redeemScript))
        case .nativeSegwit:
            return try Bech32.encodeSegwit(hrp: network.bech32HRP, version: 0, program: keyHash)
        case .taproot:
            let point = try Secp256k1.parsePublicKey(publicKey)
            let internalKey = point.xData
            let outputKey = try Secp256k1.taprootOutputKey(internalKey: internalKey)
            return try Bech32.encodeSegwit(hrp: network.bech32HRP, version: 1, program: outputKey)
        }
    }

    public static func scriptPubKey(publicKey: Data, type: AddressType) throws -> Data {
        _ = try Secp256k1.parsePublicKey(publicKey)
        let keyHash = BitcoinHash.hash160(publicKey)
        switch type {
        case .legacy:
            return Data([0x76, 0xa9, 0x14]) + keyHash + Data([0x88, 0xac])
        case .wrappedSegwit:
            let redeem = Data([0x00, 0x14]) + keyHash
            return Data([0xa9, 0x14]) + BitcoinHash.hash160(redeem) + Data([0x87])
        case .nativeSegwit:
            return Data([0x00, 0x14]) + keyHash
        case .taproot:
            let point = try Secp256k1.parsePublicKey(publicKey)
            let output = try Secp256k1.taprootOutputKey(internalKey: point.xData)
            return Data([0x51, 0x20]) + output
        }
    }

    public static func redeemScriptForWrappedSegwit(publicKey: Data) -> Data {
        Data([0x00, 0x14]) + BitcoinHash.hash160(publicKey)
    }

    public static func derive(root: HDKey, type: AddressType, account: UInt32 = 0,
                              change: Bool = false, index: UInt32) throws -> DerivedAddress {
        let path = DerivationPath.account(type: type, network: root.network, account: account)
            .appending(change ? 1 : 0)
            .appending(index)
        return try derive(root: root, path: path, type: type)
    }

    /// Firmware `auth.ShowPKHAddress.setup` — derive the payment address at an exact path.
    public static func derive(root: HDKey, path: DerivationPath, type: AddressType) throws -> DerivedAddress {
        let child = try root.derived(path: path)
        let address = try address(publicKey: child.publicKey, type: type, network: root.network)
        let script = try scriptPubKey(publicKey: child.publicKey, type: type)
        let index = path.components.last.map { $0 & ~DerivationPath.hardened } ?? 0
        let change: Bool
        if path.components.count >= 2 {
            change = (path.components[path.components.count - 2] & ~DerivationPath.hardened) == 1
        } else {
            change = false
        }
        return DerivedAddress(index: index, change: change, path: path.description, address: address,
                              publicKeyHex: child.publicKey.hexString, scriptPubKeyHex: script.hexString)
    }
}

extension Secp256k1.PublicPoint {
    fileprivate var xData: Data {
        let serialized = Secp256k1.serialize(self, compressed: true)
        return Data(serialized.dropFirst())
    }
}

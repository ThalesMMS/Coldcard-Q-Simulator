import Foundation

public enum DescriptorChecksum {
    private static let inputCharset = Array("0123456789()[],'/*abcdefgh@:$%{}IJKLMNOPQRSTUVWXYZ&+-.;<=>?!^_|~ijklmnopqrstuvwxyzABCDEFGH`#\"\\ ")
    private static let checksumCharset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let inputMap: [Character: UInt64] = Dictionary(uniqueKeysWithValues: inputCharset.enumerated().map { ($1, UInt64($0)) })

    private static func polymod(_ c: UInt64, _ value: UInt64) -> UInt64 {
        let c0 = c >> 35
        var result = ((c & 0x7ffffffff) << 5) ^ value
        if c0 & 1 != 0 { result ^= 0xf5dee51989 }
        if c0 & 2 != 0 { result ^= 0xa9fdca3312 }
        if c0 & 4 != 0 { result ^= 0x1bab10e32d }
        if c0 & 8 != 0 { result ^= 0x3706b1677a }
        if c0 & 16 != 0 { result ^= 0x644d626ffd }
        return result
    }

    public static func checksum(_ descriptor: String) -> String? {
        var c: UInt64 = 1
        var cls: UInt64 = 0
        var classCount = 0
        for character in descriptor {
            guard let position = inputMap[character] else { return nil }
            c = polymod(c, position & 31)
            cls = cls * 3 + (position >> 5)
            classCount += 1
            if classCount == 3 {
                c = polymod(c, cls)
                cls = 0
                classCount = 0
            }
        }
        if classCount > 0 { c = polymod(c, cls) }
        for _ in 0..<8 { c = polymod(c, 0) }
        c ^= 1
        return String((0..<8).map { checksumCharset[Int((c >> UInt64(5 * (7 - $0))) & 31)] })
    }

    public static func append(to descriptor: String) -> String {
        guard !descriptor.contains("#"), let checksum = checksum(descriptor) else { return descriptor }
        return descriptor + "#" + checksum
    }
}

public enum WalletExportError: Error, Equatable {
    case unsupportedAddressType
}

/// Firmware `export_contents` signing path / address format (`export.py`).
public enum WalletExportSignatureFormat: Equatable, Sendable {
    case generic
    case electrum(AddressType)
    case wasabi
    case unchained
    case bitcoinCore
    case dumpSummary
    case descriptor(AddressType)
    case keyExpression(derive: String, addressType: AddressType)
}

public struct WalletExportSignatureContext: Equatable, Sendable {
    public let derive: String
    public let addressType: AddressType
}

public struct WalletAccountExport: Codable, Equatable, Sendable {
    public let name: String
    public let addressType: String
    public let derivation: String
    public let xpub: String
    public let descriptor: String
}

public struct GenericWalletExport: Codable, Equatable, Sendable {
    public let simulator: Bool
    public let chain: String
    public let xfp: String
    public let xpub: String
    public let accounts: [WalletAccountExport]
}

public enum WalletExporter {
    /// Q1 `version.get_mpy_version()[1]` for the firmware pin in `Docs/PROVENANCE.md`.
    public static let coldcardFirmwareVersion = "1.5.0Q"

    public static func descriptor(root: HDKey, type: AddressType, account: UInt32 = 0,
                                  branch: String = "<0;1>") throws -> String {
        guard type != .taproot else { throw WalletExportError.unsupportedAddressType }
        let accountPath = DerivationPath.account(type: type, network: root.network, account: account)
        let accountKey = try root.derived(path: accountPath).neutered()
        let originPath = accountPath.components.map { component in
            let raw = component & ~DerivationPath.hardened
            return "\(raw)h"
        }.joined(separator: "/")
        let origin = "[\(root.fingerprint.hexString.lowercased())/\(originPath)]"
        let key = "\(origin)\(accountKey.serializePublic())/\(branch)/*"
        let raw: String
        switch type {
        case .legacy: raw = "pkh(\(key))"
        case .wrappedSegwit: raw = "sh(wpkh(\(key)))"
        case .nativeSegwit: raw = "wpkh(\(key))"
        case .taproot: throw WalletExportError.unsupportedAddressType
        }
        return DescriptorChecksum.append(to: raw)
    }

    public static func descriptorExport(root: HDKey, type: AddressType, account: UInt32 = 0,
                                        combined: Bool) throws -> String {
        if combined { return try descriptor(root: root, type: type, account: account) }
        let external = try descriptor(root: root, type: type, account: account, branch: "0")
        let change = try descriptor(root: root, type: type, account: account, branch: "1")
        return "\(external)\n\(change)"
    }

    public static func keyExpression(root: HDKey, type: AddressType, account: UInt32 = 0) throws -> String {
        guard type != .taproot else { throw WalletExportError.unsupportedAddressType }
        let path = DerivationPath.account(type: type, network: root.network, account: account)
        return try keyExpression(root: root, path: path)
    }

    /// Firmware `make_key_expression_export`: `[xfp/derivation]xpub` for any derivation,
    /// including the BIP-48 multisig paths (m/48'/coin'/account'/1' and .../2').
    public static func keyExpression(root: HDKey, path: DerivationPath) throws -> String {
        let xpub = try root.derived(path: path).neutered().serializePublic()
        let origin = path.description.replacingOccurrences(of: "m/", with: "").replacingOccurrences(of: "'", with: "h")
        return "[\(root.fingerprint.hexString.lowercased())/\(origin)]\(xpub)"
    }

    public static func genericJSON(root: HDKey, account: UInt32 = 0) throws -> Data {
        try firmwareGenericJSON(root: root, account: account)
    }

    /// Firmware `generate_generic_export` (no Taproot). Used for Generic JSON and named wallets.
    public static func firmwareGenericJSON(root: HDKey, account: UInt32 = 0) throws -> Data {
        var object = OrderedJSONObject([
            ("chain", root.network == .mainnet ? "BTC" : root.network == .testnet ? "XTN" : "XRT"),
            ("xfp", root.fingerprint.hexString.uppercased()),
            ("account", Int(account)),
            ("xpub", try root.neutered().serializePublic())
        ])
        let singlesig: [(String, AddressType, String)] = [
            ("bip44", .legacy, "p2pkh"),
            ("bip49", .wrappedSegwit, "p2sh-p2wpkh"),
            ("bip84", .nativeSegwit, "p2wpkh")
        ]
        for (name, type, atype) in singlesig {
            let path = DerivationPath.account(type: type, network: root.network, account: account)
            let node = try root.derived(path: path).neutered()
            let xpub = node.serializePublic()
            let slip = node.serializePublic(addressType: type)
            let first = try BitcoinAddress.derive(root: root, type: type, account: account, index: 0).address
            var entry: [(String, Any)] = [
                ("name", atype),
                ("xfp", node.fingerprint.hexString.uppercased()),
                ("deriv", path.description.replacingOccurrences(of: "'", with: "h")),
                ("xpub", xpub),
                ("desc", try descriptor(root: root, type: type, account: account))
            ]
            if slip != xpub { entry.append(("_pub", slip)) }
            entry.append(("first", first))
            object.pairs.append((name, OrderedJSONObject(entry)))
        }
        let coin = root.network.coinType
        let masterXFP = root.fingerprintHex.lowercased()
        let bip48: [(String, String, String, Bool)] = [
            ("bip48_1", "p2sh-p2wsh", "m/48h/\(coin)h/\(account)h/1h", true),
            ("bip48_2", "p2wsh", "m/48h/\(coin)h/\(account)h/2h", false)
        ]
        for (name, atype, deriv, wrapped) in bip48 {
            let path = try DerivationPath(deriv.replacingOccurrences(of: "h", with: "'"))
            let node = try root.derived(path: path).neutered()
            let xpub = node.serializePublic()
            let keyExp = "[\(masterXFP)\(deriv.dropFirst())]\(xpub)/0/*"
            let descriptor = wrapped
                ? "sh(wsh(sortedmulti(M,\(keyExp),...)))"
                : "wsh(sortedmulti(M,\(keyExp),...))"
            object.pairs.append((name, OrderedJSONObject([
                ("name", atype),
                ("xfp", node.fingerprint.hexString.uppercased()),
                ("deriv", deriv),
                ("xpub", xpub),
                ("desc", descriptor)
            ])))
        }
        if account == 0 {
            let bip45 = try DerivationPath("m/45'")
            let node = try root.derived(path: bip45).neutered()
            let xpub = node.serializePublic()
            let xfp = root.fingerprintHex.lowercased()
            // Firmware multisig_descriptor_template (descriptor.py): sh(sortedmulti(M, key, ...)).
            let template = "sh(sortedmulti(M,[\(xfp)/45h]\(xpub)/0/*,...))"
            object.pairs.append(("bip45", OrderedJSONObject([
                ("name", "p2sh"),
                ("xfp", node.fingerprint.hexString.uppercased()),
                ("deriv", "m/45h"),
                ("xpub", xpub),
                ("desc", template)
            ])))
        }
        return try OrderedJSON.data(object, pretty: true)
    }

    public static func electrumWallet(root: HDKey, type: AddressType, account: UInt32 = 0,
                                      labelPrefix: String = "Coldcard Import") throws -> Data {
        guard type != .taproot else { throw WalletExportError.unsupportedAddressType }
        let path = DerivationPath.account(type: type, network: root.network, account: account)
        let xpub = try root.derived(path: path).neutered().serializePublic(addressType: type)
        var label = "\(labelPrefix) \(root.fingerprint.hexString.uppercased())"
        if account != 0 { label += " Acct#\(account)" }
        let object = OrderedJSONObject([
            ("seed_version", 17),
            ("use_encryption", false),
            ("wallet_type", "standard"),
            ("keystore", OrderedJSONObject([
                ("type", "hardware"),
                ("hw_type", "coldcard"),
                ("label", label),
                ("ckcc_xfp", Int(root.ckccXFP)),
                ("ckcc_xpub", try root.neutered().serializePublic()),
                ("derivation", path.description.replacingOccurrences(of: "'", with: "h")),
                ("xpub", xpub)
            ]))
        ])
        return try OrderedJSON.data(object, pretty: true)
    }

    public static func wasabiWallet(root: HDKey) throws -> Data {
        let path = DerivationPath.account(type: .nativeSegwit, network: root.network, account: 0)
        let xpub = try root.derived(path: path).neutered().serializePublic(asMainnet: true)
        let object = OrderedJSONObject([
            ("ColdCardFirmwareVersion", coldcardFirmwareVersion),
            ("MasterFingerprint", root.fingerprint.hexString.uppercased()),
            ("ExtPubKey", xpub)
        ])
        return try OrderedJSON.data(object, pretty: true)
    }

    public static func bitcoinCore(root: HDKey, account: UInt32 = 0) throws -> String {
        let xfp = root.fingerprint.hexString.uppercased()
        let external = try descriptor(root: root, type: .nativeSegwit, account: account, branch: "0")
        let change = try descriptor(root: root, type: .nativeSegwit, account: account, branch: "1")
        let importMulti: [OrderedJSONObject] = [
            OrderedJSONObject([
                ("desc", external), ("range", [0, 1000]), ("timestamp", "now"),
                ("internal", false), ("keypool", true), ("watchonly", true)
            ]),
            OrderedJSONObject([
                ("desc", change), ("range", [0, 1000]), ("timestamp", "now"),
                ("internal", true), ("keypool", true), ("watchonly", true)
            ])
        ]
        let importDescriptors: [OrderedJSONObject] = [
            OrderedJSONObject([
                ("desc", external), ("active", true), ("timestamp", "now"),
                ("internal", false), ("range", [0, 100])
            ]),
            OrderedJSONObject([
                ("desc", change), ("active", true), ("timestamp", "now"),
                ("internal", true), ("range", [0, 100])
            ])
        ]
        let impMulti = String(decoding: try OrderedJSON.data(importMulti, pretty: false), as: UTF8.self)
        let impDesc = String(decoding: try OrderedJSON.data(importDescriptors, pretty: false), as: UTF8.self)
        var examples: [String] = []
        for index: UInt32 in 0..<3 {
            let derived = try BitcoinAddress.derive(root: root, type: .nativeSegwit, account: account, index: index)
            examples.append("\(derived.path) => \(derived.address)")
        }
        return """
        # Bitcoin Core Wallet Import File

        https://github.com/Coldcard/firmware/blob/master/docs/bitcoin-core-usage.md

        ## For wallet with master key fingerprint: \(xfp)

        Wallet operates on blockchain: \(root.network.displayName)

        ## Bitcoin Core RPC

        The following command can be entered after opening Window -> Console
        in Bitcoin Core, or using bitcoin-cli:

        importdescriptors '\(impDesc)'

        > **NOTE** If your UTXO was created before generating `importdescriptors` command, you should adjust the value of `timestamp` before executing command in bitcoin core. 
          By default it is set to `now` meaning do not rescan the blockchain. If approximate time of UTXO creation is known - adjust `timestamp` from `now` to UNIX epoch time.
          0 can be specified to scan the entire blockchain. Alternatively `rescanblockchain` command can be used after executing importdescriptors command.

        ### Bitcoin Core before v0.21.0 

        This command can be used on older versions, but it is not as robust
        and "importdescriptors" should be prefered if possible:

        importmulti '\(impMulti)'

        ## Resulting Addresses (first 3)

        \(examples.joined(separator: "\n"))
        """
    }

    public static func dumpSummary(root: HDKey, wallets: [MultisigWalletConfig] = []) throws -> String {
        let xfp = root.fingerprint.hexString.uppercased()
        let xpub = try root.neutered().serializePublic()
        let coin = root.network.coinType
        var body = """
        # Coldcard Wallet Summary File
        ## For wallet with master key fingerprint: \(xfp)

        Wallet operates on blockchain: \(root.network.displayName)

        For BIP-44, this is coin_type '\(coin)', and internally we use
        symbol \(root.network == .mainnet ? "BTC" : root.network == .testnet ? "XTN" : "XRT") for this blockchain.

        ## IMPORTANT WARNING

        **NEVER** deposit to any address in this file unless you have a working
        wallet system that is ready to handle the funds at that address!

        ## Top-level, 'master' extended public key ('m/'):

        \(xpub)

        What follows are derived public keys and payment addresses, as may
        be needed for different systems.


        """
        let rows: [(String, AddressType)] = [
            ("BIP-44 / Electrum", .legacy),
            ("BIP-49 (P2WPKH-nested-in-P2SH)", .wrappedSegwit),
            ("BIP-84 (Native Segwit P2WPKH)", .nativeSegwit)
        ]
        for (name, type) in rows {
            let template = "m/\(type.purpose)h/\(coin)h/{account}h/{change}/{idx}"
            body += "## For \(name): \(template)\n\n"
            body += "First 5 receive addresses (account=0, change=0):\n\n"
            let hard = "m/\(type.purpose)h/\(coin)h/0h"
            let node = try root.derived(path: DerivationPath.account(type: type, network: root.network, account: 0)).neutered()
            body += "\(hard) => \(node.serializePublic())\n"
            if type != .legacy {
                body += "\(hard) => \(node.serializePublic(addressType: type))   ##SLIP-132##\n"
            }
            for index: UInt32 in 0..<5 {
                let derived = try BitcoinAddress.derive(root: root, type: type, account: 0, change: false, index: index)
                let path = "m/\(type.purpose)h/\(coin)h/0h/0/\(index)"
                body += "\(path) => \(derived.address)\n"
            }
            body += "\n\n"
        }
        if !wallets.isEmpty {
            body += "\n# Your Multisig Wallets\n\n"
            for wallet in wallets {
                body += wallet.coldcardExport(headerComment: nil)
                body += "\n---\n\n"
            }
        }
        return body
    }

    public static func unchained(root: HDKey, account: UInt32 = 0) throws -> Data {
        var object = OrderedJSONObject([
            ("xfp", root.fingerprint.hexString.uppercased()),
            ("account", Int(account))
        ])
        let p2wshP2shVersion: UInt32 = root.network == .mainnet ? 0x0295b43f : 0x024289ef
        let p2wshVersion: UInt32 = root.network == .mainnet ? 0x02aa7ed3 : 0x02575483
        // Firmware `chains.MS_STD_DERIVATIONS`: p2sh (BIP-45), p2sh_p2wsh, p2wsh — inside the loop.
        let paths: [(String, String, UInt32?)] = [
            ("p2sh", "m/45h", nil),
            ("p2sh_p2wsh", "m/48h/\(root.network.coinType)h/\(account)h/1h", p2wshP2shVersion),
            ("p2wsh", "m/48h/\(root.network.coinType)h/\(account)h/2h", p2wshVersion)
        ]
        for (name, deriv, version) in paths {
            if name == "p2sh" && account != 0 { continue }
            let path = try DerivationPath(deriv.replacingOccurrences(of: "h", with: "'"))
            let node = try root.derived(path: path).neutered()
            object.pairs.append(("\(name)_deriv", deriv))
            object.pairs.append((name, version.map { node.serializePublic(version: $0) } ?? node.serializePublic()))
        }
        return try OrderedJSON.data(object, pretty: true)
    }

    /// Firmware `generate_address_csv` for single-signer wallets (`address_explorer.py`).
    public static func addressSummaryCSV(addresses: [DerivedAddress]) -> String {
        var lines = ["\"Index\",\"Payment Address\",\"Derivation\""]
        for address in addresses {
            lines.append("\(address.index),\"\(address.address)\",\"\(address.path)\"")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func truncateAddress(_ address: String, qwerty: Bool = true) -> String {
        if qwerty {
            guard address.count > 24 else { return address }
            return String(address.prefix(12)) + "⋯" + String(address.suffix(12))
        }
        guard address.count > 12 else { return address }
        return String(address.prefix(6)) + "⋯" + String(address.suffix(6))
    }

    /// Firmware `export_by_qr`: single QR when `len(body) <= 2000` unless `force_bbqr`.
    public static let qrCharacterLimit = 2000

    public static func usesBBQr(body: String, forceBBQr: Bool = false) -> Bool {
        forceBBQr || body.count > qrCharacterLimit
    }

    /// Firmware `export_by_qr` type_code: `"J"` for JSON, `"U"` otherwise.
    public static func bbqrTypeCode(isJSON: Bool) -> String {
        isJSON ? "J" : "U"
    }

    /// Firmware `export_contents` SD success story (`export.py:90-92`).
    public static func fileWrittenStory(title: String, filename: String, signatureFilename: String) -> String {
        "\(title) file written:\n\n\(filename)\n\n\(title) signature file written:\n\n\(signatureFilename)"
    }

    public static func detachedSignatureContext(
        format: WalletExportSignatureFormat, coinType: UInt32, account: UInt32 = 0
    ) -> WalletExportSignatureContext {
        switch format {
        case .generic:
            return WalletExportSignatureContext(derive: "m/44h/\(coinType)h/\(account)h/0/0", addressType: .legacy)
        case .electrum(let type):
            return WalletExportSignatureContext(derive: "m/\(type.purpose)h/\(coinType)h/\(account)h/0/0", addressType: type)
        case .wasabi:
            return WalletExportSignatureContext(derive: "m/84h/\(coinType)h/0h/0/0", addressType: .nativeSegwit)
        case .unchained:
            return WalletExportSignatureContext(derive: "m/48h/\(coinType)h/\(account)h/2h/0/0", addressType: .legacy)
        case .bitcoinCore:
            return WalletExportSignatureContext(derive: "m/84h/\(coinType)h/\(account)h/0/0", addressType: .nativeSegwit)
        case .dumpSummary:
            return WalletExportSignatureContext(derive: "m/44h/\(coinType)h/0h/0/0", addressType: .legacy)
        case .descriptor(let type):
            return WalletExportSignatureContext(derive: "m/\(type.purpose)h/\(coinType)h/\(account)h/0/0", addressType: type)
        case .keyExpression(let derive, let type):
            let path = derive.hasSuffix("/0/0") ? derive : derive + "/0/0"
            return WalletExportSignatureContext(derive: path, addressType: type)
        }
    }
}

private struct OrderedJSONObject {
    var pairs: [(String, Any)]
    init(_ pairs: [(String, Any)] = []) { self.pairs = pairs }
}

private enum OrderedJSONError: Error {
    case unsupported(String)
}

/// Preserves firmware `OrderedDict` insertion order (`ujson.dumps`).
private enum OrderedJSON {
    static func data(_ value: Any, pretty: Bool) throws -> Data {
        let text = try write(value, pretty: pretty, depth: 0)
        guard let encoded = text.data(using: .utf8) else {
            throw OrderedJSONError.unsupported("utf8")
        }
        return encoded
    }

    private static func write(_ value: Any, pretty: Bool, depth: Int) throws -> String {
        if let object = value as? OrderedJSONObject {
            return try writeObject(object.pairs, pretty: pretty, depth: depth)
        }
        if let objects = value as? [OrderedJSONObject] {
            return try writeArray(objects.map { $0 as Any }, pretty: pretty, depth: depth)
        }
        if let ints = value as? [Int] {
            return try writeArray(ints.map { $0 as Any }, pretty: pretty, depth: depth)
        }
        if let array = value as? [Any] {
            return try writeArray(array, pretty: pretty, depth: depth)
        }
        if let string = value as? String {
            return try quote(string)
        }
        if type(of: value) == Bool.self, let flag = value as? Bool {
            return flag ? "true" : "false"
        }
        if type(of: value) == Int.self, let number = value as? Int {
            return String(number)
        }
        if let number = value as? UInt32 {
            return String(number)
        }
        throw OrderedJSONError.unsupported(String(describing: type(of: value)))
    }

    private static func writeObject(_ pairs: [(String, Any)], pretty: Bool, depth: Int) throws -> String {
        if pairs.isEmpty { return "{}" }
        if !pretty {
            var parts: [String] = []
            for (key, value) in pairs {
                parts.append("\(try quote(key)):\(try write(value, pretty: false, depth: depth + 1))")
            }
            return "{" + parts.joined(separator: ",") + "}"
        }
        let indent = String(repeating: "  ", count: depth)
        let inner = String(repeating: "  ", count: depth + 1)
        var lines = ["{"]
        for (index, pair) in pairs.enumerated() {
            let encoded = try write(pair.1, pretty: true, depth: depth + 1)
            let comma = index + 1 == pairs.count ? "" : ","
            lines.append("\(inner)\(try quote(pair.0)) : \(encoded)\(comma)")
        }
        lines.append("\(indent)}")
        return lines.joined(separator: "\n")
    }

    private static func writeArray(_ values: [Any], pretty: Bool, depth: Int) throws -> String {
        if values.isEmpty { return "[]" }
        if !pretty {
            let parts = try values.map { try write($0, pretty: false, depth: depth + 1) }
            return "[" + parts.joined(separator: ",") + "]"
        }
        let indent = String(repeating: "  ", count: depth)
        let inner = String(repeating: "  ", count: depth + 1)
        var lines = ["["]
        for (index, value) in values.enumerated() {
            let comma = index + 1 == values.count ? "" : ","
            lines.append("\(inner)\(try write(value, pretty: true, depth: depth + 1))\(comma)")
        }
        lines.append("\(indent)]")
        return lines.joined(separator: "\n")
    }

    private static func quote(_ string: String) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }
}

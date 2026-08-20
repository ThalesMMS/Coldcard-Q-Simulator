import Foundation

/// Firmware `nfc.share_push_tx` / `actions.PUSHTX_SUPPLIERS` / `nfc-pushtx.md`.
public enum PushTxError: Error, Equatable, Sendable {
    case tooBig
    case invalidURL(String)
    case notTransaction
    case notSeedWords
    case notAddressPath
    case notBIP21
    case invalidAddressFormat(String)
    case notMultisig
}

public struct PushTxSupplier: Equatable, Sendable {
    public let label: String
    public let url: String
}

public struct PushTxBIP21: Equatable, Sendable {
    public let address: String
    public let args: [String: String]
}

public struct PushTxShowAddress: Equatable, Sendable {
    public let path: String
    public let type: AddressType
}

public struct PushTxMultisigImport: Equatable, Sendable {
    public let name: String
    public let config: String
    public let summary: String
}

public enum PushTx {
    /// Firmware `nfc.MAX_NFC_SIZE`.
    public static let maxNFCSize = 8000

    public static let suppliers: [PushTxSupplier] = [
        PushTxSupplier(label: "coldcard.com", url: "https://coldcard.com/pushtx#"),
        PushTxSupplier(label: "mempool.space", url: "https://mempool.space/pushtx#")
    ]

    /// Firmware `stash.SEED_LEN_OPTS`.
    public static let ephemeralWordCounts: Set<Int> = [12, 18, 24]

    /// Firmware `pushtx_setup_menu`: `was.split("/")[2]` (Python keeps empty parts).
    public static func hostLabel(for url: String) -> String {
        let parts = url.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count > 2 {
            let host = String(parts[2])
            if !host.isEmpty { return host }
        }
        return url
    }

    /// Firmware `actions.pushtx_setup_menu` custom URL checks.
    public static func validateCustomURL(_ raw: String) -> String? {
        let nv = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if nv.isEmpty { return nil }
        if !(nv.hasPrefix("http://") || nv.hasPrefix("https://")) {
            return "Must start with http:// or https://."
        }
        if nv.count < 12 { return "Too short." }
        guard let last = nv.last, "#?&".contains(last) else {
            return "Final char must be # or ? or &."
        }
        return nil
    }

    public static func chooserIndex(current: String?) -> Int {
        let value = current?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty { return suppliers.count + 1 }
        if let index = suppliers.firstIndex(where: { $0.url == value }) { return index }
        return suppliers.count
    }

    /// Firmware `utils.b2a_base64url`.
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    /// Firmware `nfc.share_push_tx` URL appended to the user `ptxurl` prefix.
    public static func txnToPushTxURL(prefix: String, transaction: Data,
                                      sha256: Data? = nil,
                                      network: BitcoinNetwork) throws -> String {
        let digest = sha256 ?? SHA2.sha256(transaction)
        let checksum = Data(digest.suffix(8))
        var url = prefix
        url += "t=" + base64URL(transaction) + "&c=" + base64URL(checksum)
        if network.ticker != "BTC" {
            url += "&n=" + network.ticker
        }
        if url.utf8.count >= maxNFCSize { throw PushTxError.tooBig }
        return url
    }

    /// Firmware `nfc.push_tx_from_file` hex vs binary txn taster.
    public static func decodeTxnFile(_ raw: Data) throws -> Data {
        let stripped = Data(raw.trimmingASCII)
        guard stripped.count >= 8 else { throw PushTxError.notTransaction }
        if stripped[2..<min(8, stripped.count)] == Data("000000".utf8) {
            let hex = String(decoding: stripped, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return try Data(hex: hex)
        }
        if stripped.count >= 4, stripped[1..<4] == Data(repeating: 0, count: 3) {
            return stripped
        }
        throw PushTxError.notTransaction
    }

    /// Firmware `utils.txid_from_fname`.
    public static func txidFromFilename(_ name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        let hex = base.filter(\.isHexDigit)
        guard hex.count == 64, hex.lowercased() == base.lowercased() else { return nil }
        return hex.lowercased()
    }

    public static func parseEphemeralSeedWords(_ text: String) throws -> [String] {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
        guard ephemeralWordCounts.contains(words.count) else { throw PushTxError.notSeedWords }
        _ = try BIP39Mnemonic(words: words)
        return words
    }

    public static func parseAddressFormat(_ raw: String) throws -> AddressType {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "p2pkh": return .legacy
        case "p2wpkh": return .nativeSegwit
        case "p2sh-p2wpkh", "p2wpkh-p2sh": return .wrappedSegwit
        default:
            throw PushTxError.invalidAddressFormat(
                "Invalid address format: '\(raw)'\n\nChoose from p2pkh, p2wpkh, p2sh-p2wpkh."
            )
        }
    }

    /// Firmware `nfc.address_show_and_share` payload: path, optional format line.
    public static func parseShowAddress(_ text: String) throws -> PushTxShowAddress {
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        guard (1...2).contains(lines.count) else { throw PushTxError.notAddressPath }
        let path = lines[0]
        _ = try DerivationPath(path)
        if lines.count == 1 {
            return PushTxShowAddress(path: path, type: .legacy)
        }
        return PushTxShowAddress(path: path, type: try parseAddressFormat(lines[1]))
    }

    /// Firmware `utils.decode_bip21_text` (address branch only).
    public static func parseBIP21(_ raw: String) throws -> PushTxBIP21 {
        var got = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var args: [String: String] = [:]
        if let query = got.split(separator: "?", maxSplits: 1).dropFirst().first {
            got = String(got.split(separator: "?", maxSplits: 1)[0])
            for part in query.split(separator: "&") {
                let kv = part.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                args[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        if let colon = got.firstIndex(of: ":") {
            let proto = got[..<colon]
            guard proto.lowercased() == "bitcoin" else { throw PushTxError.notBIP21 }
            got = String(got[got.index(after: colon)...])
        }
        let addr = got.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addr.isEmpty else { throw PushTxError.notBIP21 }
        if addr.count >= 4, addr.dropFirst().prefix(3) == "pub" || addr.dropFirst().prefix(3) == "prv" {
            throw PushTxError.notBIP21
        }
        if (try? Base58.checkDecode(addr)) != nil { return PushTxBIP21(address: addr, args: args) }
        if (try? Bech32.decodeSegwit(addr)) != nil {
            return PushTxBIP21(address: addr.lowercased(), args: args)
        }
        throw PushTxError.notBIP21
    }

    public static func looksLikeMultisig(_ text: String) -> Bool {
        guard text.utf8.count >= 70 else { return false }
        return text.contains("pub") || text.contains("multi(")
    }

    /// Firmware `auth.maybe_enroll_xpub` JSON `desc` unwrap plus descriptor/text passthrough.
    public static func parseMultisigConfig(_ text: String) throws -> PushTxMultisigImport {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeMultisig(trimmed) else { throw PushTxError.notMultisig }
        var config = trimmed
        var name: String?
        if let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
           let desc = object["desc"] as? String, !desc.isEmpty {
            config = desc
            if let jsonName = object["name"] as? String, (2...40).contains(jsonName.count) {
                name = jsonName
            }
        }
        if name == nil {
            for line in config.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "name" {
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    if (1...20).contains(value.count) { name = value }
                }
            }
        }
        if name == nil, let checksum = config.split(separator: "#").last, checksum.count == 8,
           config.contains("#") {
            name = String(checksum)
        }
        let summary = config.count > 600 ? String(config.prefix(600)) + "…" : config
        return PushTxMultisigImport(name: name ?? "Imported", config: config, summary: summary)
    }
}

public enum AddressOwnershipError: Error, Equatable, Sendable {
    case invalidOnChain(String)
    case walletNotDefined(String)
    case noSuitableMultisig
    case notFound(candidates: Int, wallets: Int)
}

public enum AddressOwnershipHit: Equatable, Sendable {
    case singlesig(walletName: String, derived: DerivedAddress)
    case wif(storeIndex: Int)
    case multisig(walletName: String, path: String)
}

public enum AddressOwnership {
    /// Firmware `chains.BitcoinMainnet.name` / Testnet / Regtest.
    public static func firmwareChainName(_ network: BitcoinNetwork) -> String {
        switch network {
        case .mainnet: "Bitcoin"
        case .testnet: "Testnet"
        case .regtest: "Regtest"
        }
    }

    /// Singlesig scan used by firmware `ownership.search_ux` (first N receive/change indexes).
    public static func search(address: String, root: HDKey,
                              accounts: [UInt32] = [0],
                              perChain: UInt32 = 200) -> (walletName: String, derived: DerivedAddress)? {
        if case .singlesig(let name, let derived)? = try? searchUX(
            address: address, args: [:], root: root, wifKeys: [], wallets: [],
            accounts: accounts, perChain: perChain
        ) {
            return (name, derived)
        }
        return nil
    }

    /// Firmware `ownership.search` + `search_ux` (singlesig, imported multisig, WIF store).
    public static func searchUX(address: String, args: [String: String], root: HDKey,
                                wifKeys: [WIFStoreItem], wallets: [MultisigWalletConfig],
                                accounts: [UInt32] = [0],
                                perChain: UInt32 = 200) throws -> AddressOwnershipHit {
        let (normalized, format) = try validate(address, network: root.network)
        if let named = args["wallet"], !named.isEmpty {
            let matches = wallets.filter { $0.name == named }
            if matches.isEmpty { throw AddressOwnershipError.walletNotDefined(named) }
            if matches.count > 1 { throw AddressOwnershipError.walletNotDefined(named) }
            if let hit = searchMultisig(address: normalized, wallets: matches, network: root.network,
                                        perChain: perChain) {
                return hit.hit
            }
            throw AddressOwnershipError.notFound(candidates: Int(perChain) * 2, wallets: 1)
        }

        var candidates = 0
        var walletCount = 0
        let scriptOnly = format == .p2wsh || format == .p2shP2wsh
        if !scriptOnly {
            walletCount += 1
            if let singlesig = searchSinglesig(address: normalized, root: root, format: format,
                                               accounts: accounts, perChain: perChain,
                                               candidates: &candidates) {
                return singlesig
            }
        }

        let matchingWallets = wallets.filter { wallet in
            switch format {
            case .p2wpkh, .classic: return false
            case .p2wsh: return wallet.addressFormat == .p2wsh
            case .p2sh, .p2shP2wsh:
                return wallet.addressFormat == .p2sh || wallet.addressFormat == .p2shP2wsh
            }
        }
        if scriptOnly, matchingWallets.isEmpty {
            throw AddressOwnershipError.noSuitableMultisig
        }
        walletCount += matchingWallets.count
        if let hit = searchMultisig(address: normalized, wallets: matchingWallets, network: root.network,
                                    perChain: perChain) {
            candidates += hit.scanned
            return hit.hit
        }
        candidates += matchingWallets.count * Int(perChain) * 2

        if format != .p2wsh, let wif = searchWIF(address: normalized, keys: wifKeys,
                                                 network: root.network, format: format) {
            return wif
        }
        throw AddressOwnershipError.notFound(candidates: candidates, wallets: max(walletCount, 1))
    }

    public static func addressesMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        return lhs.lowercased() == rhs.lowercased()
    }

    /// Firmware `utils.validate_own_address` (witver 0 / matching chain prefixes).
    public static func validate(_ address: String, network: BitcoinNetwork) throws -> (String, AddressOwnershipFormat) {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = raw.lowercased()
        if lowered.hasPrefix("bc1") || lowered.hasPrefix("tb1") || lowered.hasPrefix("bcrt1") {
            if let decoded = try? Bech32.decodeSegwit(raw), decoded.version == 0,
               decoded.hrp == network.bech32HRP {
                if decoded.program.count == 20 { return (lowered, .p2wpkh) }
                if decoded.program.count == 32 { return (lowered, .p2wsh) }
            }
            throw AddressOwnershipError.invalidOnChain(firmwareChainName(network))
        }
        if let first = raw.first, "123mn".contains(first),
           let decoded = try? Base58.checkDecode(raw), decoded.count == 21 {
            let version = decoded[0]
            if version == network.p2pkhPrefix { return (raw, .classic) }
            if version == network.p2shPrefix { return (raw, .p2sh) }
        }
        throw AddressOwnershipError.invalidOnChain(firmwareChainName(network))
    }

    private static func searchSinglesig(address: String, root: HDKey, format: AddressOwnershipFormat,
                                        accounts: [UInt32], perChain: UInt32,
                                        candidates: inout Int) -> AddressOwnershipHit? {
        let types: [AddressType]
        switch format {
        case .p2wpkh: types = [.nativeSegwit]
        case .classic: types = [.legacy]
        case .p2sh: types = [.wrappedSegwit]
        case .p2wsh, .p2shP2wsh: return nil
        }
        let uniqueAccounts = Array(Set(accounts)).sorted()
        for type in types {
            for account in uniqueAccounts {
                for change in [false, true] {
                    for index in 0..<perChain {
                        candidates += 1
                        guard let derived = try? BitcoinAddress.derive(
                            root: root, type: type, account: account, change: change, index: index
                        ) else { continue }
                        if addressesMatch(derived.address, address) {
                            return .singlesig(walletName: type.displayName, derived: derived)
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func searchMultisig(address: String, wallets: [MultisigWalletConfig],
                                       network: BitcoinNetwork, perChain: UInt32)
    -> (hit: AddressOwnershipHit, scanned: Int)? {
        var scanned = 0
        for wallet in wallets {
            for change: UInt32 in [0, 1] {
                for index in 0..<perChain {
                    scanned += 1
                    guard let derived = try? wallet.derivedAddress(change: change, index: index,
                                                                  network: network) else { continue }
                    if addressesMatch(derived.address, address) {
                        let path = "m/\(change)/\(index)"
                        return (.multisig(walletName: wallet.name, path: path), scanned)
                    }
                }
            }
        }
        return nil
    }

    private static func searchWIF(address: String, keys: [WIFStoreItem], network: BitcoinNetwork,
                                  format: AddressOwnershipFormat) -> AddressOwnershipHit? {
        let types: [AddressType]
        switch format {
        case .p2wpkh: types = [.nativeSegwit]
        case .classic: types = [.legacy]
        case .p2sh: types = [.wrappedSegwit]
        case .p2wsh, .p2shP2wsh: return nil
        }
        for (index, item) in keys.enumerated() {
            guard let publicKey = item.publicKey else { continue }
            for type in types {
                guard let derived = try? BitcoinAddress.address(publicKey: publicKey, type: type,
                                                               network: network) else { continue }
                if addressesMatch(derived, address) {
                    return .wif(storeIndex: index + 1)
                }
            }
        }
        return nil
    }
}

public enum AddressOwnershipFormat: Equatable, Sendable {
    case classic
    case p2wpkh
    case p2sh
    case p2wsh
    case p2shP2wsh
}

private extension Data {
    var trimmingASCII: [UInt8] {
        var bytes = [UInt8](self)
        while bytes.first?.isASCIIWhitespace == true { bytes.removeFirst() }
        while bytes.last?.isASCIIWhitespace == true { bytes.removeLast() }
        return bytes
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool { self == 0x09 || self == 0x0a || self == 0x0d || self == 0x20 }
}

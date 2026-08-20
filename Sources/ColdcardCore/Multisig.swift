import Foundation

/// Firmware `public_constants.MAX_SIGNERS`.
public let maxMultisigSigners = 15
private let opCheckMultisig: UInt8 = 0xae

public enum MultisigError: Error, Equatable, Sendable {
    case invalidScript
    case invalidPolicy
    case badFormatLine
    case badDerivation
    case unableToParseXpub
    case wrongChain
    case needFingerprint
    case emptyDerivation
    case derivDepthMismatch
    case wrongPubkey
    case myKeyNotIncluded
    case myKeyIncludedMoreThanOnce
    case duplicateCosignerKey
    case isOurKey(String)
    case nameInvalid
    case unsortedNotAllowed
    case missingXpubs
    case wrongXpubCount
    case unsupportedDescriptor
    case wrongChecksum
    case missingValue(String)
    case duplicateXFP
    case xpubsDoNotMatchExisting
    case myXFPNotInvolved
    case invalidSignerCount
    case xpubMismatch
    case scriptValidation(String)
}

/// Firmware `TRUST_*` (`pms` setting). Default is verify if any wallet exists, else offer.
public enum MultisigTrustPolicy: Int, Codable, Equatable, Sendable {
    case verify = 0
    case offer = 1
    case psbt = 2

    public static func `default`(hasWallets: Bool) -> MultisigTrustPolicy {
        hasWallets ? .verify : .offer
    }

    public var chooserIndex: Int { rawValue }
}

/// Firmware `MultisigMenu.construct` / `make_ms_wallet_menu` / `AddressListMenu` labels (Q).
public enum MultisigMenuLayout {
    public static let noneSetupYet = "(none setup yet)"
    public static let importItem = "Import"
    public static let exportXPUB = "Export XPUB"
    public static let createAirgapped = "Create Airgapped"
    public static let trustPSBT = "Trust PSBT?"
    public static let skipChecks = "Skip Checks?"
    public static let fullAddressView = "Full Address View?"
    public static let unsortedMultisig = "Unsorted Multisig?"
    public static let viewDetails = "View Details"
    public static let rename = "Rename"
    public static let delete = "Delete"
    public static let coldcardExport = "Coldcard Export"
    public static let electrumWallet = "Electrum Wallet"
    public static let descriptors = "Descriptors"
    public static let viewDescriptor = "View Descriptor"
    public static let exportDescriptor = "Export"
    public static let bitcoinCore = "Bitcoin Core"
    public static let trustChoices = ["Verify Only", "Offer Import", "Trust PSBT"]
    public static let skipChoices = ["Normal", "Skip Checks"]
    public static let addressViewChoices = ["Partly Censor", "Show Full"]
    public static let unsortedChoices = ["Do Not Allow", "Allow"]

    public static func walletRow(_ wallet: MultisigWalletConfig) -> String {
        wallet.menuTitle
    }

    public static func quotedWalletName(_ name: String) -> String {
        "\"\(name)\""
    }

    public static func cccWalletRow(_ wallet: MultisigWalletConfig) -> String {
        "↳ \(wallet.requiredSignatures)/\(wallet.totalSigners): \(wallet.name)"
    }

    /// Firmware `MultisigMenu.construct` visible rows (ShortcutItem NFC/QR are hidden).
    public static func rootLabels(wallets: [MultisigWalletConfig]) -> [String] {
        var rows: [String] = []
        if wallets.isEmpty {
            rows.append(noneSetupYet)
        } else {
            rows.append(contentsOf: wallets.map(walletRow))
        }
        rows.append(contentsOf: [
            importItem, exportXPUB, createAirgapped, trustPSBT, skipChecks,
            fullAddressView, unsortedMultisig
        ])
        return rows
    }

    /// Firmware `make_ms_wallet_menu`.
    public static func walletActionLabels(name: String, bip67: Bool) -> [String] {
        var rows = [quotedWalletName(name), viewDetails, rename, delete]
        if bip67 {
            rows.append(contentsOf: [coldcardExport, electrumWallet])
        }
        rows.append(descriptors)
        return rows
    }

    /// Firmware `make_ms_wallet_descriptor_menu`.
    public static func descriptorLabels() -> [String] {
        [viewDescriptor, exportDescriptor, bitcoinCore]
    }

    /// Firmware `AddressListMenu.render` — MS names after Applications when account is 0.
    public static func addressExplorerWalletNames(account: UInt32,
                                                  wallets: [MultisigWalletConfig]) -> [String] {
        guard account == 0 else { return [] }
        return wallets.map(\.name)
    }

    /// Firmware `flow.qr_and_ms`: QR capability and at least one MS wallet.
    public static func qrAndMS(hasQR: Bool, walletCount: Int) -> Bool {
        hasQR && walletCount > 0
    }

    /// Firmware `ccc.CCCConfigMenu.construct` — wallets whose xfp_paths include Key C.
    public static func cccRelatedWallets(cccXFP: String?,
                                         wallets: [MultisigWalletConfig]) -> [MultisigWalletConfig] {
        let hex = (cccXFP ?? "").filter(\.isHexDigit).uppercased()
        guard !hex.isEmpty else { return [] }
        return wallets.filter { $0.includesFingerprint(hex) }
    }
}

public enum MultisigPSBTResolution: Equatable, Sendable {
    case matched(MultisigWalletConfig)
    case proposed(MultisigWalletConfig, needsApproval: Bool)
    case notMultisig
}

public enum MultisigAddressFormat: String, Codable, Equatable, Sendable, CaseIterable {
    case p2sh
    case p2wsh
    case p2shP2wsh = "p2sh-p2wsh"

    /// Firmware `FORMAT_NAMES` plus the obsolete `p2wsh-p2sh` alias.
    public static func parse(_ label: String) -> MultisigAddressFormat? {
        switch label.lowercased() {
        case "p2sh": .p2sh
        case "p2wsh": .p2wsh
        case "p2sh-p2wsh", "p2wsh-p2sh": .p2shP2wsh
        default: nil
        }
    }

    public var exportLabel: String { rawValue.uppercased() }

    /// JSON keys in firmware `ccxp-*.json` / `export.py` multisig XPUB dumps.
    public var xpubJSONKey: String {
        switch self {
        case .p2sh: "p2sh"
        case .p2shP2wsh: "p2sh_p2wsh"
        case .p2wsh: "p2wsh"
        }
    }

    /// Firmware `AF_*` numeric codes stored in wallet JSON (`ft`).
    public var firmwareCode: Int {
        switch self {
        case .p2sh: 0x08
        case .p2wsh: 0x0e
        case .p2shP2wsh: 0x1a
        }
    }

    public static func fromFirmwareCode(_ code: Int) -> MultisigAddressFormat {
        switch code {
        case 0x0e: .p2wsh
        case 0x1a: .p2shP2wsh
        default: .p2sh
        }
    }

    public func slip132PublicVersion(network: BitcoinNetwork) -> UInt32 {
        let main = network == .mainnet
        switch self {
        case .p2sh: return main ? 0x0488b21e : 0x043587cf
        case .p2shP2wsh: return main ? 0x0295b43f : 0x024289ef
        case .p2wsh: return main ? 0x02aa7ed3 : 0x02575483
        }
    }
}

public struct MultisigCosigner: Codable, Equatable, Sendable {
    public var fingerprint: String
    public var derivation: String
    public var xpub: String

    public init(fingerprint: String, derivation: String, xpub: String) {
        self.fingerprint = fingerprint.uppercased()
        self.derivation = derivation.replacingOccurrences(of: "'", with: "h")
        self.xpub = xpub
    }
}

public struct MultisigImportContext: Sendable {
    public var root: HDKey
    public var allowUnsorted: Bool
    public var disableChecks: Bool

    public init(root: HDKey, allowUnsorted: Bool, disableChecks: Bool) {
        self.root = root
        self.allowUnsorted = allowUnsorted
        self.disableChecks = disableChecks
    }

    public var myFingerprint: String { root.fingerprintHex }
    public var network: BitcoinNetwork { root.network }
}

public struct MultisigDerivedAddress: Equatable, Sendable {
    public var index: UInt32
    public var change: UInt32
    public var address: String
    public var paths: [String]
    public var script: Data
    public var scriptPubKeyHex: String
}

public struct MultisigSimilarity: Equatable, Sendable {
    public var isDuplicate: Bool
    public var differences: [String]
}

public struct MultisigWalletConfig: Codable, Equatable, Sendable {
    public var name: String
    public var requiredSignatures: Int
    public var totalSigners: Int
    public var addressFormat: MultisigAddressFormat
    public var chain: String
    public var bip67: Bool
    public var cosigners: [MultisigCosigner]

    public init(name: String, requiredSignatures: Int, totalSigners: Int,
                addressFormat: MultisigAddressFormat, chain: String, bip67: Bool,
                cosigners: [MultisigCosigner]) {
        self.name = name
        self.requiredSignatures = requiredSignatures
        self.totalSigners = totalSigners
        self.addressFormat = addressFormat
        self.chain = chain
        self.bip67 = bip67
        self.cosigners = cosigners
    }

    public var menuTitle: String { "\(requiredSignatures)/\(totalSigners): \(name)" }

    public static func fingerprintString(_ value: UInt32) -> String {
        var bytes = Data()
        bytes.appendUInt32LE(value)
        return bytes.hexString.uppercased()
    }

    public static func fingerprintValue(_ text: String) -> UInt32? {
        guard text.count == 8, let data = try? Data(hex: text), data.count == 4 else { return nil }
        return data.withUnsafeBytes { raw in
            raw.loadUnaligned(as: UInt32.self).littleEndian
        }
    }

    public static func uniqueName(_ base: String, existing: [String]) -> String {
        if !existing.contains(base) { return base }
        let prefix = base + " #"
        let nums = existing.compactMap { name -> Int? in
            guard name.hasPrefix(prefix) else { return nil }
            let rest = name.dropFirst(prefix.count)
            guard !rest.isEmpty, rest.allSatisfy(\.isNumber) else { return nil }
            return Int(rest)
        }
        return prefix + String((nums.max() ?? 1) + 1)
    }

    /// Firmware `import_multisig` file taster (`sh(` / `wsh(` / `pub`).
    public static func looksLikeImportable(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            line.contains("sh(") || line.contains("wsh(") || line.contains("pub")
        }
    }

    /// Firmware `auth.maybe_enroll_xpub`: unwrap `{ "desc", "name" }` then `from_file`.
    public static func importFile(_ config: String, nameHint: String? = nil,
                                  context: MultisigImportContext,
                                  existingNames: [String] = []) throws -> MultisigWalletConfig {
        let unwrapped = try unwrapEnrollment(config)
        let hint = unwrapped.nameHint ?? nameHint
        if MultisigDescriptorCodec.isDescriptor(unwrapped.text) {
            return try importDescriptor(unwrapped.text, nameHint: hint, context: context,
                                        existingNames: existingNames)
        }
        return try importSimpleText(unwrapped.text, nameHint: hint, context: context,
                                    existingNames: existingNames)
    }

    public func coldcardExport(headerComment: String?) -> String {
        var lines: [String] = []
        if let headerComment {
            lines.append("# Coldcard Multisig setup file (\(headerComment))\n#")
        }
        lines.append("Name: \(name)")
        lines.append("Policy: \(requiredSignatures) of \(totalSigners)")
        if addressFormat != .p2sh {
            lines.append("Format: \(addressFormat.exportLabel)")
        }
        var lastDeriv: String?
        for cosigner in cosigners {
            if lastDeriv != cosigner.derivation {
                lines.append("")
                lines.append("Derivation: \(cosigner.derivation)")
                lines.append("")
                lastDeriv = cosigner.derivation
            }
            lines.append("\(cosigner.fingerprint): \(cosigner.xpub)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public func descriptor(change: Bool = false, intExt: Bool = false) throws -> String {
        try MultisigDescriptorCodec.serialize(self, change: change, intExt: intExt)
    }

    public func prettyDescriptor() throws -> String {
        try MultisigDescriptorCodec.prettySerialize(self)
    }

    public func bitcoinCoreExport() throws -> String {
        let payload = try MultisigDescriptorCodec.bitcoinCoreJSON(self)
        return "importdescriptors '\(payload)'\n"
    }

    public func electrumExport(myFingerprint: String) throws -> String {
        var object: [String: Any] = [
            "seed_version": 17,
            "use_encryption": false,
            "wallet_type": "\(requiredSignatures)of\(totalSigners)"
        ]
        for (index, cosigner) in cosigners.enumerated() {
            let node = try HDKey(extendedKey: cosigner.xpub)
            let xpub = addressFormat == .p2sh
                ? cosigner.xpub
                : node.serializePublic(version: addressFormat.slip132PublicVersion(network: node.network))
            let xfp = Self.fingerprintValue(cosigner.fingerprint) ?? 0
            object["x\(index + 1)/"] = [
                "hw_type": "coldcard",
                "type": "hardware",
                "ckcc_xfp": xfp,
                "label": "Coldcard \(cosigner.fingerprint)",
                "derivation": cosigner.derivation,
                "xpub": xpub
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    public func makeFilename(prefix: String, suffix: String = "txt") -> String {
        "\(prefix)-\(name)".replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-") + ".\(suffix)"
    }

    public func publicKeys(change: UInt32, index: UInt32) throws -> [Data] {
        try cosigners.map { cosigner in
            let node = try HDKey(extendedKey: cosigner.xpub)
            return try node.derived(index: change).derived(index: index).publicKey
        }
    }

    public func redeemScript(change: UInt32, index: UInt32) throws -> Data {
        try MultisigScript.redeem(required: requiredSignatures,
                                  publicKeys: try publicKeys(change: change, index: index),
                                  bip67: bip67)
    }

    public func scriptPubKey(change: UInt32, index: UInt32) throws -> Data {
        let redeem = try redeemScript(change: change, index: index)
        return try MultisigScript.scriptPubKey(script: redeem, format: addressFormat)
    }

    public func derivedAddress(change: UInt32, index: UInt32, network: BitcoinNetwork) throws -> MultisigDerivedAddress {
        let redeem = try redeemScript(change: change, index: index)
        let address = try MultisigScript.address(script: redeem, format: addressFormat, network: network)
        let paths = cosigners.map { cosigner in
            "[\(cosigner.fingerprint)\(cosigner.derivation.replacingOccurrences(of: "m", with: ""))/\(change)/\(index)]"
        }
        let spk = try MultisigScript.scriptPubKey(script: redeem, format: addressFormat)
        return MultisigDerivedAddress(index: index, change: change, address: address, paths: paths,
                                      script: redeem, scriptPubKeyHex: spk.hexString)
    }

    public func ownsScript(_ outputScript: Data, change: UInt32, index: UInt32) -> Bool {
        (try? scriptPubKey(change: change, index: index)) == outputScript
    }

    public func ownsOutput(_ scriptPubKey: Data, derivation: PSBTDerivation) -> Bool {
        guard derivation.path.components.count >= 2 else { return false }
        let change = derivation.path.components[derivation.path.components.count - 2] & ~DerivationPath.hardened
        let index = derivation.path.components[derivation.path.components.count - 1] & ~DerivationPath.hardened
        return ownsScript(scriptPubKey, change: change, index: index)
    }

    /// Firmware `MultisigWallet.validate_script` (`shared/multisig.py`).
    public func validateScript(_ script: Data, derivations: [PSBTDerivation]) throws {
        let parsed: (requiredSignatures: Int, totalSigners: Int, publicKeys: [Data])
        do {
            parsed = try MultisigScript.disassemble(script)
        } catch {
            throw MultisigError.scriptValidation("wrong M/N in script")
        }
        guard parsed.requiredSignatures == requiredSignatures,
              parsed.totalSigners == totalSigners else {
            throw MultisigError.scriptValidation("wrong M/N in script")
        }
        var byPubkey: [Data: PSBTDerivation] = [:]
        for derivation in derivations {
            byPubkey[derivation.publicKey] = derivation
        }
        var used = Set<Int>()
        var previous: Data?
        for (pkOrder, pubkey) in parsed.publicKeys.enumerated() {
            guard let derivation = byPubkey[pubkey] else {
                throw MultisigError.scriptValidation("unexpected pubkey")
            }
            let xfp = derivation.masterFingerprint.hexString.uppercased()
            var matched = false
            for (xpIdx, cosigner) in cosigners.enumerated() where !used.contains(xpIdx) {
                if cosigner.fingerprint != xfp { continue }
                if !bip67, xpIdx != pkOrder {
                    throw MultisigError.scriptValidation("script key order")
                }
                guard let node = try? HDKey(extendedKey: cosigner.xpub) else { continue }
                let path = derivation.path.components
                let depth = Int(node.depth)
                guard (0...path.count).contains(depth) else { continue }
                var current = node
                var ok = true
                for component in path.dropFirst(depth) {
                    if component & DerivationPath.hardened != 0 {
                        throw MultisigError.scriptValidation("hard deriv")
                    }
                    guard let next = try? current.derived(index: component) else {
                        ok = false
                        break
                    }
                    current = next
                }
                guard ok, current.publicKey == pubkey else { continue }
                used.insert(xpIdx)
                matched = true
                break
            }
            if !matched {
                throw MultisigError.scriptValidation("pk#\(pkOrder + 1) wrong")
            }
            if bip67, let previous {
                guard previous.lexicographicallyPrecedes(pubkey) else {
                    throw MultisigError.scriptValidation("BIP-67 violation")
                }
            }
            previous = pubkey
        }
        if used.count != totalSigners {
            throw MultisigError.scriptValidation("not all keys used: \(used.count) of \(totalSigners)")
        }
    }

    public func matchingSubpaths(_ xfpPaths: [[UInt32]]) -> Bool {
        guard xfpPaths.count == cosigners.count else { return false }
        let ours: [UInt32: [UInt32]] = Dictionary(uniqueKeysWithValues: cosigners.compactMap { cosigner in
            guard let xfp = Self.fingerprintValue(cosigner.fingerprint),
                  let path = try? DerivationPath(cosigner.derivation) else { return nil }
            return (xfp, [xfp] + path.components)
        })
        guard ours.count == cosigners.count else { return false }
        for path in xfpPaths {
            guard let xfp = path.first, let prefix = ours[xfp], path.count >= prefix.count,
                  Array(prefix) == Array(path.prefix(prefix.count)) else { return false }
        }
        return true
    }

    public func similarity(to existing: [MultisigWalletConfig]) -> MultisigSimilarity {
        let paths = xfpPaths()
        if let match = existing.first(where: {
            $0.requiredSignatures == requiredSignatures
                && $0.totalSigners == totalSigners
                && $0.addressFormat == addressFormat
                && $0.matchingSubpaths(paths)
        }) {
            let sortedSelf = cosigners.map(\.xpub).sorted()
            let sortedOther = match.cosigners.map(\.xpub).sorted()
            if sortedSelf != sortedOther {
                return MultisigSimilarity(isDuplicate: false, differences: ["xpubs"])
            }
            if bip67 != match.bip67 {
                return MultisigSimilarity(isDuplicate: true, differences: ["BIP-67 clash"])
            }
            if !bip67, cosigners.map(\.xpub) != match.cosigners.map(\.xpub) {
                return MultisigSimilarity(isDuplicate: true, differences: ["key order"])
            }
            if existing.contains(where: { $0.name == name && $0 != match }) {
                return MultisigSimilarity(isDuplicate: true, differences: ["Name already exists."])
            }
            return MultisigSimilarity(isDuplicate: true, differences: ["All details are the same as existing!"])
        }
        if existing.contains(where: { $0.name == name }) {
            return MultisigSimilarity(isDuplicate: true, differences: ["Name already exists."])
        }
        let similar = existing.filter { $0.matchingSubpaths(paths) }
        if similar.isEmpty { return MultisigSimilarity(isDuplicate: false, differences: []) }
        var diffs = Set<String>()
        for other in similar {
            if other.requiredSignatures != requiredSignatures { diffs.insert("M differs") }
            if other.addressFormat != addressFormat { diffs.insert("address type") }
            if other.name == name { diffs.insert("same name") }
            for (index, cosigner) in other.cosigners.enumerated() where index < cosigners.count {
                if cosigner.derivation != cosigners[index].derivation { diffs.insert("path") }
                if cosigner.fingerprint != cosigners[index].fingerprint { diffs.insert("XFPs") }
                if cosigner.xpub != cosigners[index].xpub { diffs.insert("xpubs") }
            }
        }
        return MultisigSimilarity(isDuplicate: false, differences: diffs.sorted())
    }

    public func policyExplanation() -> String {
        let m = requiredSignatures
        let n = totalSigners
        if m == 1, n == 1 { return "The one signer must approve spends." }
        if m == n { return "All \(n) co-signers must approve spends." }
        if m == 1 { return "Any signature from \(n) co-signers will approve spends." }
        return "\(m) signatures, from \(n) possible co-signers, will be required to approve spends."
    }

    public func detailText(verbose: Bool) -> String {
        var msg = ""
        if verbose {
            if !bip67 {
                msg += "WARNING: BIP-67 disabled! Unsorted multisig - order of keys in descriptor/backup is crucial.\n\n"
            }
            msg += "Policy: \(requiredSignatures) of \(totalSigners)\n"
            msg += "Blockchain: \(chain)\n"
            msg += "Addresses: \(addressFormat.exportLabel)\n\n"
        }
        for (index, cosigner) in cosigners.enumerated() {
            if index > 0 { msg += "\n---===---\n\n" }
            msg += "\(cosigner.fingerprint):\n  \(cosigner.derivation)\n\n\(cosigner.xpub)\n"
            if addressFormat != .p2sh, let node = try? HDKey(extendedKey: cosigner.xpub) {
                let slip = node.serializePublic(version: addressFormat.slip132PublicVersion(network: node.network))
                msg += "\nSLIP-132 equiv:\n\(slip)\n"
            }
        }
        return msg
    }

    public func confirmImportStory(existing: [MultisigWalletConfig]) -> (body: String, isDuplicate: Bool) {
        let similar = similarity(to: existing)
        var story: String
        if similar.isDuplicate {
            story = "Duplicate wallet."
            if let first = similar.differences.first { story += " " + first }
        } else if !similar.differences.isEmpty {
            story = "WARNING: This new wallet is similar to an existing wallet, but will NOT replace it. Consider deleting previous wallet first. Differences: "
                + similar.differences.joined(separator: ", ")
        } else {
            story = "Create new multisig wallet?"
        }
        if !bip67, !similar.isDuplicate {
            story += "\nWARNING: BIP-67 disabled! Unsorted multisig - order of keys in descriptor/backup is crucial"
        }
        let derivs = Array(Set(cosigners.map(\.derivation))).sorted()
        let dsum = derivs.count == 1 ? derivs[0] : "Varies (\(derivs.count))"
        story += """


        Wallet Name:
          \(name)

        Policy: \(requiredSignatures) of \(totalSigners)

        \(policyExplanation())

        Addresses:
          \(addressFormat.exportLabel)

        Derivation:
          \(dsum)

        Press (1) to see extended public keys, 
        """
        if similar.isDuplicate {
            story += "CANCEL to cancel"
        } else {
            story += "ENTER to approve, CANCEL to cancel."
        }
        return (story, similar.isDuplicate)
    }

    public static func censorAddress(_ address: String, showFull: Bool) -> String {
        if showFull { return address }
        guard address.count > 15 else { return address }
        let prefix = address.prefix(12)
        let suffix = address.dropFirst(15)
        return String(prefix) + "___" + String(suffix)
    }

    public func includesFingerprint(_ hex: String) -> Bool {
        let target = hex.filter(\.isHexDigit).uppercased()
        guard !target.isEmpty else { return false }
        return cosigners.contains { $0.fingerprint.filter(\.isHexDigit).uppercased() == target }
    }

    public func xfpPaths() -> [[UInt32]] {
        cosigners.compactMap { cosigner in
            guard let xfp = Self.fingerprintValue(cosigner.fingerprint),
                  let path = try? DerivationPath(cosigner.derivation) else { return nil }
            return [xfp] + path.components
        }
    }

    /// Firmware `guess_multisig_addr_fmt`.
    public static func guessAddressFormat(witnessScript: Data?, redeemScript: Data?) -> MultisigAddressFormat {
        if witnessScript != nil && redeemScript == nil { return .p2wsh }
        if witnessScript != nil && redeemScript != nil { return .p2shP2wsh }
        return .p2sh
    }

    public static func findMatch(wallets: [MultisigWalletConfig], requiredSignatures: Int, totalSigners: Int,
                                 xfpPaths: [[UInt32]], addressFormat: MultisigAddressFormat? = nil) -> MultisigWalletConfig? {
        wallets.first(where: {
            $0.requiredSignatures == requiredSignatures
                && $0.totalSigners == totalSigners
                && (addressFormat == nil || $0.addressFormat == addressFormat)
                && $0.matchingSubpaths(xfpPaths)
        })
    }

    public static func findCandidates(wallets: [MultisigWalletConfig], xfpPaths: [[UInt32]]) -> [MultisigWalletConfig] {
        wallets.filter { $0.matchingSubpaths(xfpPaths) }
    }

    /// Firmware `add_own_xpub` (BIP-48 for segwit formats, BIP-45 for P2SH).
    public static func ownCosigner(root: HDKey, account: UInt32,
                                   format: MultisigAddressFormat) throws -> MultisigCosigner {
        let coin = root.network.coinType
        let deriv: String
        switch format {
        case .p2sh: deriv = "m/45h"
        case .p2shP2wsh: deriv = "m/48h/\(coin)h/\(account)h/1h"
        case .p2wsh: deriv = "m/48h/\(coin)h/\(account)h/2h"
        }
        let node = try root.derived(path: DerivationPath(deriv)).neutered()
        return MultisigCosigner(fingerprint: root.fingerprintHex, derivation: deriv, xpub: node.serializePublic())
    }

    /// Firmware `ondevice_multisig_create` / `ms_coordinator_file` over `ccxp-*.json` (or BIP-380 lines).
    public static func createFromXPUBExports(
        files: [String],
        addressFormat: MultisigAddressFormat,
        requiredSignatures: Int,
        includeOwnIfMissing: Bool,
        account: UInt32 = 0,
        existingNames: [String] = [],
        context: MultisigImportContext
    ) throws -> MultisigWalletConfig {
        let key = addressFormat.xpubJSONKey
        var collected: [MultisigCosigner] = []
        var seen = Set<String>()
        var mine = 0
        for file in files {
            guard let object = MultisigXPUBExport.parseCoordinatorExport(file, format: addressFormat),
                  let cosigner = try? MultisigXPUBExport.cosigner(from: object, addressKey: key) else { continue }
            let token = "\(cosigner.fingerprint)|\(cosigner.derivation)|\(cosigner.xpub)"
            if seen.contains(token) { continue }
            seen.insert(token)
            var bucket: [MultisigCosigner] = []
            if try considerXpub(cosigner.fingerprint, cosigner.xpub, cosigner.derivation,
                                context: context, into: &bucket) {
                mine += 1
            }
            collected.append(contentsOf: bucket)
        }
        if includeOwnIfMissing, mine == 0 {
            let own = try ownCosigner(root: context.root, account: account, format: addressFormat)
            var bucket: [MultisigCosigner] = []
            if try considerXpub(own.fingerprint, own.xpub, own.derivation, context: context, into: &bucket) {
                mine += 1
            }
            collected.append(contentsOf: bucket)
        }
        let total = collected.count
        guard (2...maxMultisigSigners).contains(total) else { throw MultisigError.invalidSignerCount }
        guard (1...total).contains(requiredSignatures) else { throw MultisigError.invalidPolicy }
        let name = uniqueName("CC-\(requiredSignatures)-of-\(total)", existing: existingNames)
        return try finishImport(name: name, format: addressFormat, xpubs: collected, mine: mine,
                                m: requiredSignatures, n: total, bip67: true, context: context,
                                existingNames: existingNames)
    }

    /// Firmware `MultisigWallet.serialize` NVRAM object.
    public func firmwareStorageObject() -> [Any] {
        var opts: [String: Any] = [:]
        if addressFormat != .p2sh { opts["ft"] = addressFormat.firmwareCode }
        if chain != "BTC" { opts["ch"] = chain }
        let derivSet = Array(Set(cosigners.map(\.derivation))).sorted()
        let xp: [[Any]]
        if derivSet.count == 1 {
            opts["pp"] = derivSet[0]
            xp = cosigners.map { [Int(Self.fingerprintValue($0.fingerprint) ?? 0), $0.xpub] }
        } else {
            opts["d"] = derivSet
            xp = cosigners.map {
                [Int(Self.fingerprintValue($0.fingerprint) ?? 0),
                 derivSet.firstIndex(of: $0.derivation) ?? 0, $0.xpub]
            }
        }
        var result: [Any] = [name, [requiredSignatures, totalSigners], xp, opts]
        if !bip67 { result.append(0) }
        return result
    }

    public func firmwareStorageJSON() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: firmwareStorageObject(),
                                              options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// Firmware `MultisigWallet.deserialize`.
    public static func fromFirmwareStorage(_ object: Any) throws -> MultisigWalletConfig {
        guard var vals = object as? [Any], (4...5).contains(vals.count) else {
            throw MultisigError.badFormatLine
        }
        var bip67 = true
        if vals.count == 5 {
            bip67 = (jsonInt(vals[4]) ?? 1) != 0
            vals = Array(vals.prefix(4))
        }
        guard let name = vals[0] as? String,
              let policy = vals[1] as? [Any], policy.count == 2,
              let required = jsonInt(policy[0]), let total = jsonInt(policy[1]),
              let xp = vals[2] as? [Any],
              let opts = vals[3] as? [String: Any] else { throw MultisigError.badFormatLine }
        let format = MultisigAddressFormat.fromFirmwareCode(jsonInt(opts["ft"] as Any? ?? 0x08) ?? 0x08)
        let chain = opts["ch"] as? String ?? "BTC"
        var derivs: [String] = []
        if let prefix = opts["pp"] as? String {
            derivs = [prefix.replacingOccurrences(of: "'", with: "h")]
        } else if let listed = opts["d"] as? [Any] {
            derivs = listed.compactMap { ($0 as? String)?.replacingOccurrences(of: "'", with: "h") }
        }
        var cosigners: [MultisigCosigner] = []
        for item in xp {
            guard let row = item as? [Any], row.count >= 2,
                  let xfpInt = jsonInt(row[0]), let xpub = row.last as? String else {
                throw MultisigError.unableToParseXpub
            }
            let deriv: String
            if row.count == 2 {
                deriv = derivs.first ?? "m"
            } else if let index = jsonInt(row[1]), derivs.indices.contains(index) {
                deriv = derivs[index]
            } else if let path = row[1] as? String {
                deriv = path.replacingOccurrences(of: "'", with: "h")
            } else {
                throw MultisigError.emptyDerivation
            }
            let node = try HDKey(extendedKey: xpub)
            cosigners.append(MultisigCosigner(fingerprint: fingerprintString(UInt32(truncatingIfNeeded: xfpInt)),
                                              derivation: deriv, xpub: node.serializePublic()))
        }
        guard Set(cosigners.map(\.fingerprint)).count == cosigners.count else {
            throw MultisigError.duplicateXFP
        }
        return MultisigWalletConfig(name: name, requiredSignatures: required, totalSigners: total,
                                    addressFormat: format, chain: chain, bip67: bip67, cosigners: cosigners)
    }

    public static func fromFirmwareStorageJSON(_ json: String) throws -> MultisigWalletConfig {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try fromFirmwareStorage(object)
    }

    /// Firmware `import_from_psbt`.
    public static func importFromPSBT(
        addressFormat: MultisigAddressFormat,
        requiredSignatures: Int,
        totalSigners: Int,
        xpubs: [PSBTGlobalXpub],
        context: MultisigImportContext,
        trust: MultisigTrustPolicy,
        existingNames: [String] = []
    ) throws -> (wallet: MultisigWalletConfig, needsApproval: Bool) {
        if trust == .verify { throw MultisigError.xpubsDoNotMatchExisting }
        guard xpubs.count == totalSigners,
              1 <= requiredSignatures, requiredSignatures <= totalSigners,
              totalSigners <= maxMultisigSigners else { throw MultisigError.invalidPolicy }
        var collected: [MultisigCosigner] = []
        var mine = 0
        for item in xpubs {
            let node = try HDKey.parseExtendedKeyData(item.extendedKey, network: context.network)
            if try considerXpub(item.fingerprint.hexString.uppercased(), node.serializePublic(),
                                item.path.description, context: context, into: &collected) {
                mine += 1
            }
        }
        let name = uniqueName("PSBT-\(requiredSignatures)-of-\(totalSigners)", existing: existingNames)
        let wallet = try finishImport(name: name, format: addressFormat, xpubs: collected, mine: mine,
                                      m: requiredSignatures, n: totalSigners, bip67: true,
                                      context: context, existingNames: existingNames)
        return (wallet, trust != .psbt)
    }

    /// Firmware `handle_xpubs` match-or-enroll.
    public static func resolvePSBT(
        xpubs: [PSBTGlobalXpub],
        addressFormat: MultisigAddressFormat?,
        requiredSignatures: Int?,
        totalSigners: Int?,
        wallets: [MultisigWalletConfig],
        context: MultisigImportContext,
        trust: MultisigTrustPolicy,
        existingNames: [String] = []
    ) throws -> MultisigPSBTResolution {
        guard xpubs.contains(where: {
            $0.fingerprint.hexString.uppercased() == context.myFingerprint
        }) else { throw MultisigError.myXFPNotInvolved }
        let xfpPaths: [[UInt32]] = xpubs.map { item in
            let xfp = fingerprintValue(item.fingerprint.hexString.uppercased()) ?? 0
            return [xfp] + item.path.components
        }
        let candidates = findCandidates(wallets: wallets, xfpPaths: xfpPaths)
        if candidates.count == 1 {
            try candidates[0].validatePSBTXpubs(xpubs, disableChecks: context.disableChecks)
            return .matched(candidates[0])
        }
        guard let format = addressFormat, let required = requiredSignatures, let total = totalSigners else {
            return .notMultisig
        }
        if let match = candidates.first(where: {
            $0.requiredSignatures == required && $0.totalSigners == total
        }) {
            try match.validatePSBTXpubs(xpubs, disableChecks: context.disableChecks)
            return .matched(match)
        }
        let imported = try importFromPSBT(addressFormat: format, requiredSignatures: required,
                                          totalSigners: total, xpubs: xpubs, context: context,
                                          trust: trust, existingNames: existingNames)
        return .proposed(imported.wallet, needsApproval: imported.needsApproval)
    }

    /// Firmware `validate_psbt_xpubs`.
    public func validatePSBTXpubs(_ xpubs: [PSBTGlobalXpub], disableChecks: Bool) throws {
        guard xpubs.count == totalSigners else { throw MultisigError.wrongXpubCount }
        if disableChecks { return }
        for item in xpubs {
            let xfp = item.fingerprint.hexString.uppercased()
            let node = try HDKey.parseExtendedKeyData(item.extendedKey)
            let deriv = item.path.description
            guard let match = cosigners.first(where: { $0.fingerprint == xfp }) else {
                throw MultisigError.xpubMismatch
            }
            guard match.derivation == deriv else { throw MultisigError.badDerivation }
            guard match.xpub == node.serializePublic() else { throw MultisigError.xpubMismatch }
        }
    }
}

public enum MultisigScript {
    public static func redeem(required: Int, publicKeys: [Data], bip67: Bool) throws -> Data {
        let n = publicKeys.count
        guard 1 <= required, required <= n, n <= maxMultisigSigners else { throw MultisigError.invalidPolicy }
        var keys = publicKeys.map { Data([0x21]) + $0 }
        if bip67 { keys.sort { $0.lexicographicallyPrecedes($1) } }
        var script = Data([UInt8(80 + required)])
        keys.forEach { script.append($0) }
        script.append(UInt8(80 + n))
        script.append(opCheckMultisig)
        return script
    }

    public static func disassemble(_ script: Data) throws -> (requiredSignatures: Int, totalSigners: Int, publicKeys: [Data]) {
        guard script.last == opCheckMultisig, script.count >= 3 else { throw MultisigError.invalidScript }
        let m = Int(script[script.startIndex]) - 80
        let n = Int(script[script.index(script.endIndex, offsetBy: -2)]) - 80
        guard 1 <= m, m <= n, n <= maxMultisigSigners else { throw MultisigError.invalidScript }
        guard script.count == 1 + (n * 34) + 1 + 1 else { throw MultisigError.invalidScript }
        var keys: [Data] = []
        var offset = 1
        for _ in 0..<n {
            guard script[script.index(script.startIndex, offsetBy: offset)] == 0x21 else { throw MultisigError.invalidScript }
            let start = script.index(script.startIndex, offsetBy: offset + 1)
            let end = script.index(start, offsetBy: 33)
            let key = script[start..<end]
            guard key.first == 0x02 || key.first == 0x03 else { throw MultisigError.invalidScript }
            keys.append(Data(key))
            offset += 34
        }
        return (m, n, keys)
    }

    public static func scriptPubKey(script: Data, format: MultisigAddressFormat) throws -> Data {
        switch format {
        case .p2sh:
            return Data([0xa9, 0x14]) + BitcoinHash.hash160(script) + Data([0x87])
        case .p2wsh:
            return Data([0x00, 0x20]) + SHA2.sha256(script)
        case .p2shP2wsh:
            let witness = Data([0x00, 0x20]) + SHA2.sha256(script)
            return Data([0xa9, 0x14]) + BitcoinHash.hash160(witness) + Data([0x87])
        }
    }

    public static func address(script: Data, format: MultisigAddressFormat, network: BitcoinNetwork) throws -> String {
        switch format {
        case .p2sh:
            return Base58.checkEncode(version: Data([network.p2shPrefix]), payload: BitcoinHash.hash160(script))
        case .p2wsh:
            return try Bech32.encodeSegwit(hrp: network.bech32HRP, version: 0, program: SHA2.sha256(script))
        case .p2shP2wsh:
            let witness = Data([0x00, 0x20]) + SHA2.sha256(script)
            return Base58.checkEncode(version: Data([network.p2shPrefix]), payload: BitcoinHash.hash160(witness))
        }
    }
}

public enum MultisigXPUBExport {
    public static func json(root: HDKey, account: UInt32) throws -> String {
        let xfp = root.fingerprintHex
        let coin = root.network.coinType
        var lines = ["{"]
        let rows: [(String, String, MultisigAddressFormat)] = [
            ("p2sh", "m/45h", .p2sh),
            ("p2sh_p2wsh", "m/48h/\(coin)h/\(account)h/1h", .p2shP2wsh),
            ("p2wsh", "m/48h/\(coin)h/\(account)h/2h", .p2wsh)
        ]
        for (name, deriv, format) in rows {
            if format == .p2sh && account != 0 { continue }
            let path = try DerivationPath(deriv.replacingOccurrences(of: "h", with: "'"))
            let node = try root.derived(path: path).neutered()
            let xp = format == .p2sh
                ? node.serializePublic()
                : node.serializePublic(version: format.slip132PublicVersion(network: root.network))
            let xpub = node.serializePublic()
            lines.append("  \"\(name)_deriv\": \"\(deriv)\",")
            lines.append("  \"\(name)\": \"\(xp)\",")
            if let template = descriptorTemplate(xpub: xpub, path: deriv, xfp: xfp, format: format) {
                lines.append("  \"\(name)_desc\": \"\(template)\",")
            }
        }
        lines.append("  \"account\": \"\(account)\",")
        lines.append("  \"xfp\": \"\(xfp)\"")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func cosigner(from object: [String: Any], addressKey: String) throws -> MultisigCosigner {
        guard let xfp = object["xfp"] as? String else { throw MultisigError.missingValue("xfp") }
        let derivKey = addressKey + "_deriv"
        guard let deriv = object[derivKey] as? String else { throw MultisigError.missingValue(derivKey) }
        guard let xpub = object[addressKey] as? String else { throw MultisigError.missingValue(addressKey) }
        let path = try cleanupDerivation(deriv)
        let node = try HDKey(extendedKey: xpub)
        return MultisigCosigner(fingerprint: xfp, derivation: path, xpub: node.serializePublic())
    }

    /// Firmware `ms_coordinator_file` / `extract_cosigner`: ccxp JSON or first BIP-380 key expression.
    public static func parseCoordinatorExport(_ text: String, format: MultisigAddressFormat) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
           object["xfp"] != nil {
            return object
        }
        for line in trimmed.split(whereSeparator: \.isNewline).map(String.init) {
            if let extracted = extractBIP380(line, format: format) { return extracted }
        }
        return extractBIP380(trimmed, format: format)
    }

    public static func extractBIP380(_ data: String, format: MultisigAddressFormat) -> [String: Any]? {
        guard data.contains("pub"),
              let originStart = data.firstIndex(of: "["),
              let originEnd = data.firstIndex(of: "]"),
              originStart < originEnd else { return nil }
        let origin = data[data.index(after: originStart)..<originEnd]
        let parts = origin.split(separator: "/")
        guard let xfp = parts.first, xfp.count == 8 else { return nil }
        let rest = String(data[data.index(after: originEnd)...])
        guard rest.hasPrefix("xpub") || rest.hasPrefix("tpub") else { return nil }
        let key = String(rest.prefix(112))
        let deriv = parts.count > 1 ? "m/" + parts.dropFirst().joined(separator: "/") : "m"
        return ["xfp": String(xfp), format.xpubJSONKey: key, format.xpubJSONKey + "_deriv": deriv]
    }

    public static func descriptorTemplate(xpub: String, path: String, xfp: String, format: MultisigAddressFormat) -> String? {
        let keyExp = "[\(xfp.lowercased())\(path.replacingOccurrences(of: "m", with: ""))]\(xpub)/0/*"
        switch format {
        case .p2shP2wsh: return "sh(wsh(sortedmulti(M,\(keyExp),...)))"
        case .p2wsh: return "wsh(sortedmulti(M,\(keyExp),...))"
        case .p2sh: return "sh(sortedmulti(M,\(keyExp),...))"
        }
    }
}

enum MultisigDescriptorCodec {
    static func isDescriptor(_ text: String) -> Bool {
        let compact = compactDescriptor(text)
        for prefix in ["pk(", "pkh(", "wpkh(", "tr(", "addr(", "raw(", "rawtr(", "combo(",
                       "sh(", "wsh(", "multi(", "sortedmulti(", "multi_a(", "sortedmulti_a("] {
            if compact.hasPrefix(prefix) || compact.contains(prefix) { return true }
        }
        return false
    }

    static func serialize(_ wallet: MultisigWalletConfig, change: Bool, intExt: Bool) throws -> String {
        let innerType = wallet.bip67 ? "sortedmulti" : "multi"
        let keys = wallet.cosigners.map { serializeKey($0, change: change, intExt: intExt) }.joined(separator: ",")
        let inner = "\(wallet.requiredSignatures),\(keys)"
        let raw: String
        switch wallet.addressFormat {
        case .p2sh: raw = "sh(\(innerType)(\(inner)))"
        case .p2wsh: raw = "wsh(\(innerType)(\(inner)))"
        case .p2shP2wsh: raw = "sh(wsh(\(innerType)(\(inner))))"
        }
        return DescriptorChecksum.append(to: raw)
    }

    static func prettySerialize(_ wallet: MultisigWalletConfig) throws -> String {
        let innerType = wallet.bip67 ? "sortedmulti" : "multi"
        var header = "# Coldcard descriptor export\n"
        if wallet.bip67 {
            header += "# order of keys in the descriptor does not matter, will be sorted before creating script (BIP-67)\n"
        } else {
            header += "# !!! DANGER: order of keys in descriptor MUST be preserved. Correct order of keys is required to compose valid redeem/witness script.\n"
        }
        let wrapper: String
        switch wallet.addressFormat {
        case .p2sh:
            header += "# bare multisig - p2sh\n"
            wrapper = "sh(\(innerType)(\n%s\n))"
        case .p2wsh:
            header += "# native segwit - p2wsh\n"
            wrapper = "wsh(\(innerType)(\n%s\n))"
        case .p2shP2wsh:
            header += "# wrapped segwit - p2sh-p2wsh\n"
            wrapper = "sh(wsh(\(innerType)(\n%s\n)))"
        }
        let threshold = wallet.requiredSignatures == wallet.totalSigners
            ? "requires all participants to sign" : "threshold"
        var inner = "\t# \(wallet.requiredSignatures) of \(wallet.totalSigners) (\(threshold))\n"
        inner += "\t\(wallet.requiredSignatures),\n"
        let keys = wallet.cosigners.map { serializeKey($0, change: false, intExt: false) }
        for (index, key) in keys.enumerated() {
            inner += "\t" + key
            if index + 1 != keys.count { inner += ",\n" }
        }
        let checksum = try serialize(wallet, change: false, intExt: false).split(separator: "#").last.map(String.init) ?? ""
        return header + String(format: wrapper, inner) + "#" + checksum
    }

    static func bitcoinCoreJSON(_ wallet: MultisigWalletConfig) throws -> String {
        var items: [[String: Any]] = []
        for change in [false, true] {
            items.append([
                "desc": try serialize(wallet, change: change, intExt: false),
                "active": true,
                "timestamp": "now",
                "internal": change,
                "range": [0, 100]
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(_ text: String) throws -> (format: MultisigAddressFormat, m: Int, n: Int, keys: [MultisigCosigner], sorted: Bool) {
        let compact = compactDescriptor(text)
        let (desc, _) = try checksumSplit(compact)
        let sorted = desc.contains("sortedmulti(")
        let token = sorted ? "sortedmulti(" : "multi("
        let format: MultisigAddressFormat
        var inner: String
        if desc.hasPrefix("sh(wsh(\(token)") {
            format = .p2shP2wsh
            inner = String(desc.dropFirst("sh(wsh(\(token)".count))
            inner = inner.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
        } else if desc.hasPrefix("wsh(\(token)") {
            format = .p2wsh
            inner = String(desc.dropFirst("wsh(\(token)".count))
            inner = inner.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
        } else if desc.hasPrefix("sh(\(token)") {
            format = .p2sh
            inner = String(desc.dropFirst("sh(\(token)".count))
            inner = inner.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
        } else {
            throw MultisigError.unsupportedDescriptor
        }
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let m = Int(parts.first ?? ""), parts.count > 1 else { throw MultisigError.invalidPolicy }
        let keys = try parts.dropFirst().map(parseKey)
        if m > keys.count { throw MultisigError.invalidPolicy }
        return (format, m, keys.count, keys, sorted)
    }

    private static func parseKey(_ raw: String) throws -> MultisigCosigner {
        guard raw.first == "[", let close = raw.firstIndex(of: "]") else {
            throw MultisigError.unsupportedDescriptor
        }
        let origin = String(raw[raw.index(after: raw.startIndex)..<close])
        let rest = String(raw[raw.index(after: close)...])
        guard origin.count >= 8 else { throw MultisigError.needFingerprint }
        let xfp = String(origin.prefix(8))
        let originPath = "m" + origin.dropFirst(8)
        let slash = rest.split(separator: "/")
        guard slash.count > 1, slash.last == "*",
              ["0", "<0;1>", "<1;0>"].contains(slash.dropLast().last.map(String.init) ?? ""),
              slash.dropFirst().allSatisfy({ !$0.contains("h") && !$0.contains("'") }) else {
            throw MultisigError.badDerivation
        }
        let xpub = String(slash[0])
        guard xpub.hasPrefix("tpub") || xpub.hasPrefix("xpub") else { throw MultisigError.unableToParseXpub }
        return MultisigCosigner(fingerprint: xfp, derivation: originPath.replacingOccurrences(of: "'", with: "h"), xpub: xpub)
    }

    private static func serializeKey(_ cosigner: MultisigCosigner, change: Bool, intExt: Bool) -> String {
        var deriv = cosigner.derivation
        if deriv.hasPrefix("m") { deriv.removeFirst() }
        else if !deriv.hasPrefix("/") { deriv = "/" + deriv }
        var key = "[\(cosigner.fingerprint.lowercased())\(deriv)]\(cosigner.xpub)"
        if intExt {
            key += "/<0;1>/*"
        } else {
            key += change ? "/1/*" : "/0/*"
        }
        return key.replacingOccurrences(of: "'", with: "h")
    }

    private static func compactDescriptor(_ string: String) -> String {
        string.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .joined()
    }

    private static func checksumSplit(_ desc: String) throws -> (String, String?) {
        let parts = desc.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 { return (desc, nil) }
        guard parts.count == 2 else { throw MultisigError.wrongChecksum }
        let raw = parts[0]
        let got = parts[1]
        guard let expected = DescriptorChecksum.checksum(raw), expected == got else {
            throw MultisigError.wrongChecksum
        }
        return (raw, got)
    }
}

private extension MultisigWalletConfig {
    static func unwrapEnrollment(_ config: String) throws -> (text: String, nameHint: String?) {
        let trimmed = config.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" else { return (config, nil) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
            return (config, nil)
        }
        guard let desc = object["desc"] as? String, !desc.isEmpty else {
            throw MultisigError.missingValue("desc")
        }
        var hint: String?
        if let name = object["name"] as? String {
            guard (2...40).contains(name.count) else { throw MultisigError.nameInvalid }
            hint = name
        }
        return (desc, hint)
    }

    static func jsonInt(_ value: Any) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? Int64 { return Int(number) }
        if let number = value as? UInt64 { return Int(number) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    static func importDescriptor(_ config: String, nameHint: String?,
                                 context: MultisigImportContext,
                                 existingNames: [String] = []) throws -> MultisigWalletConfig {
        let parsed = try MultisigDescriptorCodec.parse(config)
        if !parsed.sorted && !context.allowUnsorted { throw MultisigError.unsortedNotAllowed }
        var xpubs: [MultisigCosigner] = []
        var mine = 0
        for key in parsed.keys {
            if try considerXpub(key.fingerprint, key.xpub, key.derivation, context: context, into: &xpubs) {
                mine += 1
            }
        }
        return try finishImport(name: nameHint, format: parsed.format, xpubs: xpubs, mine: mine,
                                m: parsed.m, n: parsed.n, bip67: parsed.sorted, context: context,
                                existingNames: existingNames)
    }

    static func importSimpleText(_ config: String, nameHint: String?,
                                 context: MultisigImportContext,
                                 existingNames: [String] = []) throws -> MultisigWalletConfig {
        var mine = 0
        var m = -1
        var n = -1
        var deriv: String?
        var name: String?
        var xpubs: [MultisigCosigner] = []
        var format = MultisigAddressFormat.p2sh
        for raw in config.split(whereSeparator: \.isNewline).map(String.init) {
            var line = raw
            if let comment = line.firstIndex(of: "#") {
                let after = line[line.index(after: comment)...]
                if comment == line.startIndex { continue }
                if after.first?.isNumber != true {
                    line = String(line[..<comment])
                }
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let label: String
            let value: String
            if let colon = line.firstIndex(of: ":") {
                label = String(line[..<colon]).lowercased()
                value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            } else if line.contains("pub") {
                label = "00000000"
                value = line
            } else {
                continue
            }
            if label == "name" {
                name = value
            } else if label == "policy" {
                let digits = value.split { !$0.isNumber }.compactMap { Int($0) }
                guard digits.count >= 2 else { throw MultisigError.invalidPolicy }
                m = digits[0]
                n = digits[1]
                guard 1 <= m, m <= n, n <= maxMultisigSigners else { throw MultisigError.invalidPolicy }
            } else if label == "derivation" {
                guard !value.isEmpty else { throw MultisigError.badDerivation }
                deriv = try cleanupDerivation(value)
            } else if label == "format" {
                guard let parsed = MultisigAddressFormat.parse(value) else { throw MultisigError.badFormatLine }
                format = parsed
            } else if label.count == 8 {
                let xfp = label.uppercased()
                if try considerXpub(xfp, value, deriv, context: context, into: &xpubs) {
                    mine += 1
                }
            }
        }
        return try finishImport(name: name ?? nameHint, format: format, xpubs: xpubs, mine: mine,
                                m: m, n: n, bip67: true, context: context, existingNames: existingNames)
    }

    static func finishImport(name: String?, format: MultisigAddressFormat, xpubs: [MultisigCosigner],
                             mine: Int, m: Int, n: Int, bip67: Bool,
                             context: MultisigImportContext,
                             existingNames: [String] = []) throws -> MultisigWalletConfig {
        guard !xpubs.isEmpty else { throw MultisigError.missingXpubs }
        var policyM = m
        var policyN = n
        if policyM == -1 && policyN == -1 {
            policyM = xpubs.count
            policyN = xpubs.count
        }
        let resolvedName: String
        if let name, !name.isEmpty {
            resolvedName = try asciiName(name)
        } else {
            resolvedName = uniqueName("\(policyM)-of-\(policyN)", existing: existingNames)
        }
        guard 1 <= policyM, policyM <= policyN, policyN <= maxMultisigSigners else { throw MultisigError.invalidPolicy }
        guard policyN == xpubs.count else { throw MultisigError.wrongXpubCount }
        guard Set(xpubs.map(\.fingerprint)).count == xpubs.count else { throw MultisigError.duplicateXFP }
        guard mine != 0 else { throw MultisigError.myKeyNotIncluded }
        guard mine == 1 else { throw MultisigError.myKeyIncludedMoreThanOnce }
        try checkUniqueCosigners(xpubs, context: context)
        return MultisigWalletConfig(
            name: resolvedName,
            requiredSignatures: policyM,
            totalSigners: policyN,
            addressFormat: format,
            chain: context.network.ticker,
            bip67: bip67,
            cosigners: xpubs
        )
    }

    static func considerXpub(_ xfpText: String, _ xpub: String, _ deriv: String?,
                             context: MultisigImportContext, into xpubs: inout [MultisigCosigner]) throws -> Bool {
        let node: HDKey
        do {
            node = try HDKey(extendedKey: xpub)
        } catch {
            throw MultisigError.unableToParseXpub
        }
        if node.privateKey != nil { throw MultisigError.unableToParseXpub }
        let expect = context.network
        if expect == .regtest {
            guard node.network == .testnet || node.network == .regtest else { throw MultisigError.wrongChain }
        } else {
            guard node.network == expect else { throw MultisigError.wrongChain }
        }
        var xfp = xfpText.uppercased()
        if xfp == "00000000" { xfp = "" }
        if node.depth == 1 {
            let parent = node.parentFingerprint.hexString.uppercased()
            if xfp.isEmpty {
                xfp = parent
            } else if !context.disableChecks, xfp != parent {
                throw MultisigError.wrongPubkey
            }
        }
        if xfp.isEmpty { throw MultisigError.needFingerprint }
        var derivation = deriv
        if node.depth == 1 {
            let guess = DerivationPath([node.childNumber]).description
            if let derivation {
                if !context.disableChecks, derivation != guess { throw MultisigError.wrongPubkey }
            } else {
                derivation = guess
            }
        }
        guard let derivation, !derivation.isEmpty else { throw MultisigError.emptyDerivation }
        guard derivation.hasPrefix("m") else { throw MultisigError.emptyDerivation }
        if !context.disableChecks {
            let path = try DerivationPath(derivation)
            guard path.components.count == Int(node.depth) else { throw MultisigError.derivDepthMismatch }
            if xfp == context.myFingerprint {
                let check = try context.root.derived(path: path)
                guard check.publicKey == node.publicKey else { throw MultisigError.wrongPubkey }
            }
        }
        xpubs.append(MultisigCosigner(fingerprint: xfp, derivation: derivation, xpub: node.serializePublic()))
        return xfp == context.myFingerprint
    }

    static func checkUniqueCosigners(_ xpubs: [MultisigCosigner], context: MultisigImportContext) throws {
        let pubkeys = try xpubs.map { try HDKey(extendedKey: $0.xpub).publicKey }
        guard Set(pubkeys).count == pubkeys.count else { throw MultisigError.duplicateCosignerKey }
        for (cosigner, pubkey) in zip(xpubs, pubkeys) where cosigner.fingerprint != context.myFingerprint {
            let path = try DerivationPath(cosigner.derivation)
            if (try? context.root.derived(path: path).publicKey) == pubkey {
                throw MultisigError.isOurKey(cosigner.fingerprint)
            }
        }
    }

    static func asciiName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(trimmed.count),
              trimmed.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 && $0.value != 127 }) else {
            throw MultisigError.nameInvalid
        }
        return trimmed
    }
}

func cleanupDerivation(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "'", with: "h")
    _ = try DerivationPath(trimmed)
    return trimmed.hasPrefix("m") ? trimmed : "m/" + trimmed
}

import Foundation

public enum PSBTError: Error, Equatable {
    case invalidMagic
    case malformed
    case missingUnsignedTransaction
    case unsupportedVersion(UInt32)
    case mapCountMismatch
    case invalidUTXO
    case noMatchingKey
    case unsupportedInput
    case transactionMismatch
    case dangerousSighash(UInt32)
    case duplicateInput
    case pathTooDeep
    case tooComplex
    case checksumMismatch
    case oversize(fileBytes: Int?, maximum: Int)
}

public struct PSBTEntry: Equatable, Sendable {
    public var key: Data
    public var value: Data
    public init(key: Data, value: Data) { self.key = key; self.value = value }
    public var type: UInt8 { key.first ?? 0xff }
    public var keyData: Data { Data(key.dropFirst()) }
}

public struct PSBTMap: Equatable, Sendable {
    public var entries: [PSBTEntry]
    public init(entries: [PSBTEntry] = []) { self.entries = entries }

    public func first(type: UInt8) -> PSBTEntry? { entries.first { $0.type == type } }
    public func all(type: UInt8) -> [PSBTEntry] { entries.filter { $0.type == type } }

    public mutating func set(type: UInt8, keyData: Data = Data(), value: Data) {
        let key = Data([type]) + keyData
        if let index = entries.firstIndex(where: { $0.key == key }) { entries[index].value = value }
        else { entries.append(PSBTEntry(key: key, value: value)) }
    }

    fileprivate func serialize() -> Data {
        var result = Data()
        for entry in entries {
            result.appendVarInt(UInt64(entry.key.count)); result.append(entry.key)
            result.appendVarInt(UInt64(entry.value.count)); result.append(entry.value)
        }
        result.append(0)
        return result
    }

    fileprivate static func parse(reader: inout ByteReader) throws -> PSBTMap {
        var entries: [PSBTEntry] = []
        var seen = Set<Data>()
        while true {
            let keyLength = try reader.readVarInt()
            if keyLength == 0 { break }
            if keyLength > UInt64(PSBT.maxTransactionLength) { throw PSBTError.tooComplex }
            guard keyLength <= UInt64(Int.max) else { throw PSBTError.malformed }
            let key = try reader.read(Int(keyLength))
            guard !key.isEmpty, !seen.contains(key) else { throw PSBTError.malformed }
            seen.insert(key)
            let value: Data
            do {
                value = try reader.readVarData(max: PSBT.maxTransactionLength)
            } catch ByteEncodingError.invalidVarInt {
                throw PSBTError.tooComplex
            }
            entries.append(PSBTEntry(key: key, value: value))
        }
        return PSBTMap(entries: entries)
    }
}

public struct PSBTDerivation: Equatable, Sendable {
    public let publicKey: Data
    public let masterFingerprint: Data
    public let path: DerivationPath

    public init(publicKey: Data, masterFingerprint: Data, path: DerivationPath) {
        self.publicKey = publicKey
        self.masterFingerprint = masterFingerprint
        self.path = path
    }

    public init(entry: PSBTEntry) throws {
        guard [UInt8(0x02), 0x06].contains(entry.type), entry.keyData.count == 33, entry.value.count >= 4,
              (entry.value.count - 4).isMultiple(of: 4) else { throw PSBTError.malformed }
        // Firmware `parse_subpaths`: `(vl//4) <= MAX_PATH_DEPTH` counts XFP plus path indexes.
        guard (entry.value.count / 4) <= DerivationPath.maxDepth else { throw PSBTError.pathTooDeep }
        publicKey = entry.keyData
        masterFingerprint = Data(entry.value.prefix(4))
        var reader = ByteReader(Data(entry.value.dropFirst(4)))
        var components: [UInt32] = []
        while !reader.isAtEnd { components.append(try reader.readUInt32LE()) }
        path = DerivationPath(components)
    }

    public var encodedValue: Data {
        var value = masterFingerprint
        for component in path.components { value.appendUInt32LE(component) }
        return value
    }
}

public struct PSBTExplorerOurKey: Equatable, Sendable {
    public let xfpPath: String
    public let publicKeyHex: String
}

public struct PSBTInputReview: Equatable, Sendable, Identifiable {
    public let index: Int
    public let value: UInt64?
    public let address: String?
    public let path: String?
    public let signable: Bool
    public let warning: String?
    public let previousOutpoint: String
    public let scriptPubKeyHex: String?
    public let sequence: UInt32
    public let alreadySigned: Bool
    public let fullySigned: Bool
    public let signedCosignerXFPs: [String]
    public let multisigMN: String?
    public let sighashNote: String?
    public let ourKeys: [PSBTExplorerOurKey]
    public let hasUTXO: Bool
    public let addressFormat: String?
    public let relativeTimelockNote: String?
    public let ourPublicKeyHex: String?
    public var id: Int { index }
}

public struct PSBTOutputReview: Equatable, Sendable, Identifiable {
    public let index: Int
    public let value: UInt64
    public let address: String
    public let scriptPubKey: Data
    public let isChange: Bool
    public let path: String?
    public var id: Int { index }
}

public struct PSBTReview: Equatable, Sendable {
    public let transactionID: String
    public let inputs: [PSBTInputReview]
    public let outputs: [PSBTOutputReview]
    public let totalInput: UInt64?
    public let totalOutput: UInt64
    public let fee: UInt64?
    public let feeRate: Double?
    public let feePercentOfOutputs: Double?
    public var warnings: [String]
    public let locktimeNotes: [String]
    public let lockTime: UInt32
    public let signableInputCount: Int
    public let feeExceedsLimit: Bool
    public let sighashBlocked: Bool
    /// Firmware `FatalPSBTIssue`: when set, the transaction must be refused before review.
    public let fatalIssue: String?
    /// Firmware `por322_msg` (PSBT global type 0x09).
    public let bip322Message: String?
    public let bip322IsProofOfReserves: Bool
    public let bip322Challenge: String?
    /// Name of a stored multisig wallet that matches this PSBT, if any.
    public let multisigWalletName: String?
    /// Firmware `OutptValueCache` after `consider_inputs` / `verify_amount`.
    public let utxoHistory: OutptValueCache
}

/// Firmware `ApproveTransaction.output_summary_text` visible lists (`MAX_VISIBLE_OUTPUTS=10`, `MAX_VISIBLE_CHANGE=20`).
public struct PSBTApprovalOutputSummary: Equatable, Sendable {
    public let foreign: [PSBTOutputReview]
    public let change: [PSBTOutputReview]
    public let changeTotal: UInt64
    public let hiddenForeignCount: Int
    public let hiddenForeignValue: UInt64
    public let hiddenChangeCount: Int
    public let hiddenChangeValue: UInt64
    /// Firmware `consolidation_tx`: every output is change (`num_change_outputs == num_outputs`).
    public let isConsolidation: Bool
}

public struct PSBTInputSigningResult: Equatable, Sendable, Identifiable {
    public let index: Int
    public let signed: Bool
    public let message: String
    public var id: Int { index }
}

public struct PSBTSigningResult: Equatable, Sendable {
    public let data: Data
    public let signedInputCount: Int
    public let inputs: [PSBTInputSigningResult]
    public let psbt: PSBT
}

public struct PSBTGlobalXpub: Equatable, Sendable {
    public let fingerprint: Data
    public let path: DerivationPath
    public let extendedKey: Data
}

public struct PSBT: Equatable, Sendable {
    public static let magic = Data([0x70, 0x73, 0x62, 0x74, 0xff])
    /// Firmware `actions.is_psbt`: skip `*-signed*`, taste binary / hex / base64 magic.
    public static func isPSBTTaste(filename: String, data: Data) -> Bool {
        if filename.lowercased().contains("-signed") { return false }
        let taste = data.prefix(10)
        if taste.starts(with: magic) { return true }
        if taste.count >= 10, String(decoding: taste, as: UTF8.self).lowercased() == "70736274ff" {
            return true
        }
        if taste.count >= 6, String(decoding: taste.prefix(6), as: UTF8.self) == "cHNidP" {
            return true
        }
        return false
    }

    /// Q `version.MAX_TXN_LEN` (`MAX_TXN_LEN_MK4`).
    public static let maxTransactionLength = 2 * 1024 * 1024
    /// Firmware `psbt.py` `NO_KEY_ERR`.
    public static let noKeyError = "None of the keys involved in this transaction belong to this Coldcard"
    /// Firmware `auth.py` `ApproveTransaction.failure` / parse stories.
    public static let parseFailedStory = "PSBT parse failed"
    public static let invalidStory = "Invalid PSBT"
    public static let tooComplexStory = "Transaction is too complex"
    public static let checksumMismatchStory = "PSBT checksum mismatch"
    public static let transactionModifiedStory = "Transaction modified"

    /// Firmware `auth.py` oversize story (`title='Sorry'`).
    public static func oversizeStory(fileBytes: Int?, maximum: Int = maxTransactionLength) -> (title: String, body: String) {
        let size = fileBytes.map { " (\($0) bytes)" } ?? ""
        return ("Sorry", "That transaction file is too big\(size). Maximum supported is \(maximum) bytes.")
    }

    /// Firmware `FraudulentChangeOutput` stories use title `Change Fraud`.
    public static func failureTitle(for issue: String) -> String {
        issue.hasPrefix("Output#") ? "Change Fraud" : "Failure"
    }

    public static func parseFailureStory(for error: Error) -> String {
        approvalFailure(for: error).body
    }

    public static func approvalFailure(for error: Error) -> (title: String, body: String) {
        guard let psbt = error as? PSBTError else {
            return ("Failure", parseFailedStory)
        }
        switch psbt {
        case .oversize(let fileBytes, let maximum):
            return oversizeStory(fileBytes: fileBytes, maximum: maximum)
        case .tooComplex:
            return ("Failure", tooComplexStory)
        case .checksumMismatch:
            return ("Failure", checksumMismatchStory)
        case .unsupportedVersion, .missingUnsignedTransaction, .pathTooDeep:
            // Firmware `psbt.validate()` assertions become `Invalid PSBT` (`auth.py`).
            return ("Failure", invalidStory)
        default:
            return ("Failure", parseFailedStory)
        }
    }

    public static func bytesWereModified(originalSHA: Data, current: Data) -> Bool {
        SHA2.sha256(current) != originalSHA
    }

    /// Taste encoding, enforce `MAX_TXN_LEN`, optional USB-style SHA, then parse.
    public static func ingest(_ data: Data, expectedSHA: Data? = nil) throws -> (psbt: PSBT, sha: Data) {
        let binary: Data
        let encoded: Bool
        if data.starts(with: magic) {
            encoded = false
            binary = data
        } else {
            encoded = true
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased().hasPrefix("70736274ff"), let decoded = try? Data(hex: text) {
                binary = decoded
            } else if let decoded = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]),
                      decoded.starts(with: magic) {
                binary = decoded
            } else {
                throw PSBTError.malformed
            }
        }
        if !encoded, data.count > maxTransactionLength {
            throw PSBTError.oversize(fileBytes: data.count, maximum: maxTransactionLength)
        }
        if encoded, binary.count > maxTransactionLength {
            throw PSBTError.oversize(fileBytes: nil, maximum: maxTransactionLength)
        }
        let sha = SHA2.sha256(binary)
        if let expectedSHA, expectedSHA != sha {
            throw PSBTError.checksumMismatch
        }
        return (try PSBT(data: binary), sha)
    }

    /// BIP-174/BIP-370 PSBT version. Firmware `validate`: `assert self.version in (0, 2)`.
    public var psbtVersion: UInt32
    public var global: PSBTMap
    public var inputs: [PSBTMap]
    public var outputs: [PSBTMap]
    public var unsignedTransaction: BitcoinTransaction

    public var isPSBTv2: Bool { psbtVersion >= 2 }

    /// BIP-174 `PSBT_GLOBAL_XPUB` (type 0x01).
    public var globalXpubs: [PSBTGlobalXpub] {
        global.all(type: 0x01).compactMap { entry in
            guard entry.keyData.count == 78, entry.value.count >= 4,
                  (entry.value.count - 4).isMultiple(of: 4) else { return nil }
            let fingerprint = Data(entry.value.prefix(4))
            var reader = ByteReader(Data(entry.value.dropFirst(4)))
            var components: [UInt32] = []
            while !reader.isAtEnd {
                guard let value = try? reader.readUInt32LE() else { return nil }
                components.append(value)
            }
            return PSBTGlobalXpub(fingerprint: fingerprint, path: DerivationPath(components),
                                  extendedKey: entry.keyData)
        }
    }

    public init(data: Data) throws {
        var reader = ByteReader(data)
        guard try reader.read(Self.magic.count) == Self.magic else { throw PSBTError.invalidMagic }
        let global = try PSBTMap.parse(reader: &reader)
        let declaredVersion = try Self.globalUInt32(global, type: 0xfb)
        let unsignedEntry = global.entries.first(where: { $0.key == Data([0x00]) })
        let version: UInt32
        if let declaredVersion {
            guard declaredVersion == 0 || declaredVersion == 2 else { throw PSBTError.unsupportedVersion(declaredVersion) }
            version = declaredVersion
        } else {
            // Firmware: version omitted → v2 if there is no global unsigned tx, else v0.
            version = unsignedEntry == nil ? 2 : 0
        }
        let isV2 = version >= 2

        if isV2 {
            guard unsignedEntry == nil else { throw PSBTError.malformed }
            guard let gtv = try Self.globalInt32(global, type: 0x02) else { throw PSBTError.malformed }
            guard let gic = try Self.globalCompactSize(global, type: 0x04) else { throw PSBTError.malformed }
            guard let goc = try Self.globalCompactSize(global, type: 0x05) else { throw PSBTError.malformed }
            guard gic > 0, goc > 0, gic <= 1_000_000, goc <= 1_000_000 else { throw PSBTError.malformed }
            if let modifiable = global.first(type: 0x06) {
                guard modifiable.key.count == 1, modifiable.value.count == 1 else { throw PSBTError.malformed }
            }
            let inputCount = Int(gic)
            let outputCount = Int(goc)
            var inputMaps: [PSBTMap] = []
            for _ in 0..<inputCount { inputMaps.append(try PSBTMap.parse(reader: &reader)) }
            var outputMaps: [PSBTMap] = []
            for _ in 0..<outputCount { outputMaps.append(try PSBTMap.parse(reader: &reader)) }
            guard reader.isAtEnd else { throw PSBTError.mapCountMismatch }
            let lockTime = try Self.globalUInt32(global, type: 0x03) ?? 0
            let transaction = try Self.transactionFromV2Maps(version: gtv, lockTime: lockTime,
                                                             inputs: inputMaps, outputs: outputMaps)
            self.global = global
            self.inputs = inputMaps
            self.outputs = outputMaps
            self.unsignedTransaction = transaction
            self.psbtVersion = version
        } else {
            guard let unsignedEntry else { throw PSBTError.missingUnsignedTransaction }
            // v0 forbids BIP-370 global fields (firmware `validate`).
            guard global.first(type: 0x02) == nil,
                  global.first(type: 0x03) == nil,
                  global.first(type: 0x04) == nil,
                  global.first(type: 0x05) == nil,
                  global.first(type: 0x06) == nil else { throw PSBTError.malformed }
            let parsed = try BitcoinTransaction(data: unsignedEntry.value)
            guard !parsed.inputs.contains(where: { !$0.scriptSig.isEmpty || !$0.witness.isEmpty }) else { throw PSBTError.malformed }
            var inputMaps: [PSBTMap] = []
            for _ in parsed.inputs { inputMaps.append(try PSBTMap.parse(reader: &reader)) }
            var outputMaps: [PSBTMap] = []
            for _ in parsed.outputs { outputMaps.append(try PSBTMap.parse(reader: &reader)) }
            guard reader.isAtEnd else { throw PSBTError.mapCountMismatch }
            try Self.validateV0Maps(inputs: inputMaps, outputs: outputMaps)
            self.global = global
            self.inputs = inputMaps
            self.outputs = outputMaps
            self.unsignedTransaction = parsed
            self.psbtVersion = version
        }
        try validateDerivationDepth()
    }

    public init(unsignedTransaction: BitcoinTransaction, inputs: [PSBTMap], outputs: [PSBTMap],
                psbtVersion: UInt32 = 0) throws {
        guard inputs.count == unsignedTransaction.inputs.count, outputs.count == unsignedTransaction.outputs.count else {
            throw PSBTError.mapCountMismatch
        }
        guard psbtVersion == 0 || psbtVersion == 2 else { throw PSBTError.unsupportedVersion(psbtVersion) }
        self.psbtVersion = psbtVersion
        self.unsignedTransaction = unsignedTransaction
        if psbtVersion >= 2 {
            var inputMaps = inputs
            var outputMaps = outputs
            for index in inputMaps.indices {
                let txin = unsignedTransaction.inputs[index]
                inputMaps[index].set(type: 0x0e, value: txin.previousTxID)
                var vout = Data(); vout.appendUInt32LE(txin.previousOutputIndex)
                inputMaps[index].set(type: 0x0f, value: vout)
                var sequence = Data(); sequence.appendUInt32LE(txin.sequence)
                inputMaps[index].set(type: 0x10, value: sequence)
            }
            for index in outputMaps.indices {
                let txout = unsignedTransaction.outputs[index]
                var amount = Data(); amount.appendUInt64LE(txout.value)
                outputMaps[index].set(type: 0x03, value: amount)
                outputMaps[index].set(type: 0x04, value: txout.scriptPubKey)
            }
            var global = PSBTMap()
            var txVersion = Data(); txVersion.appendUInt32LE(UInt32(bitPattern: unsignedTransaction.version))
            global.set(type: 0x02, value: txVersion)
            if unsignedTransaction.lockTime != 0 {
                var lockTime = Data(); lockTime.appendUInt32LE(unsignedTransaction.lockTime)
                global.set(type: 0x03, value: lockTime)
            }
            var inputCount = Data(); inputCount.appendVarInt(UInt64(inputMaps.count))
            global.set(type: 0x04, value: inputCount)
            var outputCount = Data(); outputCount.appendVarInt(UInt64(outputMaps.count))
            global.set(type: 0x05, value: outputCount)
            var version = Data(); version.appendUInt32LE(2)
            global.set(type: 0xfb, value: version)
            self.global = global
            self.inputs = inputMaps
            self.outputs = outputMaps
        } else {
            self.global = PSBTMap(entries: [PSBTEntry(key: Data([0x00]), value: unsignedTransaction.serialize(includeWitness: false))])
            self.inputs = inputs
            self.outputs = outputs
        }
        try validateDerivationDepth()
    }

    public static func decodeText(_ text: String) throws -> PSBT {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("70736274ff"), let data = try? Data(hex: trimmed) { return try PSBT(data: data) }
        if let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]) { return try PSBT(data: data) }
        throw PSBTError.malformed
    }

    public func serialize() -> Data {
        var result = Self.magic
        result.append(global.serialize())
        inputs.forEach { result.append($0.serialize()) }
        outputs.forEach { result.append($0.serialize()) }
        return result
    }

    public var base64: String { serialize().base64EncodedString() }

    /// Legal sighash flags per firmware `ALL_SIGHASH_FLAGS`: ALL/NONE/SINGLE, each optionally |ANYONECANPAY.
    static let legalSighashFlags: Set<UInt32> = [0x01, 0x02, 0x03, 0x81, 0x82, 0x83]

    public func review(root: HDKey, maxFeePercent: Int = 10, sighashChecks: Bool = true,
                       wallets: [MultisigWalletConfig] = [],
                       wifKeys: [WIFStoreItem] = [],
                       disableMultisigChecks: Bool = false,
                       utxoHistory: OutptValueCache = OutptValueCache(),
                       displayUnits: DisplayUnits = .btc) -> PSBTReview {
        var inputReviews: [PSBTInputReview] = []
        var inputTotal: UInt64 = 0
        var allValuesKnown = true
        var warnings: [String] = []
        var locktimeNotes: [String] = []
        var tbRelLocks: [(Int, UInt32)] = []
        var bbRelLocks: [(Int, UInt32)] = []
        var signable = 0
        var unusualSighash = false
        var noneSighash = false
        var singleSighash = false
        var illegalSighash = false
        var sawZeroXFP = false
        var signingInputPaths: [[UInt32]] = []
        var unverifiedWitnessUTXOs: [Int] = []
        var foreignMissingUTXOs: [Int] = []
        var fromWIF: [Int] = []
        var missingOwnUTXO = false
        var legacyNeedsNonWitness: String?
        var pendingSegwitVerify: [(prevout: Data, amount: UInt64, index: Int)] = []
        var history = utxoHistory

        let hasDuplicateInputs = hasFirmwareVisibleDuplicateInputs()
        var illegalSighashFlag: UInt32?
        var outputFatal: String?
        var allInputsPresigned = true
        var ourInputKeyCount = 0
        var hasAnyInputPaths = false
        var foreignFingerprints: [String] = []
        var seenForeign = Set<Data>()
        var taprootSpend = false
        var legacyNonWitnessIndex: Int?
        for index in inputs.indices {
            let map = inputs[index]
            let inputDerivations = map.all(type: 0x06).compactMap { try? PSBTDerivation(entry: $0) }
            if !inputDerivations.isEmpty { hasAnyInputPaths = true }
            let oursHere = inputDerivations.filter { derivationBelongs($0, to: root) }
            ourInputKeyCount += oursHere.count
            for derivation in inputDerivations where !derivationBelongs(derivation, to: root) {
                if seenForeign.insert(derivation.masterFingerprint).inserted {
                    foreignFingerprints.append(derivation.masterFingerprint.hexString.uppercased())
                }
            }
            let utxo = try? resolvedUTXO(index: index)
            let derivation = matchingDerivation(in: inputs[index], root: root)
            if hasZeroFingerprint(in: inputs[index], type: 0x06) { sawZeroXFP = true }
            let alreadySignedEarly = mapHasPartialSignature(inputs[index])
            let wifHit = utxo.flatMap { WIFStoreLogic.matchAddressHash(items: wifKeys, scriptPubKey: $0.scriptPubKey) }
            let isOurs = derivation != nil || wifHit != nil
            if wifHit != nil { fromWIF.append(index) }
            if let utxo {
                let hasNonWitness = map.first(type: 0x00) != nil
                let segwit = inputIsSegwit(utxo: utxo, map: map)
                if !hasNonWitness && !witnessUTXOIsProvablySegwit(utxo: utxo, map: map) {
                    // Firmware `consider_inputs`: witness UTXO that is not provably segwit
                    // cannot be used to compute `total_value_in` / fee.
                    unverifiedWitnessUTXOs.append(index)
                    allValuesKnown = false
                } else {
                    inputTotal &+= utxo.value
                }
                if isOurs, !segwit, !hasNonWitness, legacyNeedsNonWitness == nil {
                    legacyNeedsNonWitness = "Legacy input #\(index) requires non-witness UTXO"
                }
                if isOurs, segwit {
                    pendingSegwitVerify.append((unsignedTransaction.inputs[index].outpointData, utxo.value, index))
                }
            } else if isOurs && !alreadySignedEarly {
                missingOwnUTXO = true
                allValuesKnown = false
            } else {
                foreignMissingUTXOs.append(index)
                allValuesKnown = false
            }
            if !alreadySignedEarly { allInputsPresigned = false }
            if !oursHere.isEmpty, !alreadySignedEarly {
                let hasUTXO = map.first(type: 0x00) != nil || map.first(type: 0x01) != nil
                if !hasUTXO {
                    missingOwnUTXO = true
                } else if let utxo {
                    switch BitcoinScript.classify(utxo.scriptPubKey) {
                    case .p2tr:
                        taprootSpend = true
                    case .p2pkh, .p2pk:
                        if map.first(type: 0x00) == nil, legacyNonWitnessIndex == nil {
                            legacyNonWitnessIndex = index
                        }
                    case .p2sh:
                        if map.first(type: 0x00) == nil, !witnessUTXOIsProvablySegwit(utxo: utxo, map: map),
                           legacyNonWitnessIndex == nil {
                            legacyNonWitnessIndex = index
                        }
                    default:
                        break
                    }
                }
            }
            let canSign = (try? signingContext(index: index, root: root, sighashChecks: sighashChecks,
                                               wifKeys: wifKeys)) != nil
            if canSign { signable += 1 }
            let script = utxo?.scriptPubKey
            let address = script.flatMap { BitcoinScript.address(for: $0, network: root.network) }
            let sighash = try? declaredSighash(in: map)
            if let sighash, derivation != nil {
                if !Self.legalSighashFlags.contains(sighash) {
                    illegalSighash = true
                    if illegalSighashFlag == nil { illegalSighashFlag = sighash }
                } else if sighash != 1 {
                    unusualSighash = true
                    if sighash & 0x1f == 2 { noneSighash = true }
                    if sighash & 0x1f == 3 { singleSighash = true }
                }
            }
            let warning: String? = nil
            let txin = unsignedTransaction.inputs[index]
            let outpoint = "\(Data(txin.previousTxID.reversed()).hexString):\(txin.previousOutputIndex)"
            let redeem = map.first(type: 0x04)?.value
            let witness = map.first(type: 0x05)?.value
            let addressFormat = script.flatMap {
                DoneSigning.addressFormatName(scriptPubKey: $0, redeem: redeem, witness: witness)
                    ?? BIP322.addressFormatName($0)
            }
            var rtlNote: String?
            if unsignedTransaction.version >= 2, let rtl = BIP322.relativeTimelock(sequence: txin.sequence) {
                if rtl.isTimeBased {
                    tbRelLocks.append((index, rtl.value))
                    rtlNote = "Input has relative time-based timelock of:\n \(BIP322.humanSeconds(rtl.value))"
                } else {
                    bbRelLocks.append((index, rtl.value))
                    rtlNote = "Input has relative block height timelock of \(rtl.value) blocks"
                }
            }
            let subpaths = inputs[index].all(type: 0x06).compactMap { try? PSBTDerivation(entry: $0) }
            let signedPubs = Set(inputs[index].all(type: 0x02).map(\.keyData))
            let signedXFPs = subpaths.filter { signedPubs.contains($0.publicKey) }
                .map { $0.masterFingerprint.hexString.uppercased() }
            let scriptForMN = witness ?? redeem
            let mn = scriptForMN.flatMap { try? MultisigScript.disassemble($0) }
            let fullySigned = DoneSigning.inputFullySigned(
                partialSignatureCount: signedPubs.count,
                requiredM: mn?.requiredSignatures,
                subpathCount: subpaths.count
            )
            let ourKeys: [PSBTExplorerOurKey] = subpaths.compactMap { item in
                guard derivationBelongs(item, to: root),
                      let key = try? root.derived(path: item.path),
                      key.publicKey == item.publicKey else { return nil }
                return PSBTExplorerOurKey(
                    xfpPath: DoneSigning.ourKeyLabel(
                        xfp: item.masterFingerprint.hexString.uppercased(),
                        path: item.path
                    ),
                    publicKeyHex: item.publicKey.hexString
                )
            }
            inputReviews.append(PSBTInputReview(
                index: index, value: utxo?.value, address: address,
                path: derivation?.path.description, signable: canSign, warning: warning,
                previousOutpoint: outpoint, scriptPubKeyHex: utxo?.scriptPubKey.hexString,
                sequence: txin.sequence, alreadySigned: alreadySignedEarly,
                fullySigned: fullySigned, signedCosignerXFPs: signedXFPs,
                multisigMN: mn.map { "\($0.requiredSignatures)of\($0.totalSigners)" },
                sighashNote: sighash.flatMap { DoneSigning.sighashNote($0) },
                ourKeys: ourKeys, hasUTXO: utxo != nil,
                addressFormat: addressFormat, relativeTimelockNote: rtlNote,
                ourPublicKeyHex: derivation?.publicKey.hexString
            ))
            if canSign, !alreadySignedEarly, let derivation {
                signingInputPaths.append(derivation.path.components)
            }
        }

        var outputReviews: [PSBTOutputReview] = []
        var outputTotal: UInt64 = 0
        var opReturnCount = 0
        var opReturnOversized = 0
        var unknownScripts = 0
        var zeroValueNonOpReturn = 0
        var changePaths: [(index: Int, components: [UInt32])] = []
        let activeMultisig = matchingMultisigWallet(wallets: wallets)
        for index in unsignedTransaction.outputs.indices {
            let output = unsignedTransaction.outputs[index]
            outputTotal &+= output.value
            if hasZeroFingerprint(in: outputs[index], type: 0x02) { sawZeroXFP = true }
            let analyzed = analyzeChangeOutput(
                index: index, script: output.scriptPubKey, map: outputs[index],
                root: root, activeMultisig: activeMultisig,
                disableMultisigChecks: disableMultisigChecks
            )
            if case .fatal(let message) = analyzed, outputFatal == nil {
                outputFatal = message
            }
            let isChange: Bool
            let changePath: String?
            switch analyzed {
            case .change(let path):
                isChange = true
                changePath = path
            case .notChange, .fatal:
                isChange = false
                changePath = nil
            }
            let derivation = matchingDerivation(in: outputs[index], root: root, type: 0x02)
            let scriptKind = BitcoinScript.classify(output.scriptPubKey)
            switch scriptKind {
            case .unknown:
                unknownScripts += 1
            case .opReturn:
                opReturnCount += 1
                if output.scriptPubKey.count > 83 { opReturnOversized += 1 }
            default:
                if output.value == 0 { zeroValueNonOpReturn += 1 }
            }
            let address = BitcoinScript.address(for: output.scriptPubKey, network: root.network)
                ?? "script:\(output.scriptPubKey.hexString.prefix(24))…"
            outputReviews.append(PSBTOutputReview(index: index, value: output.value, address: address,
                                                  scriptPubKey: output.scriptPubKey,
                                                  isChange: isChange, path: isChange ? changePath : nil))
            if isChange, let derivation {
                changePaths.append((index, derivation.path.components))
            }
        }
        let fee = allValuesKnown && inputTotal >= outputTotal ? inputTotal - outputTotal : nil
        let feeRate = fee.map { Double($0) / Double(max(1, unsignedTransaction.virtualSize)) }
        let feePercent: Double?
        if let fee, outputTotal > 0 {
            feePercent = (Double(fee) * 100) / Double(outputTotal)
        } else if fee != nil {
            feePercent = 100
        } else {
            feePercent = nil
        }
        var feeExceedsLimit = false
        var feeLimitIssue: String?
        var bigFeeWarning: String?
        if let feePercent {
            if maxFeePercent != -1, feePercent >= Double(maxFeePercent) {
                feeExceedsLimit = true
                feeLimitIssue = String(format: "Network fee bigger than %d%% of total amount (it is %.0f%%).", maxFeePercent, feePercent)
            } else if feePercent >= 5 {
                bigFeeWarning = String(format: "Big Fee: Network fee is more than 5%% of total value (%.1f%%).", feePercent)
            }
        }

        var sighashFatal: String?
        var sighashBlocked = illegalSighash
        let consolidation = !outputReviews.isEmpty && outputReviews.allSatisfy(\.isChange)
        if unusualSighash && sighashChecks {
            if consolidation {
                sighashBlocked = true
                sighashFatal = "Only sighash ALL is allowed for pure consolidation transactions."
            } else if noneSighash {
                sighashBlocked = true
                sighashFatal = "Sighash NONE is not allowed as funds could be going anywhere."
            } else if singleSighash {
                sighashBlocked = true
                sighashFatal = "Sighash SINGLE is not allowed as some outputs could be changed."
            }
        }

        let lockTime = unsignedTransaction.lockTime
        var badLocktime = false
        if lockTime > 0 {
            if inputReviews.allSatisfy({ $0.sequence == 0xffffffff }) {
                badLocktime = true
            } else {
                locktimeNotes.append("Abs Locktime: \(Self.absLocktimeMessage(lockTime))")
            }
        }
        locktimeNotes.append(contentsOf: Self.relativeTimelockApprovalNotes(
            blockHeight: bbRelLocks, timeBased: tbRelLocks
        ))

        let porMessage: String? = {
            guard let entry = global.first(type: 0x09),
                  let text = String(data: entry.value, encoding: .utf8), !text.isEmpty else { return nil }
            return text
        }()
        let singleNullOpReturn = unsignedTransaction.outputs.count == 1
            && unsignedTransaction.outputs.first?.value == 0
            && unsignedTransaction.outputs.first?.scriptPubKey == Data([0x6a])
        let isBIP322 = porMessage != nil && singleNullOpReturn
        let isProofOfReserves = isBIP322 && unsignedTransaction.inputs.count > 1
        var bip322Challenge: String?
        var bip322Fatal: String?
        if isBIP322, let porMessage {
            do {
                _ = try BitcoinMessageSigner.validate(porMessage, allowTabAndNewline: true, maxLength: 330)
            } catch {
                bip322Fatal = error.localizedDescription
            }
            if ![0, 2].contains(unsignedTransaction.version) {
                bip322Fatal = bip322Fatal ?? "bad txn version"
            }
            if let utxo = try? resolvedUTXO(index: 0), unsignedTransaction.inputs.indices.contains(0) {
                let toSpend = BIP322.toSpend(messageHash: BIP322.messageHash(porMessage), challenge: utxo.scriptPubKey)
                let input0 = unsignedTransaction.inputs[0]
                if input0.previousTxID != toSpend.txidHash || input0.previousOutputIndex != 0 || utxo.value != 0 {
                    bip322Fatal = bip322Fatal ?? "i0: invalid BIP-322 'to_spend'"
                } else {
                    bip322Challenge = BitcoinScript.address(for: utxo.scriptPubKey, network: root.network)
                        ?? utxo.scriptPubKey.hexString
                }
            }
            for index in inputs.indices {
                let ours = matchingDerivation(in: inputs[index], root: root) != nil || fromWIF.contains(index)
                guard ours, let sighash = try? declaredSighash(in: inputs[index]) else { continue }
                if sighash != 1 {
                    bip322Fatal = bip322Fatal ?? "POR not SIGHASH_ALL"
                }
            }
        } else if unsignedTransaction.version == 0 {
            bip322Fatal = "bad txn version"
        }

        var utxoAmountFatal: String?
        if !isBIP322 {
            for item in pendingSegwitVerify {
                do {
                    try history.verifyAmount(
                        prevout: item.prevout,
                        amount: item.amount,
                        inputIndex: item.index,
                        displayUnits: displayUnits,
                        network: root.network
                    )
                } catch OutptValueCacheError.incorrectAmount(let message) {
                    utxoAmountFatal = utxoAmountFatal ?? message
                } catch {
                    continue
                }
            }
        }

        // Firmware warning append order: validate → consider_inputs → consider_outputs → consider_dangerous_sighash.
        if sawZeroXFP {
            warnings.append("Zero XFP: Assuming XFP of zero should be replaced by correct XFP")
        }
        if badLocktime {
            warnings.append("Bad Locktime: Locktime has no effect! None of the nSequences decremented.")
        }
        if !foreignMissingUTXOs.isEmpty {
            warnings.append("Unable to calculate fee: Some input(s) haven't provided UTXO(s): " +
                            Self.seqToStr(foreignMissingUTXOs))
        }
        if !unverifiedWitnessUTXOs.isEmpty {
            warnings.append("Unable to calculate fee: Some input(s) provided unverified witness UTXO(s): " +
                            Self.seqToStr(unverifiedWitnessUTXOs))
        }
        let unsignedUnsignable = inputReviews.indices.filter { !inputReviews[$0].signable && !inputReviews[$0].alreadySigned }
        if !unsignedUnsignable.isEmpty && signable > 0 {
            warnings.append("Limited Signing: We are not signing these inputs, because we do not know the key: " +
                            Self.seqToStr(unsignedUnsignable))
        }
        let presigned = inputReviews.compactMap { $0.alreadySigned ? $0.index : nil }
        if !presigned.isEmpty {
            warnings.append("Partly Signed Already: Some input(s) provided were already completely signed by other parties: " +
                            Self.seqToStr(presigned))
        }
        if !fromWIF.isEmpty {
            warnings.append("WIF Store: Some input(s) use key from the WIF store: " + Self.seqToStr(fromWIF))
        }
        if disableMultisigChecks {
            warnings.append("Danger: Some multisig checks are disabled.")
        }
        if !isBIP322 {
            if let bigFeeWarning { warnings.append(bigFeeWarning) }
            if opReturnCount > 1 || opReturnOversized > 0 {
                var extra = ""
                if opReturnCount > 1 { extra += "\nMultiple OP_RETURN outputs: \(opReturnCount)" }
                if opReturnOversized > 0 { extra += "\nOP_RETURN > 80 bytes" }
                warnings.append("OP_RETURN: TX may not be relayed by some nodes.\(extra)")
            }
            if unknownScripts > 0 {
                warnings.append("Output?: Sending to \(unknownScripts) not well understood script(s).")
            }
            if zeroValueNonOpReturn > 0 {
                warnings.append("Zero Value: Non-standard zero value output(s).")
            }
            warnings.append(contentsOf: troublesomeChangeWarnings(inputPaths: signingInputPaths, changePaths: changePaths))
        }
        if !sighashBlocked {
            if noneSighash {
                warnings.append("Danger: Destination address can be changed after signing (sighash NONE).")
            } else if unusualSighash {
                warnings.append("Caution: Some inputs have unusual SIGHASH values not used in typical cases.")
            }
        }

        // Firmware `FatalPSBTIssue` conditions: the PSBT is refused outright, never reviewed.
        let fatalIssue: String?
        if let bip322Fatal {
            fatalIssue = bip322Fatal
        } else if ourInputKeyCount == 0, fromWIF.isEmpty {
            if !hasAnyInputPaths {
                fatalIssue = "PSBT does not contain any key path information."
            } else {
                fatalIssue = Self.noKeyError + " (need \(root.fingerprintHex), found \(foreignFingerprints.joined(separator: ", ")))"
            }
        } else if hasDuplicateInputs {
            fatalIssue = "Duplicate inputs"
        } else if let flag = illegalSighashFlag {
            fatalIssue = String(format: "Unsupported sighash flag 0x%x", flag)
        } else if let sighashFatal {
            fatalIssue = sighashFatal
        } else if missingOwnUTXO {
            fatalIssue = "Missing own UTXO(s). Cannot determine value being signed"
        } else if taprootSpend {
            fatalIssue = "Install EDGE firmware to spend taproot."
        } else if let index = legacyNonWitnessIndex {
            fatalIssue = "Legacy input #\(index) requires non-witness UTXO"
        } else if let legacyNeedsNonWitness {
            fatalIssue = legacyNeedsNonWitness
        } else if let utxoAmountFatal {
            fatalIssue = utxoAmountFatal
        } else if allInputsPresigned, !inputs.isEmpty {
            fatalIssue = "Transaction looks completely signed already?"
        } else if let outputFatal {
            fatalIssue = outputFatal
        } else if allValuesKnown && inputTotal < outputTotal && !isBIP322 {
            fatalIssue = "Outputs worth more than inputs!"
        } else if let feeLimitIssue, !isBIP322 {
            fatalIssue = feeLimitIssue
        } else if let flag = illegalSighashFlag {
            fatalIssue = String(format: "Unsupported sighash flag 0x%x", flag)
        } else if let sighashFatal {
            fatalIssue = sighashFatal
        } else if signable == 0 {
            fatalIssue = Self.noKeyError
        } else {
            fatalIssue = nil
        }

        return PSBTReview(transactionID: unsignedTransaction.txid, inputs: inputReviews, outputs: outputReviews,
                          totalInput: allValuesKnown ? inputTotal : nil, totalOutput: outputTotal, fee: fee,
                          feeRate: feeRate, feePercentOfOutputs: feePercent, warnings: warnings,
                          locktimeNotes: locktimeNotes, lockTime: lockTime,
                          signableInputCount: signable, feeExceedsLimit: feeExceedsLimit,
                          sighashBlocked: sighashBlocked, fatalIssue: fatalIssue,
                          bip322Message: isBIP322 ? porMessage : nil,
                          bip322IsProofOfReserves: isProofOfReserves,
                          bip322Challenge: bip322Challenge,
                          multisigWalletName: matchingMultisigWallet(wallets: wallets)?.name,
                          utxoHistory: history)
    }

    /// Firmware `psbt.py` abs locktime sentence (without the `Abs Locktime:` label).
    public static func absLocktimeMessage(_ lockTime: UInt32) -> String {
        var msg = "This tx can only be spent after "
        if lockTime < 500_000_000 {
            msg += "block height of \(lockTime)"
        } else {
            msg += absLocktimeTimestamp(lockTime)
            msg += " (MTP)"
        }
        return msg
    }

    /// Firmware `datetime_to_str` plus UTC, used when locktime is a timestamp.
    /// Falls back to `"%d (unix timestamp)"` if conversion fails (`psbt.py` except).
    public static func absLocktimeTimestamp(_ lockTime: UInt32) -> String {
        datetimeToStrUTC(lockTime) ?? absLocktimeUnixTimestamp(lockTime)
    }

    /// Firmware except path: `"%d (unix timestamp)" % self.lock_time`.
    public static func absLocktimeUnixTimestamp(_ lockTime: UInt32) -> String {
        String(format: "%d (unix timestamp)", lockTime)
    }

    /// Firmware `datetime_to_str(datetime_from_timestamp(lock_time))`.
    static func datetimeToStrUTC(_ lockTime: UInt32) -> String? {
        let date = Date(timeIntervalSince1970: TimeInterval(lockTime))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute, let second = parts.second else {
            return nil
        }
        return String(format: "%d-%02d-%02d %02d:%02d:%02d UTC", year, month, day, hour, minute, second)
    }

    /// Firmware `psbtObject.ux_relative_timelocks` as `- label: message` bodies.
    public static func relativeTimelockApprovalNotes(
        blockHeight: [(Int, UInt32)],
        timeBased: [(Int, UInt32)]
    ) -> [String] {
        let maxShow = 10
        let numBB = blockHeight.count
        let numTB = timeBased.count
        var block = blockHeight
        var time = timeBased
        if numBB + numTB > maxShow {
            block = Array(block.sorted { $0.1 > $1.1 }.prefix(10))
            time = Array(time.sorted { $0.1 > $1.1 }.prefix(10))
            if numTB >= 5 && numBB >= 5 {
                time = Array(time.prefix(5))
                block = Array(block.prefix(5))
            } else if numTB < numBB {
                time = Array(time.prefix(numTB))
                block = Array(block.prefix(maxShow - numTB))
            } else {
                block = Array(block.prefix(numBB))
                time = Array(time.prefix(maxShow - numBB))
            }
        }
        var notes: [String] = []
        if numBB > 0 {
            let msg: String
            if numBB == 1 {
                msg = "Input \(block[0].0). has relative block height timelock of \(block[0].1) blocks"
            } else if block.allSatisfy({ $0.1 == block[0].1 }) {
                msg = "\(numBB) inputs have relative block height timelock of \(block[0].1) blocks"
            } else {
                var body = "\(numBB) inputs have relative block height timelock."
                if numBB > block.count {
                    body += " Showing only \(block.count) with highest values."
                }
                body += "\n\n" + block.map { " \($0.0).  \($0.1) blocks" }.joined(separator: "\n")
                msg = body
            }
            notes.append("Block height RTL: \(msg)")
        }
        if numTB > 0 {
            let msg: String
            if numTB == 1 {
                msg = "Input \(time[0].0). has relative time-based timelock of:\n \(BIP322.humanSeconds(time[0].1))"
            } else if time.allSatisfy({ $0.1 == time[0].1 }) {
                msg = "\(numTB) inputs have relative time-based timelock of:\n \(BIP322.humanSeconds(time[0].1))"
            } else {
                var body = "\(numTB) inputs have relative time-based timelock."
                if numTB > time.count {
                    body += " Showing only \(time.count) with highest values."
                }
                body += "\n\n" + time.map { " \($0.0).  \(BIP322.humanSeconds($0.1))" }.joined(separator: "\n")
                msg = body
            }
            notes.append("Time-based RTL: \(msg)")
        }
        return notes
    }

    /// Firmware `auth.py` story title: `OK TO SIGN?` for any BIP-322 / PoR, else `OK TO SEND?`.
    public static func approvalTitle(isBIP322: Bool) -> String {
        isBIP322 ? "OK TO SIGN?" : "OK TO SEND?"
    }

    /// Firmware Q `ux_show_story` footer (`OK`/`X` plus explore key). `(B)` when `input_method == "sd"` and both slots are inserted (`auth.py:544-546`).
    public static func approvalFooter(
        noun: String,
        okKey: String = "ENTER",
        cancelKey: String = "CANCEL",
        writeToLowerSlot: Bool = false
    ) -> String {
        var msg = "Press \(okKey) to approve and sign \(noun). Press (2) to explore transaction."
        if writeToLowerSlot { msg += " (B) to write to lower SD slot." }
        msg += " \(cancelKey) to abort."
        return msg
    }

    /// Firmware `auth.py` `noun` for the approve footer.
    public static func approveNoun(isBIP322: Bool, isProofOfReserves: Bool) -> String {
        guard isBIP322 else { return "transaction" }
        return isProofOfReserves ? "proof of reserves" : "message"
    }

    /// Firmware `auth.py` input/output count lines (`" %d input(s)\\n %d output(s)\\n\\n"`).
    public static func inputOutputCountLine(inputs: Int, outputs: Int) -> String {
        " \(inputs) \(inputs == 1 ? "input" : "inputs")\n \(outputs) \(outputs == 1 ? "output" : "outputs")\n\n"
    }

    /// Firmware `auth.py` BIP-322 / Proof of Reserves story block (`interact` after the warning header).
    public static func bip322ApprovalPreamble(
        isProofOfReserves: Bool,
        message: String,
        amount: String? = nil,
        challengeAddress: String? = nil,
        challengeHex: String? = nil,
        inputCount: Int,
        outputCount: Int
    ) -> String {
        var msg = "\(isProofOfReserves ? "Proof of Reserves" : "BIP-322 Message")\n\n"
        msg += "Message:\n\(message)\n\n"
        if isProofOfReserves, let amount {
            msg += "Amount \(amount)\n\n"
        }
        if let challengeAddress {
            msg += "Challenge Address:\n\(LCDDisplay.showSingleAddress(challengeAddress))\n\n"
        } else if let challengeHex {
            msg += "Message Challenge:\n\(challengeHex)\n\n"
        }
        if isProofOfReserves {
            msg += inputOutputCountLine(inputs: inputCount, outputs: outputCount)
        }
        return msg
    }

    /// Firmware `seq_to_str`: sorted 0-based input indexes.
    public static func seqToStr(_ indexes: [Int]) -> String {
        indexes.sorted().map(String.init).joined(separator: ", ")
    }

    /// Firmware `TX LOCKTIMES` block. Each `ux_notes` message already ends with a newline in Python; `- label: msg\\n` therefore blanks a line after every note.
    public static func approvalLocktimeSection(_ notes: [String]) -> String {
        guard !notes.isEmpty else { return "" }
        var msg = "TX LOCKTIMES\n\n"
        for note in notes { msg += "- \(note)\n\n" }
        return msg
    }

    /// Firmware `Sending` / `Consolidating … within wallet.` preamble (amounts already rendered).
    public static func approvalValuePreamble(isConsolidation: Bool, sendAmount: String, totalOutput: String) -> String {
        if isConsolidation {
            return "Consolidating \(totalOutput)\nwithin wallet.\n\n"
        }
        return "Sending \(sendAmount)\n"
    }

    /// Firmware `output_summary_text` selection: keep original order until the 10/20 cap, then keep the largest (stable descending).
    public static func approvalOutputSummary(
        _ outputs: [PSBTOutputReview],
        maxForeign: Int = 10,
        maxChange: Int = 20
    ) -> PSBTApprovalOutputSummary {
        var foreign: [PSBTOutputReview] = []
        var change: [PSBTOutputReview] = []
        for output in outputs {
            if output.isChange {
                if change.count < maxChange {
                    change.append(output)
                    if change.count == maxChange {
                        change = Self.stableDescendingByValue(change)
                    }
                    continue
                }
            } else if foreign.count < maxForeign {
                foreign.append(output)
                if foreign.count == maxForeign {
                    foreign = Self.stableDescendingByValue(foreign)
                }
                continue
            }
            var largest = output.isChange ? change : foreign
            var insertAt: Int?
            for (index, existing) in largest.enumerated() where output.value > existing.value {
                insertAt = index
                break
            }
            guard let insertAt else { continue }
            largest.removeLast()
            largest.insert(output, at: insertAt)
            if output.isChange { change = largest } else { foreign = largest }
        }
        let changeTotal = outputs.filter(\.isChange).reduce(UInt64(0)) { $0 + $1.value }
        let foreignTotal = outputs.filter { !$0.isChange }.reduce(UInt64(0)) { $0 + $1.value }
        let visibleForeign = foreign.reduce(UInt64(0)) { $0 + $1.value }
        let visibleChange = change.reduce(UInt64(0)) { $0 + $1.value }
        let changeCount = outputs.filter(\.isChange).count
        return PSBTApprovalOutputSummary(
            foreign: foreign,
            change: change,
            changeTotal: changeTotal,
            hiddenForeignCount: outputs.count - foreign.count - changeCount,
            hiddenForeignValue: foreignTotal &- visibleForeign,
            hiddenChangeCount: changeCount - change.count,
            hiddenChangeValue: changeTotal &- visibleChange,
            isConsolidation: outputs.allSatisfy(\.isChange)
        )
    }

    private static func stableDescendingByValue(_ outputs: [PSBTOutputReview]) -> [PSBTOutputReview] {
        outputs.enumerated().sorted { lhs, rhs in
            if lhs.element.value != rhs.element.value { return lhs.element.value > rhs.element.value }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    public func signed(using root: HDKey, sighashChecks: Bool = true, deltaMode: Bool = false,
                       wifKeys: [WIFStoreItem] = []) -> PSBTSigningResult {
        var copy = self
        var results: [PSBTInputSigningResult] = []
        var signedCount = 0
        var txnModifiable: UInt8 = copy.global.first(type: 0x06)?.value.first ?? 3
        var updatedModifiable = false
        for index in inputs.indices {
            do {
                let context = try copy.signingContext(index: index, root: root, sighashChecks: sighashChecks,
                                                      wifKeys: wifKeys)
                let sighashType = context.sighashType
                var digest: Data
                switch context.kind {
                case .legacy:
                    digest = try unsignedTransaction.legacySignatureHash(inputIndex: index, scriptCode: context.scriptCode,
                                                                         sighashType: sighashType)
                case .segwit:
                    digest = try unsignedTransaction.segwitV0SignatureHash(inputIndex: index, scriptCode: context.scriptCode,
                                                                           value: context.utxo.value, sighashType: sighashType)
                }
                if deltaMode {
                    // Firmware `psbt.py`: silently corrupt the sighash in delta mode.
                    digest = SHA2.doubleSHA256(digest)
                }
                guard let privateKey = context.key.privateKey else { throw PSBTError.noMatchingKey }
                let signature = try Secp256k1.sign(hash: digest, privateKey: privateKey)
                var value = signature.der
                value.append(UInt8(truncatingIfNeeded: sighashType))
                copy.inputs[index].set(type: 0x02, keyData: context.derivation.publicKey, value: value)
                results.append(PSBTInputSigningResult(index: index, signed: true,
                                                      message: "Signed with \(context.derivation.path.description)"))
                signedCount += 1
                if copy.isPSBTv2 {
                    // Firmware `set_modifiable_flag` after each v2 signature.
                    updatedModifiable = true
                    if sighashType & 0x80 == 0 { txnModifiable &= ~1 }
                    if sighashType & 0x1f != 2 { txnModifiable &= ~2 }
                    if sighashType & 0x1f == 3 { txnModifiable |= 4 }
                }
            } catch {
                results.append(PSBTInputSigningResult(index: index, signed: false, message: error.localizedDescription))
            }
        }
        if copy.isPSBTv2, updatedModifiable {
            copy.global.set(type: 0x06, value: Data([txnModifiable]))
        }
        return PSBTSigningResult(data: copy.serialize(), signedInputCount: signedCount, inputs: results, psbt: copy)
    }

    /// Firmware `psbt.is_complete()`: every input has added/partial sigs, using M-of-N when known.
    public func isComplete(requiredSignatures: Int? = nil) -> Bool {
        let threshold = requiredSignatures ?? guessMultisigPolicy()?.requiredSignatures
        guard !inputs.isEmpty else { return true }
        for map in inputs {
            let sigs = map.all(type: 0x02).count
            let script = map.first(type: 0x05)?.value ?? map.first(type: 0x04)?.value
            let m = script.flatMap { try? MultisigScript.disassemble($0).requiredSignatures } ?? threshold
            if let m {
                if sigs < m { return false }
            } else if sigs == 0 {
                return false
            }
        }
        return true
    }

    /// Firmware `psbt.finalize`: stream a broadcastable txn once `is_complete()`.
    public func extractedTransaction() throws -> BitcoinTransaction {
        var transaction = unsignedTransaction
        for index in inputs.indices {
            let sigs = inputs[index].all(type: 0x02)
            guard let first = sigs.first else { throw PSBTError.unsupportedInput }
            let utxo = try resolvedUTXO(index: index)
            let redeem = inputs[index].first(type: 0x04)?.value
            let witnessScript = inputs[index].first(type: 0x05)?.value
            switch BitcoinScript.classify(utxo.scriptPubKey) {
            case .p2pkh:
                transaction.inputs[index].scriptSig = BitcoinScript.push(first.value) + BitcoinScript.push(first.keyData)
                transaction.inputs[index].witness = []
            case .p2wpkh:
                transaction.inputs[index].scriptSig = Data()
                transaction.inputs[index].witness = [first.value, first.keyData]
            case .p2wsh:
                guard let witnessScript else { throw PSBTError.unsupportedInput }
                transaction.inputs[index].scriptSig = Data()
                transaction.inputs[index].witness = try finalizedMultisigStack(sigs: sigs, script: witnessScript)
            case .p2sh:
                guard let redeem else { throw PSBTError.invalidUTXO }
                if redeem.count == 22, redeem.starts(with: [0x00, 0x14]) {
                    transaction.inputs[index].scriptSig = BitcoinScript.push(redeem)
                    transaction.inputs[index].witness = [first.value, first.keyData]
                } else if redeem.count == 34, redeem.starts(with: [0x00, 0x20]), let witnessScript {
                    transaction.inputs[index].scriptSig = BitcoinScript.push(redeem)
                    transaction.inputs[index].witness = try finalizedMultisigStack(sigs: sigs, script: witnessScript)
                } else if let policy = try? MultisigScript.disassemble(redeem) {
                    let ordered = try orderedMultisigSignatures(
                        sigs: sigs, publicKeys: policy.publicKeys, required: policy.requiredSignatures
                    )
                    var scriptSig = Data([0x00])
                    for signature in ordered { scriptSig.append(BitcoinScript.push(signature)) }
                    scriptSig.append(BitcoinScript.push(redeem))
                    transaction.inputs[index].scriptSig = scriptSig
                    transaction.inputs[index].witness = []
                } else {
                    throw PSBTError.unsupportedInput
                }
            default:
                throw PSBTError.unsupportedInput
            }
        }
        return transaction
    }

    private func finalizedMultisigStack(sigs: [PSBTEntry], script: Data) throws -> [Data] {
        let policy = try MultisigScript.disassemble(script)
        let ordered = try orderedMultisigSignatures(
            sigs: sigs, publicKeys: policy.publicKeys, required: policy.requiredSignatures
        )
        return [Data()] + ordered + [script]
    }

    private func orderedMultisigSignatures(sigs: [PSBTEntry], publicKeys: [Data], required: Int) throws -> [Data] {
        var byPub: [Data: Data] = [:]
        for entry in sigs { byPub[entry.keyData] = entry.value }
        var ordered: [Data] = []
        for key in publicKeys {
            if let signature = byPub[key] { ordered.append(signature) }
            if ordered.count == required { break }
        }
        if ordered.count < required {
            for entry in sigs where !ordered.contains(entry.value) {
                ordered.append(entry.value)
                if ordered.count == required { break }
            }
        }
        let trimmed = Array(ordered.prefix(required))
        guard trimmed.count >= required else { throw PSBTError.unsupportedInput }
        return trimmed
    }

    private enum SigningKind { case legacy, segwit }
    private struct SigningContext {
        let key: HDKey
        let derivation: PSBTDerivation
        let utxo: TransactionOutput
        let scriptCode: Data
        let sighashType: UInt32
        let kind: SigningKind
    }

    private func signingContext(index: Int, root: HDKey, sighashChecks: Bool = true,
                                wifKeys: [WIFStoreItem] = []) throws -> SigningContext {
        guard inputs.indices.contains(index) else { throw PSBTError.malformed }
        guard !hasFirmwareVisibleDuplicateInputs() else { throw PSBTError.duplicateInput }
        let map = inputs[index]
        let utxo = try resolvedUTXO(index: index)
        let sighash = try declaredSighash(in: map)
        guard Self.legalSighashFlags.contains(sighash) else { throw PSBTError.dangerousSighash(sighash) }
        // ALL and ALL|ANYONECANPAY always sign; NONE/SINGLE need "Sighash Checks" set to Warn.
        if sighashChecks, sighash & 0x1f != 1 { throw PSBTError.dangerousSighash(sighash) }

        let derivations = map.all(type: 0x06).compactMap { try? PSBTDerivation(entry: $0) }
        var candidates: [(HDKey, PSBTDerivation)] = []
        for derivation in derivations where derivationBelongs(derivation, to: root) {
            guard let key = try? root.derived(path: derivation.path), key.publicKey == derivation.publicKey else { continue }
            candidates.append((key, derivation))
        }
        if candidates.isEmpty,
           let wifIndex = WIFStoreLogic.matchAddressHash(items: wifKeys, scriptPubKey: utxo.scriptPubKey),
           wifKeys.indices.contains(wifIndex),
           let privateKey = wifKeys[wifIndex].privateKey,
           let publicKey = wifKeys[wifIndex].publicKey {
            let key = try HDKey.master(privateKey: privateKey, chainCode: Data(repeating: 0, count: 32),
                                       network: root.network)
            let derivation = PSBTDerivation(publicKey: publicKey, masterFingerprint: Data(repeating: 0, count: 4),
                                            path: DerivationPath())
            candidates.append((key, derivation))
        }

        for (key, derivation) in candidates {
            let keyHash = BitcoinHash.hash160(key.publicKey)
            switch BitcoinScript.classify(utxo.scriptPubKey) {
            case .p2pkh(let hash) where hash == keyHash:
                guard map.first(type: 0x00) != nil else { throw PSBTError.invalidUTXO }
                return SigningContext(key: key, derivation: derivation, utxo: utxo,
                                      scriptCode: utxo.scriptPubKey, sighashType: sighash, kind: .legacy)
            case .p2wpkh(let hash) where hash == keyHash:
                return SigningContext(key: key, derivation: derivation, utxo: utxo,
                                      scriptCode: BitcoinScript.p2pkhScriptCode(pubkeyHash: keyHash),
                                      sighashType: sighash, kind: .segwit)
            case .p2sh(let scriptHash):
                if let redeem = map.first(type: 0x04)?.value,
                   redeem == Data([0x00, 0x14]) + keyHash,
                   BitcoinHash.hash160(redeem) == scriptHash {
                    return SigningContext(key: key, derivation: derivation, utxo: utxo,
                                          scriptCode: BitcoinScript.p2pkhScriptCode(pubkeyHash: keyHash),
                                          sighashType: sighash, kind: .segwit)
                }
                if let redeem = map.first(type: 0x04)?.value,
                   BitcoinHash.hash160(redeem) == scriptHash {
                    if redeem.count == 34, redeem.starts(with: [0x00, 0x20]),
                       let witness = map.first(type: 0x05)?.value,
                       SHA2.sha256(witness) == redeem.subdata(in: 2..<34),
                       witnessContains(witness, publicKey: key.publicKey) {
                        return SigningContext(key: key, derivation: derivation, utxo: utxo,
                                              scriptCode: witness, sighashType: sighash, kind: .segwit)
                    }
                    if witnessContains(redeem, publicKey: key.publicKey) {
                        guard map.first(type: 0x00) != nil else { throw PSBTError.invalidUTXO }
                        return SigningContext(key: key, derivation: derivation, utxo: utxo,
                                              scriptCode: redeem, sighashType: sighash, kind: .legacy)
                    }
                }
            case .p2wsh(let hash):
                guard let witness = map.first(type: 0x05)?.value,
                      SHA2.sha256(witness) == hash,
                      witnessContains(witness, publicKey: key.publicKey) else { continue }
                return SigningContext(key: key, derivation: derivation, utxo: utxo,
                                      scriptCode: witness, sighashType: sighash, kind: .segwit)
            case .p2tr:
                // TODO: Taproot / Schnorr signing is not implemented. Pinned firmware also
                // refuses P2TR spends ("Install EDGE firmware to spend taproot.") and there is
                // no key-path Schnorr signer or BIP-371 taproot field support here. Prefer a
                // complete skip over a half-signer; see README remaining-work note.
                continue
            default: continue
            }
        }
        throw PSBTError.noMatchingKey
    }

    private func witnessContains(_ script: Data, publicKey: Data) -> Bool {
        (try? MultisigScript.disassemble(script).publicKeys.contains(publicKey)) ?? false
    }

    /// Firmware `guess_M_of_N` plus `guess_multisig_addr_fmt` from the first multisig input.
    public func guessMultisigPolicy() -> (format: MultisigAddressFormat, requiredSignatures: Int, totalSigners: Int)? {
        for map in inputs {
            let witness = map.first(type: 0x05)?.value
            let redeem = map.first(type: 0x04)?.value
            if let witness, let parsed = try? MultisigScript.disassemble(witness) {
                return (MultisigWalletConfig.guessAddressFormat(witnessScript: witness, redeemScript: redeem),
                        parsed.requiredSignatures, parsed.totalSigners)
            }
            if let redeem, let parsed = try? MultisigScript.disassemble(redeem) {
                return (.p2sh, parsed.requiredSignatures, parsed.totalSigners)
            }
        }
        return nil
    }

    public func matchingMultisigWallet(wallets: [MultisigWalletConfig]) -> MultisigWalletConfig? {
        guard !wallets.isEmpty else { return nil }
        for index in inputs.indices {
            let script = inputs[index].first(type: 0x05)?.value ?? inputs[index].first(type: 0x04)?.value
            guard let script, let parsed = try? MultisigScript.disassemble(script) else { continue }
            let paths: [[UInt32]] = inputs[index].all(type: 0x06).compactMap { entry in
                guard let derivation = try? PSBTDerivation(entry: entry),
                      let xfp = MultisigWalletConfig.fingerprintValue(derivation.masterFingerprint.hexString.uppercased()) else {
                    return nil
                }
                return [xfp] + derivation.path.components
            }
            if let match = wallets.first(where: {
                $0.requiredSignatures == parsed.requiredSignatures
                    && $0.totalSigners == parsed.totalSigners
                    && (paths.isEmpty || $0.matchingSubpaths(paths))
            }) {
                return match
            }
        }
        return nil
    }

    /// Firmware `consider_inputs` only records the first 100 unique outpoints, so a duplicate
    /// among later unique inputs is not detected. 4cc0759 did not keep a stricter ColdcardCore check.
    private static let duplicateOutpointRecordLimit = 100

    private func hasFirmwareVisibleDuplicateInputs() -> Bool {
        var recorded = Set<Data>()
        for input in unsignedTransaction.inputs {
            var key = input.previousTxID
            key.appendUInt32LE(input.previousOutputIndex)
            if recorded.contains(key) { return true }
            if recorded.count < Self.duplicateOutpointRecordLimit {
                recorded.insert(key)
            }
        }
        return false
    }

    private func declaredSighash(in map: PSBTMap) throws -> UInt32 {
        guard let entry = map.first(type: 0x03) else { return 1 }
        guard entry.value.count == 4 else { throw PSBTError.malformed }
        var reader = ByteReader(entry.value)
        return try reader.readUInt32LE()
    }

    private func resolvedUTXO(index: Int) throws -> TransactionOutput {
        let map = inputs[index]
        // Prefer the complete previous transaction whenever supplied. This is
        // essential for legacy inputs and prevents a conflicting witness_utxo
        // from spoofing the amount or script shown during review.
        if let nonWitness = map.first(type: 0x00) {
            let previous = try BitcoinTransaction(data: nonWitness.value)
            let input = unsignedTransaction.inputs[index]
            guard input.previousTxID == Data(previous.txidHash.reversed()) else { throw PSBTError.transactionMismatch }
            guard Int(input.previousOutputIndex) < previous.outputs.count else { throw PSBTError.invalidUTXO }
            return previous.outputs[Int(input.previousOutputIndex)]
        }
        if let witness = map.first(type: 0x01) { return try TransactionOutput.parse(witness.value) }
        throw PSBTError.invalidUTXO
    }

    private enum OutputChangeResult {
        case notChange
        case change(path: String?)
        case fatal(String)
    }

    /// Firmware `psbtOutputProxy.validate` / change-output fraud (`shared/psbt.py`).
    private func analyzeChangeOutput(
        index: Int,
        script: Data,
        map: PSBTMap,
        root: HDKey,
        activeMultisig: MultisigWalletConfig?,
        disableMultisigChecks: Bool
    ) -> OutputChangeResult {
        let derivations = map.all(type: 0x02).compactMap { try? PSBTDerivation(entry: $0) }
        let ours = derivations.filter { derivationBelongs($0, to: root) }
        guard !ours.isEmpty else { return .notChange }
        let expectPubkey = derivations.count == 1 ? derivations[0].publicKey : nil
        let ourPath = ours.first?.path.description
        switch BitcoinScript.classify(script) {
        case .p2tr, .opReturn, .unknown:
            return .notChange
        case .p2pk(let pubkey):
            if pubkey != expectPubkey {
                return .fatal("Output#\(index): P2PK change output is fraudulent")
            }
            return .change(path: ourPath)
        case .p2sh(let scriptHash):
            return analyzeP2SHP2WSHChange(
                index: index, isSegwit: false, hashed: scriptHash, script: script,
                expectPubkey: expectPubkey, derivations: derivations, ourPath: ourPath,
                map: map, activeMultisig: activeMultisig, disableMultisigChecks: disableMultisigChecks
            )
        case .p2wsh(let hash):
            return analyzeP2SHP2WSHChange(
                index: index, isSegwit: true, hashed: hash, script: script,
                expectPubkey: expectPubkey, derivations: derivations, ourPath: ourPath,
                map: map, activeMultisig: activeMultisig, disableMultisigChecks: disableMultisigChecks
            )
        case .p2pkh(let hash), .p2wpkh(let hash):
            guard let expectPubkey else {
                return .fatal("Output#\(index): Change output is fraudulent")
            }
            if hash != BitcoinHash.hash160(expectPubkey) {
                return .fatal("Output#\(index): Change output is fraudulent")
            }
            return .change(path: ourPath)
        }
    }

    private func analyzeP2SHP2WSHChange(
        index: Int,
        isSegwit: Bool,
        hashed: Data,
        script: Data,
        expectPubkey: Data?,
        derivations: [PSBTDerivation],
        ourPath: String?,
        map: PSBTMap,
        activeMultisig: MultisigWalletConfig?,
        disableMultisigChecks: Bool
    ) -> OutputChangeResult {
        let redeem = map.first(type: 0x00)?.value
        let witness = map.first(type: 0x01)?.value
        if let expectPubkey {
            guard let redeem else {
                return .fatal("Missing redeem script for output #\(index)")
            }
            let wrapped = Data([0x00, 0x14]) + BitcoinHash.hash160(expectPubkey)
            let targetSPK = Data([0xa9, 0x14]) + BitcoinHash.hash160(wrapped) + Data([0x87])
            if !isSegwit, redeem.count == 22, redeem.starts(with: [0x00, 0x14]), script == targetSPK {
                let pkh = redeem.subdata(in: 2..<22)
                if pkh != BitcoinHash.hash160(expectPubkey) {
                    return .fatal("Output#\(index): Change output is fraudulent")
                }
                return .change(path: ourPath)
            }
            return .fatal("Output#\(index): Change output is fraudulent")
        }
        if redeem == nil && witness == nil {
            return .fatal("Missing redeem/witness script for multisig output #\(index)")
        }
        guard let wallet = activeMultisig else { return .notChange }
        if disableMultisigChecks { return .notChange }
        var format: MultisigAddressFormat = isSegwit ? .p2wsh : .p2sh
        if !isSegwit, let redeem, redeem.count == 34, redeem.starts(with: [0x00, 0x20]), witness != nil {
            format = .p2shP2wsh
        }
        if format != wallet.addressFormat { return .notChange }
        let scriptToCheck = witness ?? redeem
        guard let scriptToCheck else { return .notChange }
        do {
            try wallet.validateScript(scriptToCheck, derivations: derivations)
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .fatal("Output#\(index): P2WSH or P2SH change output script: \(detail)")
        }
        if isSegwit {
            guard let witness, SHA2.sha256(witness) == hashed else {
                return .fatal("Output#\(index): P2WSH witness script has wrong hash")
            }
            return .change(path: ourPath)
        }
        if let witness {
            let expectRedeem = Data([0x00, 0x20]) + SHA2.sha256(witness)
            if let redeem, expectRedeem != redeem {
                return .fatal("Output#\(index): P2SH-P2WSH redeem script provided, and doesn't match")
            }
            if BitcoinHash.hash160(expectRedeem) != hashed {
                return .fatal("Output#\(index): Change output is fraudulent")
            }
            return .change(path: ourPath)
        }
        if let redeem, BitcoinHash.hash160(redeem) != hashed {
            return .fatal("Output#\(index): Change output is fraudulent")
        }
        return .change(path: ourPath)
    }

    /// Firmware `consider_dangerous_change` (`shared/psbt.py`).
    private func troublesomeChangeWarnings(inputPaths: [[UInt32]],
                                           changePaths: [(index: Int, components: [UInt32])]) -> [String] {
        guard !inputPaths.isEmpty else { return [] }
        let lengths = Set(inputPaths.map(\.count))
        guard lengths.count == 1, let pathLen = lengths.first, pathLen > 2 else { return [] }
        func hardBits(_ path: [UInt32]) -> [Bool] {
            path.map { $0 & DerivationPath.hardened != 0 }
        }
        let pathPrefix = Array(inputPaths[0].dropLast(2))
        let idxMax = (inputPaths.compactMap { $0.last }.map { $0 & ~DerivationPath.hardened }.max() ?? 0) &+ 200
        let hardPattern = hardBits(inputPaths[0])
        var warnings: [String] = []
        for change in changePaths {
            let path = change.components
            let issue: String?
            if path.count != pathLen {
                issue = "has wrong path length (\(path.count) not \(pathLen))"
            } else if hardBits(path) != hardPattern {
                issue = "has different hardening pattern"
            } else if Array(path.prefix(pathPrefix.count)) != pathPrefix {
                issue = "goes to diff path prefix"
            } else if path.count >= 2, (path[path.count - 2] & ~DerivationPath.hardened) > 1 {
                issue = "2nd last component not 0 or 1"
            } else if let last = path.last, (last & ~DerivationPath.hardened) > idxMax {
                issue = "last component beyond reasonable gap"
            } else {
                issue = nil
            }
            if let issue {
                let got = DerivationPath(path).description
                let expectPrefix = DerivationPath(pathPrefix).description
                let hard2 = hardPattern.count >= 2 && hardPattern[hardPattern.count - 2] ? "'" : ""
                let hard1 = hardPattern.last == true ? "'" : ""
                warnings.append("Troublesome Change Outs: Output#\(change.index): \(issue): \(got) not \(expectPrefix)/{0~1}\(hard2)/{0~\(idxMax)}\(hard1) expected")
            }
        }
        return warnings
    }

    private func matchingDerivation(in map: PSBTMap, root: HDKey, type: UInt8 = 0x06) -> PSBTDerivation? {
        map.all(type: type).compactMap { try? PSBTDerivation(entry: $0) }.first { derivation in
            guard derivationBelongs(derivation, to: root),
                  let key = try? root.derived(path: derivation.path) else { return false }
            return key.publicKey == derivation.publicKey
        }
    }

    /// Firmware `parse_subpaths`: `here[0] == 0` is replaced with `my_xfp` and then treated as ours.
    private func derivationBelongs(_ derivation: PSBTDerivation, to root: HDKey) -> Bool {
        derivation.masterFingerprint == Self.zeroFingerprint || derivation.masterFingerprint == root.fingerprint
    }

    private static let zeroFingerprint = Data(repeating: 0, count: 4)

    private func hasZeroFingerprint(in map: PSBTMap, type: UInt8) -> Bool {
        map.all(type: type).compactMap { try? PSBTDerivation(entry: $0) }
            .contains { $0.masterFingerprint == Self.zeroFingerprint }
    }

    /// Native / wrapped / P2WSH / P2TR — firmware `inp.is_segwit` after `determine_my_signing_key`.
    private func inputIsSegwit(utxo: TransactionOutput, map: PSBTMap) -> Bool {
        switch BitcoinScript.classify(utxo.scriptPubKey) {
        case .p2wpkh, .p2wsh, .p2tr:
            return true
        case .p2sh:
            return witnessUTXOIsProvablySegwit(utxo: utxo, map: map)
        default:
            return false
        }
    }

    /// Firmware `add_segwit_utxos`: change outputs that carry a witness script.
    public func segwitChangeOutputs(markedChange: [Int]) -> [(index: Int, value: UInt64)] {
        markedChange.compactMap { index in
            guard outputs.indices.contains(index), unsignedTransaction.outputs.indices.contains(index),
                  outputs[index].first(type: 0x01) != nil else { return nil }
            return (index, unsignedTransaction.outputs[index].value)
        }
    }

    /// Firmware `witness_utxo_is_provably_segwit`.
    private func witnessUTXOIsProvablySegwit(utxo: TransactionOutput, map: PSBTMap) -> Bool {
        switch BitcoinScript.classify(utxo.scriptPubKey) {
        case .p2wpkh, .p2wsh, .p2tr:
            return true
        case .p2sh(let scriptHash):
            guard let redeem = map.first(type: 0x04)?.value else { return false }
            let wrappedKey = redeem.count == 22 && redeem.starts(with: [0x00, 0x14])
            let wrappedScript = redeem.count == 34 && redeem.starts(with: [0x00, 0x20])
            return (wrappedKey || wrappedScript) && BitcoinHash.hash160(redeem) == scriptHash
        default:
            return false
        }
    }

    private func validateDerivationDepth() throws {
        for map in inputs {
            for entry in map.all(type: 0x06) { _ = try PSBTDerivation(entry: entry) }
        }
        for map in outputs {
            for entry in map.all(type: 0x02) { _ = try PSBTDerivation(entry: entry) }
        }
    }

    private static func globalUInt32(_ map: PSBTMap, type: UInt8) throws -> UInt32? {
        guard let entry = map.first(type: type) else { return nil }
        guard entry.key.count == 1, entry.value.count == 4 else { throw PSBTError.malformed }
        var reader = ByteReader(entry.value)
        return try reader.readUInt32LE()
    }

    private static func globalInt32(_ map: PSBTMap, type: UInt8) throws -> Int32? {
        try globalUInt32(map, type: type).map { Int32(bitPattern: $0) }
    }

    private static func globalCompactSize(_ map: PSBTMap, type: UInt8) throws -> UInt64? {
        guard let entry = map.first(type: type) else { return nil }
        guard entry.key.count == 1, !entry.value.isEmpty else { throw PSBTError.malformed }
        var reader = ByteReader(entry.value)
        let value = try reader.readVarInt()
        guard reader.isAtEnd else { throw PSBTError.malformed }
        return value
    }

    private static func validateV0Maps(inputs: [PSBTMap], outputs: [PSBTMap]) throws {
        let v2InputTypes: Set<UInt8> = [0x0e, 0x0f, 0x10, 0x11, 0x12]
        for map in inputs {
            if map.entries.contains(where: { v2InputTypes.contains($0.type) }) { throw PSBTError.malformed }
        }
        for map in outputs {
            if map.first(type: 0x03) != nil || map.first(type: 0x04) != nil { throw PSBTError.malformed }
        }
    }

    private static func transactionFromV2Maps(version: Int32, lockTime: UInt32,
                                              inputs: [PSBTMap], outputs: [PSBTMap]) throws -> BitcoinTransaction {
        var txInputs: [TransactionInput] = []
        txInputs.reserveCapacity(inputs.count)
        for map in inputs {
            guard let txidEntry = map.first(type: 0x0e), txidEntry.key.count == 1, txidEntry.value.count == 32 else {
                throw PSBTError.malformed
            }
            guard let voutEntry = map.first(type: 0x0f), voutEntry.key.count == 1, voutEntry.value.count == 4 else {
                throw PSBTError.malformed
            }
            var voutReader = ByteReader(voutEntry.value)
            let vout = try voutReader.readUInt32LE()
            let sequence: UInt32
            if let seqEntry = map.first(type: 0x10) {
                guard seqEntry.key.count == 1, seqEntry.value.count == 4 else { throw PSBTError.malformed }
                var seqReader = ByteReader(seqEntry.value)
                sequence = try seqReader.readUInt32LE()
            } else {
                sequence = 0xffff_ffff
            }
            if let timeLock = map.first(type: 0x11) {
                guard timeLock.key.count == 1, timeLock.value.count == 4 else { throw PSBTError.malformed }
                var reader = ByteReader(timeLock.value)
                let value = try reader.readUInt32LE()
                guard value >= 500_000_000 else { throw PSBTError.malformed }
            }
            if let heightLock = map.first(type: 0x12) {
                guard heightLock.key.count == 1, heightLock.value.count == 4 else { throw PSBTError.malformed }
                var reader = ByteReader(heightLock.value)
                let value = try reader.readUInt32LE()
                guard value > 0, value < 500_000_000 else { throw PSBTError.malformed }
            }
            txInputs.append(TransactionInput(previousTxID: txidEntry.value, previousOutputIndex: vout, sequence: sequence))
        }
        var txOutputs: [TransactionOutput] = []
        txOutputs.reserveCapacity(outputs.count)
        for map in outputs {
            guard let amountEntry = map.first(type: 0x03), amountEntry.key.count == 1, amountEntry.value.count == 8 else {
                throw PSBTError.malformed
            }
            guard let scriptEntry = map.first(type: 0x04), scriptEntry.key.count == 1 else {
                throw PSBTError.malformed
            }
            var amountReader = ByteReader(amountEntry.value)
            let signedAmount = Int64(bitPattern: try amountReader.readUInt64LE())
            guard signedAmount >= 0 else { throw PSBTError.malformed }
            txOutputs.append(TransactionOutput(value: UInt64(signedAmount), scriptPubKey: scriptEntry.value))
        }
        return BitcoinTransaction(version: version, inputs: txInputs, outputs: txOutputs, lockTime: lockTime)
    }

    private func mapHasPartialSignature(_ map: PSBTMap) -> Bool {
        map.first(type: 0x02) != nil
    }
}

import Foundation

// Adapted from Coldcard transaction helpers that retain Bitcoin Core-derived
// MIT material. See ThirdParty/BitcoinCore-LICENSE.md and Docs/PROVENANCE.md.

public enum BitcoinTransactionError: Error, Equatable {
    case malformed
    case unsupportedSighash
    case inputIndexOutOfRange
    case outputIndexOutOfRange
}

public struct TransactionInput: Equatable, Codable, Sendable {
    public var previousTxID: Data      // serialized little-endian hash
    public var previousOutputIndex: UInt32
    public var scriptSig: Data
    public var sequence: UInt32
    public var witness: [Data]

    public init(previousTxID: Data, previousOutputIndex: UInt32, scriptSig: Data = Data(),
                sequence: UInt32 = 0xffff_ffff, witness: [Data] = []) {
        self.previousTxID = previousTxID
        self.previousOutputIndex = previousOutputIndex
        self.scriptSig = scriptSig
        self.sequence = sequence
        self.witness = witness
    }

    public var outpointData: Data {
        var result = previousTxID
        result.appendUInt32LE(previousOutputIndex)
        return result
    }
}

public struct TransactionOutput: Equatable, Codable, Sendable {
    public var value: UInt64
    public var scriptPubKey: Data

    public init(value: UInt64, scriptPubKey: Data) {
        self.value = value
        self.scriptPubKey = scriptPubKey
    }

    public func serialize() -> Data {
        var result = Data()
        result.appendUInt64LE(value)
        result.appendVarInt(UInt64(scriptPubKey.count))
        result.append(scriptPubKey)
        return result
    }

    public static func parse(_ data: Data) throws -> TransactionOutput {
        var reader = ByteReader(data)
        let value = try reader.readUInt64LE()
        let script = try reader.readVarData()
        guard reader.isAtEnd else { throw BitcoinTransactionError.malformed }
        return TransactionOutput(value: value, scriptPubKey: script)
    }
}

public struct BitcoinTransaction: Equatable, Codable, Sendable {
    public var version: Int32
    public var inputs: [TransactionInput]
    public var outputs: [TransactionOutput]
    public var lockTime: UInt32

    public init(version: Int32 = 2, inputs: [TransactionInput], outputs: [TransactionOutput], lockTime: UInt32 = 0) {
        self.version = version
        self.inputs = inputs
        self.outputs = outputs
        self.lockTime = lockTime
    }

    public init(data: Data) throws {
        var reader = ByteReader(data)
        self = try Self.parse(reader: &reader)
        guard reader.isAtEnd else { throw BitcoinTransactionError.malformed }
    }

    private static func parse(reader: inout ByteReader) throws -> BitcoinTransaction {
        let version = Int32(bitPattern: try reader.readUInt32LE())
        var hasWitness = false
        let markerOffset = reader.offset
        var inputCount = try reader.readVarInt()
        if inputCount == 0 {
            let flag = try reader.readByte()
            guard flag != 0 else { throw BitcoinTransactionError.malformed }
            hasWitness = true
            inputCount = try reader.readVarInt()
        } else {
            _ = markerOffset
        }
        guard inputCount <= 1_000_000 else { throw BitcoinTransactionError.malformed }
        var inputs: [TransactionInput] = []
        inputs.reserveCapacity(Int(inputCount))
        for _ in 0..<inputCount {
            let txid = try reader.read(32)
            let index = try reader.readUInt32LE()
            let script = try reader.readVarData()
            let sequence = try reader.readUInt32LE()
            inputs.append(TransactionInput(previousTxID: txid, previousOutputIndex: index, scriptSig: script, sequence: sequence))
        }
        let outputCount = try reader.readVarInt()
        guard outputCount <= 1_000_000 else { throw BitcoinTransactionError.malformed }
        var outputs: [TransactionOutput] = []
        outputs.reserveCapacity(Int(outputCount))
        for _ in 0..<outputCount {
            let value = try reader.readUInt64LE()
            let script = try reader.readVarData()
            outputs.append(TransactionOutput(value: value, scriptPubKey: script))
        }
        if hasWitness {
            for index in inputs.indices {
                let count = try reader.readVarInt()
                guard count <= 1_000_000 else { throw BitcoinTransactionError.malformed }
                var witness: [Data] = []
                witness.reserveCapacity(Int(count))
                for _ in 0..<count { witness.append(try reader.readVarData()) }
                inputs[index].witness = witness
            }
        }
        let lockTime = try reader.readUInt32LE()
        return BitcoinTransaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
    }

    public func serialize(includeWitness: Bool = true) -> Data {
        let useWitness = includeWitness && inputs.contains { !$0.witness.isEmpty }
        var result = Data()
        result.appendUInt32LE(UInt32(bitPattern: version))
        if useWitness { result.append(contentsOf: [0x00, 0x01]) }
        result.appendVarInt(UInt64(inputs.count))
        for input in inputs {
            result.append(input.previousTxID)
            result.appendUInt32LE(input.previousOutputIndex)
            result.appendVarInt(UInt64(input.scriptSig.count))
            result.append(input.scriptSig)
            result.appendUInt32LE(input.sequence)
        }
        result.appendVarInt(UInt64(outputs.count))
        for output in outputs { result.append(output.serialize()) }
        if useWitness {
            for input in inputs {
                result.appendVarInt(UInt64(input.witness.count))
                for item in input.witness {
                    result.appendVarInt(UInt64(item.count))
                    result.append(item)
                }
            }
        }
        result.appendUInt32LE(lockTime)
        return result
    }

    public var txidHash: Data { SHA2.doubleSHA256(serialize(includeWitness: false)) }
    public var txid: String { Data(txidHash.reversed()).hexString }
    public var weight: Int {
        let stripped = serialize(includeWitness: false).count
        let total = serialize(includeWitness: true).count
        return stripped * 4 + (total - stripped)
    }
    public var virtualSize: Int { (weight + 3) / 4 }

    public func legacySignatureHash(inputIndex: Int, scriptCode: Data, sighashType: UInt32) throws -> Data {
        guard inputs.indices.contains(inputIndex) else { throw BitcoinTransactionError.inputIndexOutOfRange }
        let base = sighashType & 0x1f
        guard [UInt32(1), 2, 3].contains(base) else { throw BitcoinTransactionError.unsupportedSighash }
        if base == 3 && inputIndex >= outputs.count {
            return Data([1]) + Data(repeating: 0, count: 31)
        }

        var transaction = self
        for index in transaction.inputs.indices { transaction.inputs[index].scriptSig = index == inputIndex ? scriptCode : Data() }
        transaction.inputs.indices.forEach { transaction.inputs[$0].witness = [] }

        if base == 2 { // NONE
            transaction.outputs = []
            for index in transaction.inputs.indices where index != inputIndex { transaction.inputs[index].sequence = 0 }
        } else if base == 3 { // SINGLE
            transaction.outputs = Array(transaction.outputs.prefix(inputIndex + 1))
            for index in 0..<inputIndex { transaction.outputs[index] = TransactionOutput(value: UInt64.max, scriptPubKey: Data()) }
            for index in transaction.inputs.indices where index != inputIndex { transaction.inputs[index].sequence = 0 }
        }

        if sighashType & 0x80 != 0 {
            transaction.inputs = [transaction.inputs[inputIndex]]
        }
        var preimage = transaction.serialize(includeWitness: false)
        preimage.appendUInt32LE(sighashType)
        return SHA2.doubleSHA256(preimage)
    }

    public func segwitV0SignatureHash(inputIndex: Int, scriptCode: Data, value: UInt64,
                                      sighashType: UInt32) throws -> Data {
        guard inputs.indices.contains(inputIndex) else { throw BitcoinTransactionError.inputIndexOutOfRange }
        let base = sighashType & 0x1f
        guard [UInt32(1), 2, 3].contains(base) else { throw BitcoinTransactionError.unsupportedSighash }
        let anyoneCanPay = sighashType & 0x80 != 0

        let hashPrevouts: Data
        if anyoneCanPay {
            hashPrevouts = Data(repeating: 0, count: 32)
        } else {
            var data = Data()
            for input in inputs { data.append(input.outpointData) }
            hashPrevouts = SHA2.doubleSHA256(data)
        }

        let hashSequence: Data
        if anyoneCanPay || base == 2 || base == 3 {
            hashSequence = Data(repeating: 0, count: 32)
        } else {
            var data = Data()
            for input in inputs { data.appendUInt32LE(input.sequence) }
            hashSequence = SHA2.doubleSHA256(data)
        }

        let hashOutputs: Data
        if base == 1 {
            var data = Data()
            for output in outputs { data.append(output.serialize()) }
            hashOutputs = SHA2.doubleSHA256(data)
        } else if base == 3 && inputIndex < outputs.count {
            hashOutputs = SHA2.doubleSHA256(outputs[inputIndex].serialize())
        } else {
            hashOutputs = Data(repeating: 0, count: 32)
        }

        let input = inputs[inputIndex]
        var preimage = Data()
        preimage.appendUInt32LE(UInt32(bitPattern: version))
        preimage.append(hashPrevouts)
        preimage.append(hashSequence)
        preimage.append(input.outpointData)
        preimage.appendVarInt(UInt64(scriptCode.count))
        preimage.append(scriptCode)
        preimage.appendUInt64LE(value)
        preimage.appendUInt32LE(input.sequence)
        preimage.append(hashOutputs)
        preimage.appendUInt32LE(lockTime)
        preimage.appendUInt32LE(sighashType)
        return SHA2.doubleSHA256(preimage)
    }
}

public enum BitcoinScript {
    public enum Kind: Equatable, Sendable {
        case p2pkh(Data)
        case p2sh(Data)
        case p2wpkh(Data)
        case p2wsh(Data)
        case p2tr(Data)
        case p2pk(Data)
        case opReturn
        case unknown
    }

    public static func classify(_ script: Data) -> Kind {
        if script.count == 35, script.first == 0x21, script.last == 0xac {
            return .p2pk(script.subdata(in: 1..<34))
        }
        if script.count == 67, script.first == 0x41, script.last == 0xac {
            return .p2pk(script.subdata(in: 1..<66))
        }
        if script.count == 25, script.starts(with: [0x76, 0xa9, 0x14]), script.suffix(2) == Data([0x88, 0xac]) {
            return .p2pkh(script.subdata(in: 3..<23))
        }
        if script.count == 23, script.starts(with: [0xa9, 0x14]), script.last == 0x87 {
            return .p2sh(script.subdata(in: 2..<22))
        }
        if script.count == 22, script.starts(with: [0x00, 0x14]) { return .p2wpkh(script.subdata(in: 2..<22)) }
        if script.count == 34, script.starts(with: [0x00, 0x20]) { return .p2wsh(script.subdata(in: 2..<34)) }
        if script.count == 34, script.starts(with: [0x51, 0x20]) { return .p2tr(script.subdata(in: 2..<34)) }
        if script.first == 0x6a { return .opReturn }
        return .unknown
    }

    /// Firmware `chains.op_return`: payload bytes, empty for bare/`OP_0`, nil if not a simple OP_RETURN.
    public static func opReturnPayload(_ script: Data) -> Data? {
        guard script.first == 0x6a else { return nil }
        if script.count == 1 { return Data() }
        var index = 1
        let opcode = script[index]
        index += 1
        if opcode == 0 { return index == script.count ? Data() : nil }
        let length: Int
        if opcode < 0x4c {
            length = Int(opcode)
        } else if opcode == 0x4c, index < script.count {
            length = Int(script[index]); index += 1
        } else {
            return nil
        }
        guard index + length == script.count else { return nil }
        return script.subdata(in: index..<(index + length))
    }

    public static func address(for script: Data, network: BitcoinNetwork) -> String? {
        switch classify(script) {
        case .p2pkh(let hash): return Base58.checkEncode(version: Data([network.p2pkhPrefix]), payload: hash)
        case .p2sh(let hash): return Base58.checkEncode(version: Data([network.p2shPrefix]), payload: hash)
        case .p2wpkh(let hash): return try? Bech32.encodeSegwit(hrp: network.bech32HRP, version: 0, program: hash)
        case .p2wsh(let hash): return try? Bech32.encodeSegwit(hrp: network.bech32HRP, version: 0, program: hash)
        case .p2tr(let key): return try? Bech32.encodeSegwit(hrp: network.bech32HRP, version: 1, program: key)
        case .p2pk: return nil
        case .opReturn: return "OP_RETURN"
        case .unknown: return nil
        }
    }

    public static func p2pkhScriptCode(pubkeyHash: Data) -> Data {
        Data([0x76, 0xa9, 0x14]) + pubkeyHash + Data([0x88, 0xac])
    }

    public static func push(_ data: Data) -> Data {
        if data.count < 0x4c { return Data([UInt8(data.count)]) + data }
        if data.count <= 0xff { return Data([0x4c, UInt8(data.count)]) + data }
        var result = Data([0x4d])
        result.append(UInt8(data.count & 0xff))
        result.append(UInt8((data.count >> 8) & 0xff))
        result.append(data)
        return result
    }
}

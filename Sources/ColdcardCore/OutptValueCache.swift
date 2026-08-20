import Foundation

/// Firmware `shared/history.py` `OutptValueCache` (`ovc` settings key).
///
/// Segwit input amounts are recorded the first time they are seen. A later PSBT
/// that claims a different amount for the same prevout is `IncorrectUTXOAmount`.
public struct OutptValueCache: Equatable, Sendable {
    public static let savedLimit = 30
    public static let memoryLimit = 128
    public static let encodedKeyLength = 20

    public var entries: [String]

    public init(entries: [String] = []) {
        self.entries = entries
    }

    public mutating func verifyAmount(
        prevout: Data,
        amount: UInt64,
        inputIndex: Int,
        displayUnits: DisplayUnits,
        network: BitcoinNetwork
    ) throws {
        if let expected = fetchAmount(prevout) {
            if expected != amount {
                throw OutptValueCacheError.incorrectAmount(
                    Self.incorrectAmountMessage(
                        inputIndex: inputIndex,
                        expected: expected,
                        claimed: amount,
                        displayUnits: displayUnits,
                        network: network
                    )
                )
            }
            return
        }
        add(prevout: prevout, amount: amount)
    }

    public mutating func add(prevout: Data, amount: UInt64) {
        let key = Self.encodeKey(prevout)
        if entries.count >= Self.memoryLimit {
            entries.removeFirst()
        }
        entries.append(key + Self.encodeValue(prevout: prevout, amount: amount))
    }

    /// Firmware persists `runtime_cache[-HISTORY_SAVED:]` as settings `ovc`.
    public var persistedEntries: [String] {
        Array(entries.suffix(Self.savedLimit))
    }

    /// Firmware `add_segwit_utxos` / `add_segwit_utxos_finalize`.
    public mutating func addFinalizedSegwitChange(txidHash: Data, outputs: [(index: Int, value: UInt64)]) {
        for output in outputs {
            var prevout = txidHash
            prevout.appendUInt32LE(UInt32(output.index))
            add(prevout: prevout, amount: output.value)
        }
    }

    public func fetchAmount(_ prevout: Data) -> UInt64? {
        let key = Self.encodeKey(prevout)
        for entry in entries where entry.count >= Self.encodedKeyLength && entry.hasPrefix(key) {
            return Self.decodeValue(prevout: prevout, text: String(entry.dropFirst(Self.encodedKeyLength)))
        }
        return nil
    }

    /// Firmware `IncorrectUTXOAmount`: `Input#%d: Expected %s but PSBT claims %s %s`.
    public static func incorrectAmountMessage(
        inputIndex: Int,
        expected: UInt64,
        claimed: UInt64,
        displayUnits: DisplayUnits,
        network: BitcoinNetwork
    ) -> String {
        let (expectedText, units) = displayUnits.render(expected, network: network, unpad: true)
        let (claimedText, _) = displayUnits.render(claimed, network: network, unpad: true)
        return "Input#\(inputIndex): Expected \(expectedText) but PSBT claims \(claimedText) \(units)"
    }

    public static func encodeKey(_ prevout: Data) -> String {
        let digest = SHA2.sha256(Data("OutptValueCache".utf8) + prevout)
        return base64NoPad(digest.prefix(15))
    }

    public static func encodeValue(prevout: Data, amount: UInt64) -> String {
        let xor = Data(prevout.prefix(8))
        var packed = Data()
        packed.appendUInt64LE(amount)
        let mixed = Data(zip(xor, packed).map { $0 ^ $1 })
        return base64NoPad(mixed)
    }

    public static func decodeValue(prevout: Data, text: String) -> UInt64? {
        guard let mixed = Data(base64Encoded: text + "="), mixed.count == 8 else { return nil }
        let xor = Data(prevout.prefix(8))
        let packed = Data(zip(xor, mixed).map { $0 ^ $1 })
        var reader = ByteReader(packed)
        return try? reader.readUInt64LE()
    }

    private static func base64NoPad(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}

public enum OutptValueCacheError: Error, Equatable, Sendable {
    case incorrectAmount(String)
}

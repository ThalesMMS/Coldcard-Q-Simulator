import Foundation

public enum DemoPSBT {
    public static func make(root: HDKey, inputValue: UInt64 = 100_000, fee: UInt64 = 2_000) throws -> PSBT {
        let inputPath = DerivationPath.account(type: .nativeSegwit, network: root.network).appending(0).appending(0)
        let inputKey = try root.derived(path: inputPath)
        let changePath = DerivationPath.account(type: .nativeSegwit, network: root.network).appending(1).appending(0)
        let changeKey = try root.derived(path: changePath)
        let utxo = TransactionOutput(value: inputValue,
                                     scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: inputKey.publicKey, type: .nativeSegwit))
        let output = TransactionOutput(value: inputValue - min(inputValue, fee),
                                       scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: changeKey.publicKey, type: .nativeSegwit))
        let fakeHash = SHA2.sha256(Data("Coldcard Q Simulator demonstration prevout".utf8))
        let transaction = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(fakeHash.reversed()), previousOutputIndex: 0)],
                                             outputs: [output])
        let inputDerivation = PSBTDerivation(publicKey: inputKey.publicKey, masterFingerprint: root.fingerprint, path: inputPath)
        let outputDerivation = PSBTDerivation(publicKey: changeKey.publicKey, masterFingerprint: root.fingerprint, path: changePath)
        let inputMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + inputKey.publicKey, value: inputDerivation.encodedValue)
        ])
        let outputMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x02]) + changeKey.publicKey, value: outputDerivation.encodedValue)
        ])
        return try PSBT(unsignedTransaction: transaction, inputs: [inputMap], outputs: [outputMap])
    }
}

import Foundation
import Testing
@testable import ColdcardCore

@Test func doneSigningNounsMatchFirmwareAuth() {
    #expect(DoneSigning.noun(isComplete: true, isBIP322: false) == "Finalized TX ready for broadcast")
    #expect(DoneSigning.noun(isComplete: false, isBIP322: false) == "Partly Signed PSBT")
    #expect(DoneSigning.noun(isComplete: false, isBIP322: true) == "Signed BIP-322 PSBT")
    #expect(DoneSigning.noun(isComplete: true, isBIP322: true) == "Signed BIP-322 PSBT")
}

@Test func doneSigningBaseNameStripsOnlyLastExtension() {
    #expect(DoneSigning.baseName(from: nil) == "recent-txn")
    #expect(DoneSigning.baseName(from: "") == "recent-txn")
    #expect(DoneSigning.baseName(from: "incoming.psbt") == "incoming")
    #expect(DoneSigning.baseName(from: "foo.psbt.backup.psbt") == "foo.psbt.backup")
    #expect(DoneSigning.baseName(from: "noext") == "noext")
    #expect(DoneSigning.baseName(from: "/sd/dir/wallet.psbt") == "wallet")
}

@Test func doneSigningPSBTFilenamesMatchCompleteBranch() {
    #expect(DoneSigning.psbtFilename(base: "incoming", isComplete: true) == "incoming-signed.psbt")
    #expect(DoneSigning.psbtFilename(base: "incoming-part", isComplete: true) == "incoming-part-signed.psbt")
    #expect(DoneSigning.psbtFilename(base: "incoming-part", isComplete: false) == "incoming-part.psbt")
    #expect(DoneSigning.psbtFilename(base: "incoming", isComplete: false) == "incoming-part.psbt")
    #expect(DoneSigning.psbtFilename(base: "foo-part-extra", isComplete: false) == "foo-extra-part.psbt")
}

@Test func doneSigningTxnFilenamesHonorDeletePSBTs() {
    #expect(DoneSigning.txnFilename(base: "incoming", txid: "ab", deleteAfter: false) == "incoming-final.txn")
    #expect(DoneSigning.txnFilename(base: "incoming", txid: "deadbeef", deleteAfter: true) == "deadbeef.txn")
}

@Test func doneSigningSaveStoryWritesBothFilesAndOmitsPSBTWhenDeleted() {
    let both = DoneSigning.saveStory(psbtFilename: "a-signed.psbt", txnFilename: "a-final.txn")
    #expect(both == "Updated PSBT is:\n\na-signed.psbt\n\nFinalized transaction (ready for broadcast):\n\na-final.txn")

    let part = DoneSigning.saveStory(psbtFilename: "a-part.psbt", txnFilename: nil)
    #expect(part == "Updated PSBT is:\n\na-part.psbt")
    #expect(!part.contains("Finalized transaction"))

    let deleted = DoneSigning.saveStory(psbtFilename: nil, txnFilename: "txid.txn")
    #expect(deleted == "Finalized transaction (ready for broadcast):\n\ntxid.txn")
    #expect(!deleted.contains("Updated PSBT is:"))
}

@Test func doneSigningIntroAndQRCaptionUseTxidOrNoun() {
    #expect(DoneSigning.txidIntro("abc") == "TXID:\nabc")
    #expect(DoneSigning.qrCaption(txid: "abc", noun: "Partly Signed PSBT") == "abc")
    #expect(DoneSigning.qrCaption(txid: nil, noun: "Partly Signed PSBT") == "Partly Signed PSBT")
    #expect(DoneSigning.plainQRByteLimit == 920)
    #expect(DoneSigning.usesPlainHexQR(byteCount: 920))
    #expect(!DoneSigning.usesPlainHexQR(byteCount: 921))
}

@Test func doneSigningRemainingSignaturesAndCardErrorsMatchFirmware() {
    #expect(DoneSigning.remainingSignaturesNeeded(1) == "1 more signature is still required.")
    #expect(DoneSigning.remainingSignaturesNeeded(2) == "2 more signatures are still required.")
    #expect(DoneSigning.signaturesStillNeeded(required: 2, total: 3, stillNeededAmongWallet: 2) == 1)
    #expect(DoneSigning.needCard == "Need a card!\n\n")
    #expect(DoneSigning.failedToWrite("boom") == "Failed to write!\n\nboom\n\n")
    #expect(DoneSigning.noPSBTsFound == "No PSBTs found. Need to have '.psbt' suffix.")
    #expect(DoneSigning.signedTitle == "PSBT Signed")
    #expect(DoneSigning.pushedTitle == "TX Pushed")
    #expect(DoneSigning.sentByTeleportTitle == "Sent by Teleport")
    #expect(DoneSigning.failedToTeleportTitle == "Failed to Teleport")
    #expect(DoneSigning.offerKT == "use Key Teleport to send PSBT to other co-signers")
    #expect(DoneSigning.txidQRHint == "for QR Code of TXID")
}

@Test func doneSigningBatchImportPromptOmitsNFCAndQR() {
    let prompt = FirmwareImportPrompt.qImportPrompt(
        title: "PSBTs",
        slotBOnly: false,
        virtualDiskEnabled: false,
        nfcEnabled: false,
        includeQR: false
    )
    #expect(prompt == "Press (1) to import PSBTs from SD Card, (B) for lower slot.")
    #expect(!prompt.contains("NFC"))
    #expect(!prompt.contains("QR"))
}

@Test func doneSigningPostSignExportPromptIncludesTxidKeyAndKT() {
    let prompt = ExportPromptBuilder.prompt(
        whatItIs: "Finalized TX ready for broadcast",
        dualSDSlots: true,
        virtualDiskEnabled: false,
        nfcEnabled: true,
        qrEnabled: true,
        qwerty: true,
        key6: DoneSigning.txidQRHint,
        offerKT: nil,
        forcePrompt: true
    )
    #expect(prompt == "Press (1) to save Finalized TX ready for broadcast to SD Card, (B) for lower slot, press NFC to share via NFC, QR to show QR code, (6) for QR Code of TXID.")

    let partial = ExportPromptBuilder.prompt(
        whatItIs: "Partly Signed PSBT",
        dualSDSlots: true,
        virtualDiskEnabled: false,
        nfcEnabled: false,
        qrEnabled: true,
        qwerty: true,
        offerKT: DoneSigning.offerKT,
        forcePrompt: true
    )
    #expect(partial?.contains("(T) to use Key Teleport to send PSBT to other co-signers") == true)
}

@Test func doneSigningExplorerTitlesAndHintsMatchQFirmware() {
    #expect(DoneSigning.outputTitle(offset: 0, endExclusive: 10) == "0-9")
    #expect(DoneSigning.outputTitle(offset: 3, endExclusive: 13) == "3-12")
    #expect(DoneSigning.startIdxPrompt(maxIndex: 11) == "Start Idx (0-11):")
    #expect(DoneSigning.inputQRLabels == ["TXID", "UTXO ADDR"])
    #expect(!DoneSigning.qExplorerHints(hasNext: true, hasPrev: false, canGoto: true).contains("(4)"))
    #expect(DoneSigning.qExplorerHints(hasNext: true, hasPrev: true, canGoto: true)
            == "Press RIGHT to see next group, LEFT to go back, (2) to go to index. CANCEL to quit.")
}

@Test func doneSigningFullySignedIsMOfNNotAnyPartial() {
    #expect(DoneSigning.inputFullySigned(partialSignatureCount: 1, requiredM: 2, subpathCount: 3) == false)
    #expect(DoneSigning.inputFullySigned(partialSignatureCount: 2, requiredM: 2, subpathCount: 3) == true)
    #expect(DoneSigning.inputFullySigned(partialSignatureCount: 1, requiredM: nil, subpathCount: 1) == true)
    #expect(DoneSigning.inputFullySigned(partialSignatureCount: 1, requiredM: nil, subpathCount: 2) == false)
}

@Test func doneSigningOurKeyLabelAndSighashMatchFirmware() throws {
    let path = try DerivationPath("m/84h/1h/0h/0/0")
    #expect(DoneSigning.ourKeyLabel(xfp: "0F056943", path: path) == "0F056943/84h/1h/0h/0/0")
    #expect(DoneSigning.sighashNote(1) == nil)
    #expect(DoneSigning.sighashNote(2) == "sighash: NONE")
    #expect(DoneSigning.sighashNote(0x81) == "sighash: ALL|ANYONECANPAY")
    #expect(DoneSigning.sighashNote(0x2a) == "sighash: 0x2a (non-standard)")
}

@Test func doneSigningPickFilenameSkipsExistingLikeCardSlot() {
    #expect(DoneSigning.pickFilename("foo.psbt", existing: []) == "foo.psbt")
    #expect(DoneSigning.pickFilename("foo.psbt", existing: ["foo.psbt"]) == "foo-2.psbt")
    #expect(DoneSigning.pickFilename("foo.psbt", existing: ["foo.psbt", "foo-2.psbt"]) == "foo-3.psbt")
    #expect(DoneSigning.pickFilename("foo.psbt", existing: ["foo.psbt"], overwrite: true) == "foo.psbt")
}

@Test func doneSigningIsCompleteUsesMultisigThresholdNotExtraction() throws {
    let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    let root = try HDKey(seed: mnemonic.seed(passphrase: ""), network: .testnet)
    let path = try DerivationPath("m/84h/1h/0h/0/0")
    let child = try root.derived(path: path)
    let utxo = TransactionOutput(
        value: 100_000,
        scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit)
    )
    let unsigned = BitcoinTransaction(
        inputs: [TransactionInput(previousTxID: Data(repeating: 0x11, count: 32), previousOutputIndex: 0)],
        outputs: [TransactionOutput(value: 98_000, scriptPubKey: Data([0x6a]))]
    )
    let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
    let unsignedMap = PSBTMap(entries: [
        PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
        PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
    ])
    let unsignedPSBT = try PSBT(unsignedTransaction: unsigned, inputs: [unsignedMap], outputs: [PSBTMap()])
    #expect(!unsignedPSBT.isComplete())

    let signed = unsignedPSBT.signed(using: root).psbt
    #expect(signed.isComplete())

    var p2wsh = unsignedMap
    p2wsh.set(type: 0x05, value: Data([0x00]))
    p2wsh.set(type: 0x01, value: TransactionOutput(value: 100_000, scriptPubKey: Data([0x00, 0x20]) + SHA2.sha256(Data([0x00]))).serialize())
    p2wsh.set(type: 0x02, keyData: child.publicKey, value: Data([0x30, 0x01]))
    p2wsh.set(type: 0x02, keyData: Data(repeating: 0x02, count: 33), value: Data([0x30, 0x02]))
    let completeMultisig = try PSBT(unsignedTransaction: unsigned, inputs: [p2wsh], outputs: [PSBTMap()])
    #expect(completeMultisig.isComplete(requiredSignatures: 2))
    #expect((try? completeMultisig.extractedTransaction()) == nil)

    let second = try root.derived(path: DerivationPath("m/84h/1h/0h/0/1"))
    var realP2WSH = unsignedMap
    let script = Data([0x52, 0x21]) + child.publicKey + Data([0x21]) + second.publicKey + Data([0x52, 0xae])
    realP2WSH.set(type: 0x05, value: script)
    realP2WSH.set(
        type: 0x01,
        value: TransactionOutput(value: 100_000, scriptPubKey: Data([0x00, 0x20]) + SHA2.sha256(script)).serialize()
    )
    realP2WSH.set(type: 0x02, keyData: child.publicKey, value: Data([0x30, 0x01]))
    realP2WSH.set(type: 0x02, keyData: second.publicKey, value: Data([0x30, 0x02]))
    let extractable = try PSBT(unsignedTransaction: unsigned, inputs: [realP2WSH], outputs: [PSBTMap()])
    #expect(extractable.isComplete(requiredSignatures: 2))
    let finalized = try extractable.extractedTransaction()
    #expect(finalized.inputs[0].witness.count == 4)
    #expect(DoneSigning.psbtFilename(base: "incoming", isComplete: extractable.isComplete(requiredSignatures: 2))
            == "incoming-signed.psbt")
}

import XCTest
@testable import ColdcardCore

final class PSBTTests: XCTestCase {
    private let mnemonicPhrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    func testNativeSegwitPSBTRoundTripAndSigning() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let destination = try BitcoinAddress.derive(root: root, type: .nativeSegwit, change: true, index: 1)
        let unsigned = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(repeating: 0x11, count: 32), previousOutputIndex: 0)],
                                          outputs: [TransactionOutput(value: 98_000, scriptPubKey: try Data(hex: destination.scriptPubKeyHex))])
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let inputMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [inputMap], outputs: [PSBTMap()])
        let reparsed = try PSBT(data: psbt.serialize())
        XCTAssertEqual(reparsed, psbt)
        let review = reparsed.review(root: root)
        XCTAssertEqual(review.fee, 2_000)
        XCTAssertEqual(review.signableInputCount, 1)

        let result = reparsed.signed(using: root)
        XCTAssertEqual(result.signedInputCount, 1)
        let signed = try PSBT(data: result.data)
        let partial = try XCTUnwrap(signed.inputs[0].first(type: 0x02))
        XCTAssertEqual(partial.keyData, child.publicKey)
        XCTAssertEqual(partial.value.last, 1)
        let der = Data(partial.value.dropLast())
        let hash = try unsigned.segwitV0SignatureHash(inputIndex: 0,
                                                       scriptCode: BitcoinScript.p2pkhScriptCode(pubkeyHash: BitcoinHash.hash160(child.publicKey)),
                                                       value: utxo.value, sighashType: 1)
        XCTAssertTrue(Secp256k1.verify(hash: hash, derSignature: der, publicKey: child.publicKey))
    }

    func testWrappedSegwitSigning() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/49'/1'/0'/0/2")
        let child = try root.derived(path: path)
        let redeem = BitcoinAddress.redeemScriptForWrappedSegwit(publicKey: child.publicKey)
        let utxo = TransactionOutput(value: 80_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .wrappedSegwit))
        let unsigned = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(repeating: 0x22, count: 32), previousOutputIndex: 1)],
                                          outputs: [TransactionOutput(value: 79_000, scriptPubKey: Data([0x6a]))])
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x04]), value: redeem),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        XCTAssertEqual(psbt.signed(using: root).signedInputCount, 1)
    }

    func testLegacyRequiresFullPreviousTransactionAndSigns() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/44'/1'/0'/0/3")
        let child = try root.derived(path: path)
        let previousOutput = TransactionOutput(value: 50_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .legacy))
        let previous = BitcoinTransaction(version: 1,
                                          inputs: [TransactionInput(previousTxID: Data(repeating: 0, count: 32), previousOutputIndex: UInt32.max,
                                                                    scriptSig: Data([0x01, 0x01]))],
                                          outputs: [previousOutput])
        let unsignedInput = TransactionInput(previousTxID: Data(previous.txidHash.reversed()), previousOutputIndex: 0)
        let unsigned = BitcoinTransaction(inputs: [unsignedInput], outputs: [TransactionOutput(value: 49_000, scriptPubKey: Data([0x6a]))])
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x00]), value: previous.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        XCTAssertEqual(psbt.signed(using: root).signedInputCount, 1)
    }


    func testLegacyPrefersNonWitnessUTXOOverSpoofedWitnessUTXO() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/44'/1'/0'/0/4")
        let child = try root.derived(path: path)
        let realOutput = TransactionOutput(value: 50_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .legacy))
        let previous = BitcoinTransaction(version: 1,
                                          inputs: [TransactionInput(previousTxID: Data(repeating: 0, count: 32), previousOutputIndex: UInt32.max,
                                                                    scriptSig: Data([0x01, 0x02]))],
                                          outputs: [realOutput])
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(previous.txidHash.reversed()), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 49_000, scriptPubKey: Data([0x6a]))]
        )
        let spoofedWitness = TransactionOutput(value: 5_000_000, scriptPubKey: realOutput.scriptPubKey)
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x00]), value: previous.serialize()),
            PSBTEntry(key: Data([0x01]), value: spoofedWitness.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        let review = psbt.review(root: root)
        XCTAssertEqual(review.totalInput, 50_000)
        XCTAssertEqual(review.fee, 1_000)
        XCTAssertEqual(psbt.signed(using: root).signedInputCount, 1)
    }

    func testDangerousSighashIsBlockedByDefault() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/5")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 60_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let unsigned = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(repeating: 0x33, count: 32), previousOutputIndex: 0)],
                                          outputs: [TransactionOutput(value: 59_000, scriptPubKey: Data([0x6a]))])
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        var sighashSingle = Data(); sighashSingle.appendUInt32LE(3)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x03]), value: sighashSingle),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        let review = psbt.review(root: root)
        XCTAssertEqual(review.signableInputCount, 0)
        XCTAssertTrue(review.sighashBlocked)
        XCTAssertEqual(review.fatalIssue, "Sighash SINGLE is not allowed as some outputs could be changed.")
        let signed = psbt.signed(using: root)
        XCTAssertEqual(signed.signedInputCount, 0)
        XCTAssertTrue(signed.inputs[0].message.contains("SIGHASH"))
    }

    func testOutputDerivationCannotFalselyLabelChange() throws {
        let root = try rootKey()
        let inputPath = try DerivationPath("m/84'/1'/0'/0/6")
        let inputKey = try root.derived(path: inputPath)
        let utxo = TransactionOutput(value: 70_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: inputKey.publicKey, type: .nativeSegwit))
        let changePath = try DerivationPath("m/84'/1'/0'/1/0")
        let changeKey = try root.derived(path: changePath)
        let foreignScript = Data([0x00, 0x14]) + Data(repeating: 0x42, count: 20)
        let unsigned = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(repeating: 0x44, count: 32), previousOutputIndex: 0)],
                                          outputs: [TransactionOutput(value: 69_000, scriptPubKey: foreignScript)])
        let inputDerivation = PSBTDerivation(publicKey: inputKey.publicKey, masterFingerprint: root.fingerprint, path: inputPath)
        let outputDerivation = PSBTDerivation(publicKey: changeKey.publicKey, masterFingerprint: root.fingerprint, path: changePath)
        let inputMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + inputKey.publicKey, value: inputDerivation.encodedValue)
        ])
        let outputMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x02]) + changeKey.publicKey, value: outputDerivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [inputMap], outputs: [outputMap])
        let review = psbt.review(root: root)
        XCTAssertFalse(review.outputs[0].isChange)
        XCTAssertEqual(review.fatalIssue, "Output#0: Change output is fraudulent")
    }


    func testDuplicateOutpointIsRejected() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/7")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 40_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let duplicated = TransactionInput(previousTxID: Data(repeating: 0x55, count: 32), previousOutputIndex: 2)
        let unsigned = BitcoinTransaction(inputs: [duplicated, duplicated],
                                          outputs: [TransactionOutput(value: 79_000, scriptPubKey: Data([0x6a]))])
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map, map], outputs: [PSBTMap()])
        let review = psbt.review(root: root)
        XCTAssertEqual(review.signableInputCount, 0)
        XCTAssertEqual(review.fatalIssue, "Duplicate inputs")
        XCTAssertEqual(psbt.signed(using: root).signedInputCount, 0)
    }

    func testSighashNoneBlockedByDefaultSignedInWarnMode() throws {
        let root = try rootKey()
        let (psbt, child, utxo, unsigned) = try sighashFixture(root: root, sighash: 2)

        let blocked = psbt.review(root: root, sighashChecks: true)
        XCTAssertTrue(blocked.sighashBlocked)
        XCTAssertEqual(blocked.signableInputCount, 0)
        XCTAssertEqual(blocked.fatalIssue, "Sighash NONE is not allowed as funds could be going anywhere.")
        XCTAssertEqual(psbt.signed(using: root, sighashChecks: true).signedInputCount, 0)

        let warned = psbt.review(root: root, sighashChecks: false)
        XCTAssertFalse(warned.sighashBlocked)
        XCTAssertEqual(warned.signableInputCount, 1)
        XCTAssertTrue(warned.warnings.contains("Danger: Destination address can be changed after signing (sighash NONE)."))

        let result = psbt.signed(using: root, sighashChecks: false)
        XCTAssertEqual(result.signedInputCount, 1)
        let partial = try XCTUnwrap(PSBT(data: result.data).inputs[0].first(type: 0x02))
        XCTAssertEqual(partial.value.last, 2)
        let hash = try unsigned.segwitV0SignatureHash(inputIndex: 0,
                                                      scriptCode: BitcoinScript.p2pkhScriptCode(pubkeyHash: BitcoinHash.hash160(child.publicKey)),
                                                      value: utxo.value, sighashType: 2)
        XCTAssertTrue(Secp256k1.verify(hash: hash, derSignature: Data(partial.value.dropLast()), publicKey: child.publicKey))
    }

    func testSighashAllAnyoneCanPaySignsInBlockModeWithCaution() throws {
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 0x81)
        let review = psbt.review(root: root, sighashChecks: true)
        XCTAssertFalse(review.sighashBlocked)
        XCTAssertEqual(review.signableInputCount, 1)
        XCTAssertTrue(review.warnings.contains("Caution: Some inputs have unusual SIGHASH values not used in typical cases."))
        XCTAssertEqual(psbt.signed(using: root, sighashChecks: true).signedInputCount, 1)
    }

    func testTroublesomeChangeWarnsOnGapAndWrongChangeBranch() throws {
        let root = try rootKey()
        let inPath = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: inPath)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let farChange = try BitcoinAddress.derive(root: root, type: .nativeSegwit, change: false, index: 500)
        let farKey = try root.derived(path: try DerivationPath("m/84'/1'/0'/0/500"))
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x44, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: try Data(hex: farChange.scriptPubKeyHex))]
        )
        let inMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: inPath).encodedValue)
        ])
        let outMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x02]) + farKey.publicKey, value: PSBTDerivation(publicKey: farKey.publicKey, masterFingerprint: root.fingerprint, path: try DerivationPath("m/84'/1'/0'/0/500")).encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [inMap], outputs: [outMap])
        let review = psbt.review(root: root)
        XCTAssertTrue(review.outputs[0].isChange)
        XCTAssertTrue(review.warnings.contains(where: { $0.contains("Troublesome Change Outs") && $0.contains("beyond reasonable gap") }))
    }

    func testZeroFingerprintDerivationIsTreatedAsOursAndSigns() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/8")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let unsigned = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(repeating: 0x66, count: 32), previousOutputIndex: 0)],
                                          outputs: [TransactionOutput(value: 98_000, scriptPubKey: Data([0x6a]))])
        let zeroXFP = Data(repeating: 0, count: 4)
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: zeroXFP, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        let review = psbt.review(root: root)
        XCTAssertEqual(review.signableInputCount, 1)
        XCTAssertNil(review.fatalIssue)
        XCTAssertTrue(review.warnings.contains("Zero XFP: Assuming XFP of zero should be replaced by correct XFP"))
        XCTAssertEqual(psbt.signed(using: root).signedInputCount, 1)
    }

    func testPSBTPathDeeperThanMaxDepthIsRejected() throws {
        let root = try rootKey()
        // parse_subpaths counts XFP + indexes, so 12 path components is too deep (13 uint32s).
        let deep = DerivationPath(Array(repeating: UInt32(0), count: DerivationPath.maxDepth))
        let child = try root.derived(path: deep)
        let utxo = TransactionOutput(value: 50_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let unsigned = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(repeating: 0x77, count: 32), previousOutputIndex: 0)],
                                          outputs: [TransactionOutput(value: 49_000, scriptPubKey: Data([0x6a]))])
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: deep)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        XCTAssertThrowsError(try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])) { error in
            XCTAssertEqual(error as? PSBTError, .pathTooDeep)
        }
    }

    func testNativeSegwitWitnessUTXOStillHasFee() throws {
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 1)
        let review = psbt.review(root: root)
        XCTAssertEqual(review.fee, 2_000)
        XCTAssertFalse(review.warnings.contains(where: { $0.contains("unverified witness UTXO") }))
    }

    func testUnverifiedWitnessUTXOOmitsFeeAndWarns() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/9")
        let child = try root.derived(path: path)
        let ours = TransactionOutput(value: 80_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let foreignLegacy = TransactionOutput(value: 40_000, scriptPubKey: Data([0x76, 0xa9, 0x14]) + Data(repeating: 0x11, count: 20) + Data([0x88, 0xac]))
        let unsigned = BitcoinTransaction(
            inputs: [
                TransactionInput(previousTxID: Data(repeating: 0x88, count: 32), previousOutputIndex: 0),
                TransactionInput(previousTxID: Data(repeating: 0x89, count: 32), previousOutputIndex: 1)
            ],
            outputs: [TransactionOutput(value: 100_000, scriptPubKey: Data([0x6a]))]
        )
        let oursMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: ours.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey,
                      value: PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path).encodedValue)
        ])
        let foreignMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: foreignLegacy.serialize())
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [oursMap, foreignMap], outputs: [PSBTMap()])
        let review = psbt.review(root: root)
        XCTAssertNil(review.fee)
        XCTAssertNil(review.totalInput)
        XCTAssertEqual(review.signableInputCount, 1)
        XCTAssertTrue(review.warnings.contains("Unable to calculate fee: Some input(s) provided unverified witness UTXO(s): 1"))
        XCTAssertEqual(psbt.signed(using: root).signedInputCount, 1)
    }

    func testWrappedSegwitWitnessUTXOIsProvablySegwitForFee() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/49'/1'/0'/0/3")
        let child = try root.derived(path: path)
        let redeem = BitcoinAddress.redeemScriptForWrappedSegwit(publicKey: child.publicKey)
        let utxo = TransactionOutput(value: 80_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .wrappedSegwit))
        let unsigned = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(repeating: 0x22, count: 32), previousOutputIndex: 1)],
                                          outputs: [TransactionOutput(value: 79_000, scriptPubKey: Data([0x6a]))])
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x04]), value: redeem),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        let review = psbt.review(root: root)
        XCTAssertEqual(review.fee, 1_000)
        XCTAssertFalse(review.warnings.contains(where: { $0.contains("unverified witness UTXO") }))
    }

    func testPSBTv2RoundTripAndSigning() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let unsigned = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(repeating: 0x11, count: 32), previousOutputIndex: 0)],
                                          outputs: [TransactionOutput(value: 98_000, scriptPubKey: Data([0x6a]))],
                                          lockTime: 500_000)
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let inputMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [inputMap], outputs: [PSBTMap()], psbtVersion: 2)
        XCTAssertEqual(psbt.psbtVersion, 2)
        XCTAssertNil(psbt.global.first(type: 0x00))
        XCTAssertNotNil(psbt.global.first(type: 0x02))
        XCTAssertNotNil(psbt.inputs[0].first(type: 0x0e))
        XCTAssertNotNil(psbt.outputs[0].first(type: 0x03))
        let reparsed = try PSBT(data: psbt.serialize())
        XCTAssertEqual(reparsed.psbtVersion, 2)
        XCTAssertEqual(reparsed.unsignedTransaction.lockTime, 500_000)
        XCTAssertEqual(reparsed.unsignedTransaction.inputs[0].previousTxID, Data(repeating: 0x11, count: 32))
        let review = reparsed.review(root: root)
        XCTAssertEqual(review.fee, 2_000)
        XCTAssertEqual(review.signableInputCount, 1)
        let result = reparsed.signed(using: root)
        XCTAssertEqual(result.signedInputCount, 1)
        let signed = try PSBT(data: result.data)
        XCTAssertEqual(signed.psbtVersion, 2)
        XCTAssertNil(signed.global.first(type: 0x00))
        XCTAssertEqual(signed.global.first(type: 0x06)?.value, Data([0]))
        XCTAssertNotNil(signed.inputs[0].first(type: 0x02))
    }

    func testPSBTVersion1IsRejected() throws {
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 1)
        var copy = psbt
        var version = Data(); version.appendUInt32LE(1)
        copy.global.set(type: 0xfb, value: version)
        XCTAssertThrowsError(try PSBT(data: copy.serialize())) { error in
            XCTAssertEqual(error as? PSBTError, .unsupportedVersion(1))
        }
    }

    func testPSBTv0WithVersion2FieldIsRejected() throws {
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 1)
        var copy = psbt
        var version = Data(); version.appendUInt32LE(2)
        copy.global.set(type: 0xfb, value: version)
        XCTAssertThrowsError(try PSBT(data: copy.serialize())) { error in
            XCTAssertEqual(error as? PSBTError, .malformed)
        }
    }

    func testPSBTv2MissingPreviousTxidIsRejected() throws {
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 1)
        var v2 = try PSBT(unsignedTransaction: psbt.unsignedTransaction, inputs: psbt.inputs,
                          outputs: psbt.outputs, psbtVersion: 2)
        v2.inputs[0].entries.removeAll { $0.type == 0x0e }
        XCTAssertThrowsError(try PSBT(data: v2.serialize())) { error in
            XCTAssertEqual(error as? PSBTError, .malformed)
        }
    }

    func testUnsupportedSighashFlagAlwaysBlocked() throws {
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 5)
        for checks in [true, false] {
            let review = psbt.review(root: root, sighashChecks: checks)
            XCTAssertTrue(review.sighashBlocked)
            XCTAssertEqual(review.fatalIssue, String(format: "Unsupported sighash flag 0x%x", 5))
            XCTAssertEqual(psbt.signed(using: root, sighashChecks: checks).signedInputCount, 0)
        }
    }

    func testP2PKChangeOutputFraudIsFatal() throws {
        let root = try rootKey()
        let (psbt, _) = try fundedPSBT(
            root: root,
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: p2pkScript(Data(repeating: 0x02, count: 33)))],
            outputMaps: [try changeDerivationMap(root: root)]
        )
        let review = psbt.review(root: root)
        XCTAssertEqual(review.fatalIssue, "Output#0: P2PK change output is fraudulent")
        XCTAssertEqual(PSBT.failureTitle(for: review.fatalIssue ?? ""), "Change Fraud")
    }

    func testP2PKMatchingPubkeyIsChange() throws {
        let root = try rootKey()
        let changePath = try DerivationPath("m/84'/1'/0'/1/0")
        let changeKey = try root.derived(path: changePath)
        let (psbt, _) = try fundedPSBT(
            root: root,
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: p2pkScript(changeKey.publicKey))],
            outputMaps: [try changeDerivationMap(root: root, path: changePath)]
        )
        let review = psbt.review(root: root)
        XCTAssertNil(review.fatalIssue)
        XCTAssertTrue(review.outputs[0].isChange)
    }

    func testMissingRedeemScriptForP2SHOutputIsFatal() throws {
        let root = try rootKey()
        let changePath = try DerivationPath("m/49'/1'/0'/1/0")
        let changeKey = try root.derived(path: changePath)
        let script = try BitcoinAddress.scriptPubKey(publicKey: changeKey.publicKey, type: .wrappedSegwit)
        let (psbt, _) = try fundedPSBT(
            root: root,
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: script)],
            outputMaps: [try changeDerivationMap(root: root, path: changePath, publicKey: changeKey.publicKey)]
        )
        XCTAssertEqual(psbt.review(root: root).fatalIssue, "Missing redeem script for output #0")
        XCTAssertEqual(PSBT.failureTitle(for: "Missing redeem script for output #0"), "Failure")
    }

    func testMissingRedeemWitnessScriptForMultisigOutputIsFatal() throws {
        let root = try rootKey()
        let other = try otherRoot()
        let wallet = try twoOfTwo(ours: root, other: other)
        let derived = try wallet.derivedAddress(change: 1, index: 0, network: .testnet)
        let script = try Data(hex: derived.scriptPubKeyHex)
        let (psbt, _) = try fundedPSBT(
            root: root,
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: script)],
            outputMaps: [try twoOfTwoOutputDerivations(root: root, other: other, change: 1, index: 0)]
        )
        XCTAssertEqual(
            psbt.review(root: root, wallets: [wallet]).fatalIssue,
            "Missing redeem/witness script for multisig output #0"
        )
    }

    func testP2WSHWitnessScriptWrongHashIsFraud() throws {
        let root = try rootKey()
        let other = try otherRoot()
        let wallet = try twoOfTwo(ours: root, other: other)
        let redeem = try wallet.redeemScript(change: 1, index: 0)
        let fakeHash = Data(repeating: 0xab, count: 32)
        let script = Data([0x00, 0x20]) + fakeHash
        var outputMap = try twoOfTwoOutputDerivations(root: root, other: other, change: 1, index: 0)
        outputMap.set(type: 0x01, value: redeem)
        let psbt = try fundedTwoOfTwoPSBT(
            root: root, other: other, wallet: wallet,
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: script)],
            outputMaps: [outputMap]
        )
        XCTAssertEqual(
            psbt.review(root: root, wallets: [wallet]).fatalIssue,
            "Output#0: P2WSH witness script has wrong hash"
        )
    }

    func testP2SHP2WSHRedeemScriptMismatchIsFraud() throws {
        let root = try rootKey()
        let other = try otherRoot()
        let wallet = try twoOfTwo(ours: root, other: other, format: .p2shP2wsh)
        let witness = try wallet.redeemScript(change: 1, index: 0)
        let expectedRedeem = Data([0x00, 0x20]) + SHA2.sha256(witness)
        let script = Data([0xa9, 0x14]) + BitcoinHash.hash160(expectedRedeem) + Data([0x87])
        var outputMap = try twoOfTwoOutputDerivations(root: root, other: other, change: 1, index: 0,
                                                      path: try DerivationPath("m/48'/1'/0'/1'/1/0"))
        outputMap.set(type: 0x01, value: witness)
        outputMap.set(type: 0x00, value: Data([0x00, 0x20]) + Data(repeating: 0x11, count: 32))
        let psbt = try fundedTwoOfTwoPSBT(
            root: root, other: other, wallet: wallet,
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: script)],
            outputMaps: [outputMap]
        )
        XCTAssertEqual(
            psbt.review(root: root, wallets: [wallet]).fatalIssue,
            "Output#0: P2SH-P2WSH redeem script provided, and doesn't match"
        )
    }

    func testP2WSHChangeScriptWrongMNIsFraud() throws {
        let root = try rootKey()
        let other = try otherRoot()
        let wallet = try twoOfTwo(ours: root, other: other)
        let keys = try wallet.publicKeys(change: 1, index: 0)
        let wrong = try MultisigScript.redeem(required: 1, publicKeys: keys, bip67: true)
        let script = try MultisigScript.scriptPubKey(script: wrong, format: .p2wsh)
        var outputMap = try twoOfTwoOutputDerivations(root: root, other: other, change: 1, index: 0)
        outputMap.set(type: 0x01, value: wrong)
        let psbt = try fundedTwoOfTwoPSBT(
            root: root, other: other, wallet: wallet,
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: script)],
            outputMaps: [outputMap]
        )
        XCTAssertEqual(
            psbt.review(root: root, wallets: [wallet]).fatalIssue,
            "Output#0: P2WSH or P2SH change output script: wrong M/N in script"
        )
    }

    func testTaprootSpendRequiresEdgeFirmware() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/86'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .taproot))
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x86, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: Data([0x6a]))]
        )
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        XCTAssertEqual(psbt.review(root: root).fatalIssue, "Install EDGE firmware to spend taproot.")
        XCTAssertEqual(psbt.signed(using: root).signedInputCount, 0)
    }

    func testLegacyInputWithoutNonWitnessUTXOIsFatal() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/44'/1'/0'/0/3")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 50_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .legacy))
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x44, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 49_000, scriptPubKey: Data([0x6a]))]
        )
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        XCTAssertEqual(psbt.review(root: root).fatalIssue, "Legacy input #0 requires non-witness UTXO")
    }

    func testMissingOwnUTXOIsFatal() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x99, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: Data([0x6a]))]
        )
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        XCTAssertEqual(psbt.review(root: root).fatalIssue, "Missing own UTXO(s). Cannot determine value being signed")
    }

    func testNoKeyPathInformationIsFatal() throws {
        let root = try rootKey()
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: Data([0x00, 0x14]) + Data(repeating: 0x11, count: 20))
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0xaa, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: Data([0x6a]))]
        )
        let map = PSBTMap(entries: [PSBTEntry(key: Data([0x01]), value: utxo.serialize())])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        XCTAssertEqual(psbt.review(root: root).fatalIssue, "PSBT does not contain any key path information.")
    }

    func testNoKeyErrorIncludesNeedAndFoundFingerprints() throws {
        let root = try rootKey()
        let other = try otherRoot()
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try other.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0xab, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: Data([0x6a]))]
        )
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: other.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        XCTAssertEqual(
            psbt.review(root: root).fatalIssue,
            PSBT.noKeyError + " (need \(root.fingerprintHex), found \(other.fingerprintHex))"
        )
    }

    func testApprovalFailureStoriesMatchFirmware() {
        XCTAssertEqual(PSBT.parseFailedStory, "PSBT parse failed")
        XCTAssertEqual(PSBT.invalidStory, "Invalid PSBT")
        XCTAssertEqual(PSBT.tooComplexStory, "Transaction is too complex")
        XCTAssertEqual(PSBT.checksumMismatchStory, "PSBT checksum mismatch")
        XCTAssertEqual(PSBT.transactionModifiedStory, "Transaction modified")
        XCTAssertEqual(PSBT.noKeyError, "None of the keys involved in this transaction belong to this Coldcard")
        XCTAssertEqual(PSBT.failureTitle(for: "Output#1: Change output is fraudulent"), "Change Fraud")
        XCTAssertEqual(PSBT.failureTitle(for: "Duplicate inputs"), "Failure")
        let binary = PSBT.oversizeStory(fileBytes: 3_000_000)
        XCTAssertEqual(binary.title, "Sorry")
        XCTAssertEqual(
            binary.body,
            "That transaction file is too big (3000000 bytes). Maximum supported is \(PSBT.maxTransactionLength) bytes."
        )
        let encoded = PSBT.oversizeStory(fileBytes: nil)
        XCTAssertEqual(
            encoded.body,
            "That transaction file is too big. Maximum supported is \(PSBT.maxTransactionLength) bytes."
        )
        XCTAssertEqual(PSBT.parseFailureStory(for: PSBTError.malformed), "PSBT parse failed")
        XCTAssertEqual(PSBT.parseFailureStory(for: PSBTError.unsupportedVersion(1)), "Invalid PSBT")
        XCTAssertEqual(PSBT.parseFailureStory(for: PSBTError.missingUnsignedTransaction), "Invalid PSBT")
        XCTAssertEqual(PSBT.parseFailureStory(for: PSBTError.pathTooDeep), "Invalid PSBT")
        XCTAssertEqual(PSBT.parseFailureStory(for: PSBTError.tooComplex), "Transaction is too complex")
        XCTAssertEqual(PSBT.parseFailureStory(for: PSBTError.checksumMismatch), "PSBT checksum mismatch")
        XCTAssertTrue(PSBT.bytesWereModified(originalSHA: Data(repeating: 1, count: 32), current: Data([2])))
        XCTAssertFalse(PSBT.bytesWereModified(originalSHA: SHA2.sha256(Data([1])), current: Data([1])))
    }

    func testIngestRejectsOversizeBinaryAndChecksumMismatch() throws {
        XCTAssertEqual(PSBT.maxTransactionLength, 2 * 1024 * 1024)
        let huge = PSBT.magic + Data(count: PSBT.maxTransactionLength + 1)
        XCTAssertThrowsError(try PSBT.ingest(huge)) { error in
            XCTAssertEqual(error as? PSBTError, .oversize(fileBytes: huge.count, maximum: PSBT.maxTransactionLength))
        }
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 1)
        let data = psbt.serialize()
        XCTAssertThrowsError(try PSBT.ingest(data, expectedSHA: Data(repeating: 0, count: 32))) { error in
            XCTAssertEqual(error as? PSBTError, .checksumMismatch)
        }
        let ingested = try PSBT.ingest(data)
        XCTAssertEqual(ingested.sha, SHA2.sha256(data))
        XCTAssertEqual(ingested.psbt.unsignedTransaction.txid, psbt.unsignedTransaction.txid)
        XCTAssertThrowsError(try PSBT.ingest(Data("not-a-psbt".utf8))) { error in
            XCTAssertEqual(PSBT.parseFailureStory(for: error), "PSBT parse failed")
        }
    }

    func testAbsLocktimeApprovalCopyMatchesFirmware() throws {
        XCTAssertEqual(
            PSBT.absLocktimeMessage(100_000),
            "This tx can only be spent after block height of 100000"
        )
        XCTAssertEqual(
            PSBT.absLocktimeTimestamp(1_700_000_000),
            "2023-11-14 22:13:20 UTC"
        )
        XCTAssertEqual(
            PSBT.absLocktimeTimestamp(1_294_790_399),
            "2011-01-11 23:59:59 UTC"
        )
        XCTAssertEqual(
            PSBT.absLocktimeMessage(1_700_000_000),
            "This tx can only be spent after 2023-11-14 22:13:20 UTC (MTP)"
        )
        XCTAssertEqual(PSBT.absLocktimeUnixTimestamp(1_294_790_399), "1294790399 (unix timestamp)")
        XCTAssertEqual(
            PSBT.absLocktimeMessage(1_294_790_399),
            "This tx can only be spent after 2011-01-11 23:59:59 UTC (MTP)"
        )

        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let unsigned = BitcoinTransaction(
            version: 2,
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x11, count: 32), previousOutputIndex: 0, sequence: 0xffff_fffe)],
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: Data([0x6a]))],
            lockTime: 100_000
        )
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        let review = psbt.review(root: root)
        XCTAssertEqual(review.locktimeNotes, [
            "Abs Locktime: This tx can only be spent after block height of 100000"
        ])
    }

    func testRelativeTimelockApprovalNotesMatchFirmware() {
        XCTAssertEqual(
            PSBT.relativeTimelockApprovalNotes(blockHeight: [(3, 6)], timeBased: []),
            ["Block height RTL: Input 3. has relative block height timelock of 6 blocks"]
        )
        XCTAssertEqual(
            PSBT.relativeTimelockApprovalNotes(blockHeight: [(0, 6), (1, 6)], timeBased: []),
            ["Block height RTL: 2 inputs have relative block height timelock of 6 blocks"]
        )
        let mixed = PSBT.relativeTimelockApprovalNotes(blockHeight: [(0, 4), (1, 9)], timeBased: [])
        XCTAssertEqual(mixed.first, """
        Block height RTL: 2 inputs have relative block height timelock.

         0.  4 blocks
         1.  9 blocks
        """)
        XCTAssertEqual(
            PSBT.relativeTimelockApprovalNotes(blockHeight: [], timeBased: [(2, 512)]),
            ["Time-based RTL: Input 2. has relative time-based timelock of:\n \(BIP322.humanSeconds(512))"]
        )
    }

    func testRelativeTimelockOnVersion2InputAppearsInReview() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let unsigned = BitcoinTransaction(
            version: 2,
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x11, count: 32), previousOutputIndex: 0, sequence: 6)],
            outputs: [TransactionOutput(value: 98_000, scriptPubKey: Data([0x6a]))]
        )
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        let review = psbt.review(root: root)
        XCTAssertEqual(review.locktimeNotes, [
            "Block height RTL: Input 0. has relative block height timelock of 6 blocks"
        ])
    }

    func testApprovalTitleFooterAndLocktimeSectionMatchFirmware() {
        XCTAssertEqual(PSBT.approvalTitle(isBIP322: false), "OK TO SEND?")
        XCTAssertEqual(PSBT.approvalTitle(isBIP322: true), "OK TO SIGN?")
        XCTAssertEqual(
            PSBT.approvalFooter(noun: "transaction"),
            "Press ENTER to approve and sign transaction. Press (2) to explore transaction. CANCEL to abort."
        )
        XCTAssertEqual(
            PSBT.approvalFooter(noun: "proof of reserves"),
            "Press ENTER to approve and sign proof of reserves. Press (2) to explore transaction. CANCEL to abort."
        )
        XCTAssertEqual(
            PSBT.approvalFooter(noun: "transaction", writeToLowerSlot: true),
            "Press ENTER to approve and sign transaction. Press (2) to explore transaction. (B) to write to lower SD slot. CANCEL to abort."
        )
        XCTAssertEqual(PSBT.seqToStr([3, 0, 1]), "0, 1, 3")
        XCTAssertEqual(
            PSBT.approvalValuePreamble(isConsolidation: false, sendAmount: "8,000 SATS", totalOutput: "98,000 SATS"),
            "Sending 8,000 SATS\n"
        )
        XCTAssertEqual(
            PSBT.approvalValuePreamble(isConsolidation: true, sendAmount: "0 SATS", totalOutput: "98,000 SATS"),
            "Consolidating 98,000 SATS\nwithin wallet.\n\n"
        )
        XCTAssertEqual(
            PSBT.approvalLocktimeSection([
                "Abs Locktime: This tx can only be spent after block height of 100000",
                "Block height RTL: Input 0. has relative block height timelock of 6 blocks"
            ]),
            "TX LOCKTIMES\n\n"
            + "- Abs Locktime: This tx can only be spent after block height of 100000\n\n"
            + "- Block height RTL: Input 0. has relative block height timelock of 6 blocks\n\n"
        )
    }

    func testApprovalOutputCapsKeepOriginalOrderUntilTenAndTwenty() {
        let foreign = (0..<12).map { index in
            dummyOutput(index: index, value: UInt64(1_000 + index), isChange: false)
        }
        let change = (12..<34).map { index in
            dummyOutput(index: index, value: UInt64(100 + index), isChange: true)
        }
        let summary = PSBT.approvalOutputSummary(foreign + change)
        XCTAssertFalse(summary.isConsolidation)
        XCTAssertEqual(summary.foreign.map(\.index), [11, 10, 9, 8, 7, 6, 5, 4, 3, 2])
        XCTAssertEqual(summary.hiddenForeignCount, 2)
        XCTAssertEqual(summary.hiddenForeignValue, 1_000 + 1_001)
        XCTAssertEqual(summary.change.map(\.index), Array(14..<34).reversed())
        XCTAssertEqual(summary.hiddenChangeCount, 2)
        XCTAssertEqual(summary.changeTotal, change.reduce(UInt64(0)) { $0 + $1.value })

        let underCap = [
            dummyOutput(index: 0, value: 10, isChange: false),
            dummyOutput(index: 1, value: 50, isChange: false),
            dummyOutput(index: 2, value: 20, isChange: false),
            dummyOutput(index: 3, value: 5, isChange: true),
            dummyOutput(index: 4, value: 9, isChange: true)
        ]
        let original = PSBT.approvalOutputSummary(underCap)
        XCTAssertEqual(original.foreign.map(\.index), [0, 1, 2])
        XCTAssertEqual(original.change.map(\.index), [3, 4])
        XCTAssertEqual(original.hiddenForeignCount, 0)
        XCTAssertEqual(original.hiddenChangeCount, 0)
        XCTAssertFalse(original.isConsolidation)

        let onlyChange = (0..<3).map { dummyOutput(index: $0, value: 100, isChange: true) }
        XCTAssertTrue(PSBT.approvalOutputSummary(onlyChange).isConsolidation)
    }

    func testWarningsNeverIncludeSatVBOrOneBasedInputPrefix() throws {
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 1)
        let review = psbt.review(root: root)
        XCTAssertFalse(review.warnings.contains(where: { $0.contains("sat/vB") || $0.contains("High fee rate") }))
        XCTAssertFalse(review.warnings.contains(where: { $0.hasPrefix("Input ") && $0.contains(":") }))
    }

    func testMissingForeignUTXOWarnsAndOmitsFee() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/9")
        let child = try root.derived(path: path)
        let ours = TransactionOutput(value: 80_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let unsigned = BitcoinTransaction(
            inputs: [
                TransactionInput(previousTxID: Data(repeating: 0x88, count: 32), previousOutputIndex: 0),
                TransactionInput(previousTxID: Data(repeating: 0x89, count: 32), previousOutputIndex: 1)
            ],
            outputs: [TransactionOutput(value: 70_000, scriptPubKey: Data([0x6a]))]
        )
        let oursMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: ours.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey,
                      value: PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path).encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [oursMap, PSBTMap()], outputs: [PSBTMap()])
        let review = psbt.review(root: root)
        XCTAssertNil(review.fee)
        XCTAssertTrue(review.warnings.contains("Unable to calculate fee: Some input(s) haven't provided UTXO(s): 1"))
        XCTAssertTrue(review.warnings.contains("Limited Signing: We are not signing these inputs, because we do not know the key: 1"))
        let feeIdx = review.warnings.firstIndex { $0.hasPrefix("Unable to calculate fee") }
        let limitedIdx = review.warnings.firstIndex { $0.hasPrefix("Limited Signing") }
        XCTAssertEqual(feeIdx.map { $0 < (limitedIdx ?? .max) }, true)
    }

    func testWarningOrderZeroXFPThenInputsThenOutputsThenSighash() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x33, count: 32), previousOutputIndex: 0, sequence: 0xffff_ffff)],
            outputs: [TransactionOutput(value: 95_000, scriptPubKey: Data([0x6a, 0x01, 0x61]))],
            lockTime: 100
        )
        let zeroXFP = Data(repeating: 0, count: 4)
        var sighash = Data(); sighash.appendUInt32LE(0x81)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x03]), value: sighash),
            PSBTEntry(key: Data([0x06]) + child.publicKey,
                      value: PSBTDerivation(publicKey: child.publicKey, masterFingerprint: zeroXFP, path: path).encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        let review = psbt.review(root: root, sighashChecks: false)
        let labels = review.warnings.map { String($0.split(separator: ":", maxSplits: 1).first ?? "") }
        XCTAssertEqual(labels.first, "Zero XFP")
        XCTAssertTrue(labels.contains("Bad Locktime"))
        XCTAssertTrue(labels.contains("Big Fee"))
        XCTAssertTrue(labels.contains("Caution"))
        let zero = labels.firstIndex(of: "Zero XFP")!
        let lock = labels.firstIndex(of: "Bad Locktime")!
        let fee = labels.firstIndex(of: "Big Fee")!
        let caution = labels.firstIndex(of: "Caution")!
        XCTAssertTrue(zero < lock && lock < fee && fee < caution)
    }

    func testWIFStoreWarningAndSignableWithoutHDPath() throws {
        let root = try rootKey()
        let wifRoot = try HDKey(seed: Data(repeating: 9, count: 32), network: .testnet)
        let item = try WIF.decodeForStore(wifRoot.wif(), network: .testnet)
        let script = try BitcoinAddress.scriptPubKey(publicKey: item.publicKey!, type: .nativeSegwit)
        let utxo = TransactionOutput(value: 50_000, scriptPubKey: script)
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0xaa, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 49_000, scriptPubKey: Data([0x6a]))]
        )
        let map = PSBTMap(entries: [PSBTEntry(key: Data([0x01]), value: utxo.serialize())])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        let review = psbt.review(root: root, wifKeys: [item])
        XCTAssertNil(review.fatalIssue)
        XCTAssertEqual(review.signableInputCount, 1)
        XCTAssertTrue(review.warnings.contains("WIF Store: Some input(s) use key from the WIF store: 0"))
        XCTAssertEqual(psbt.signed(using: root, wifKeys: [item]).signedInputCount, 1)
    }

    func testDisabledMultisigChecksWarnsDanger() throws {
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 1)
        let review = psbt.review(root: root, disableMultisigChecks: true)
        XCTAssertTrue(review.warnings.contains("Danger: Some multisig checks are disabled."))
    }

    func testSegwitHistoryMismatchIsIncorrectUTXOAmount() throws {
        let root = try rootKey()
        let (psbt, _, _, _) = try sighashFixture(root: root, sighash: 1)
        let first = psbt.review(root: root, displayUnits: .sats)
        XCTAssertNil(first.fatalIssue)
        XCTAssertFalse(first.utxoHistory.entries.isEmpty)

        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let spoofed = TransactionOutput(value: 50_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x33, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 40_000, scriptPubKey: Data([0x6a]))]
        )
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: spoofed.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let spoofedPSBT = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        let second = spoofedPSBT.review(root: root, utxoHistory: first.utxoHistory, displayUnits: .sats)
        XCTAssertEqual(
            second.fatalIssue,
            "Input#0: Expected 100000 but PSBT claims 50000 sats"
        )
    }

    func testOutptValueCacheRoundTripAndIncorrectAmountCopy() {
        var cache = OutptValueCache()
        let prevout = Data(repeating: 0x33, count: 32) + Data([0, 0, 0, 0])
        XCTAssertEqual(OutptValueCache.encodeKey(prevout).count, OutptValueCache.encodedKeyLength)
        XCTAssertEqual(OutptValueCache.encodeValue(prevout: prevout, amount: 100_000).count, 11)
        try? cache.verifyAmount(prevout: prevout, amount: 100_000, inputIndex: 0, displayUnits: .sats, network: .testnet)
        XCTAssertEqual(cache.fetchAmount(prevout), 100_000)
        XCTAssertEqual(
            OutptValueCache.incorrectAmountMessage(
                inputIndex: 0, expected: 100_000, claimed: 50_000, displayUnits: .sats, network: .testnet
            ),
            "Input#0: Expected 100000 but PSBT claims 50000 sats"
        )
    }

    func testBIP322ApprovalCopyAndSimpleReview() throws {
        XCTAssertEqual(PSBT.approveNoun(isBIP322: false, isProofOfReserves: false), "transaction")
        XCTAssertEqual(PSBT.approveNoun(isBIP322: true, isProofOfReserves: false), "message")
        XCTAssertEqual(PSBT.approveNoun(isBIP322: true, isProofOfReserves: true), "proof of reserves")
        XCTAssertEqual(
            PSBT.inputOutputCountLine(inputs: 1, outputs: 2),
            " 1 input\n 2 outputs\n\n"
        )
        let preamble = PSBT.bip322ApprovalPreamble(
            isProofOfReserves: false,
            message: "hello",
            challengeAddress: "tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            inputCount: 1,
            outputCount: 1
        )
        XCTAssertTrue(preamble.hasPrefix("BIP-322 Message\n\nMessage:\nhello\n\n"))
        XCTAssertTrue(preamble.contains("Challenge Address:\n"))
        XCTAssertTrue(preamble.contains(String(LCDDisplay.addressMarker)))
        XCTAssertFalse(preamble.contains("Amount "))
        XCTAssertFalse(preamble.contains(" input"))
        let por = PSBT.bip322ApprovalPreamble(
            isProofOfReserves: true,
            message: "reserves",
            amount: "0.001 XTN",
            challengeAddress: "tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            inputCount: 2,
            outputCount: 1
        )
        XCTAssertTrue(por.hasPrefix("Proof of Reserves\n\n"))
        XCTAssertTrue(por.contains("Amount 0.001 XTN\n\n"))
        XCTAssertTrue(por.contains(" 2 inputs\n 1 output\n\n"))

        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let challenge = try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit)
        let message = "hello"
        let toSpend = BIP322.toSpend(messageHash: BIP322.messageHash(message), challenge: challenge)
        let utxo = TransactionOutput(value: 0, scriptPubKey: challenge)
        let unsigned = BitcoinTransaction(
            version: 0,
            inputs: [TransactionInput(previousTxID: toSpend.txidHash, previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 0, scriptPubKey: Data([0x6a]))]
        )
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        var psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        psbt.global.set(type: 0x09, value: Data(message.utf8))
        let review = psbt.review(root: root)
        XCTAssertNil(review.fatalIssue)
        XCTAssertEqual(review.bip322Message, message)
        XCTAssertFalse(review.bip322IsProofOfReserves)
        XCTAssertEqual(review.bip322Challenge, BitcoinScript.address(for: challenge, network: .testnet))
        XCTAssertFalse(review.warnings.contains(where: { $0.contains("Big Fee") || $0.contains("sat/vB") }))
        XCTAssertEqual(PSBT.approvalTitle(isBIP322: true), "OK TO SIGN?")
        XCTAssertTrue(PSBT.approvalFooter(noun: "message").contains("sign message"))
        XCTAssertFalse(PSBT.approvalFooter(noun: "message").contains(".psbt"))
    }

    func testBIP322UnusualSighashIsPORNotSighashAll() throws {
        let root = try rootKey()
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let challenge = try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit)
        let message = "hello"
        let toSpend = BIP322.toSpend(messageHash: BIP322.messageHash(message), challenge: challenge)
        let utxo = TransactionOutput(value: 0, scriptPubKey: challenge)
        let unsigned = BitcoinTransaction(
            version: 0,
            inputs: [TransactionInput(previousTxID: toSpend.txidHash, previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 0, scriptPubKey: Data([0x6a]))]
        )
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        var sighash = Data(); sighash.appendUInt32LE(0x81)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x03]), value: sighash),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        var psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        psbt.global.set(type: 0x09, value: Data(message.utf8))
        XCTAssertEqual(psbt.review(root: root, sighashChecks: false).fatalIssue, "POR not SIGHASH_ALL")
    }

    func testShowSingleAddressUsesControlMarker() {
        let addr = "tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        XCTAssertEqual(LCDDisplay.showSingleAddress(addr).first, Optional(LCDDisplay.addressMarker))
        XCTAssertEqual(
            LCDDisplay.spacedAddress(addr),
            "tb1q xy2k gdyg jrsq tzq2 n0yr f249 3p83 kkfj hx0w lh"
        )
        XCTAssertEqual(LCDDisplay.drawnAddress("tb1qxy2k"), " tb1q xy2k ")
    }

    private func dummyOutput(index: Int, value: UInt64, isChange: Bool) -> PSBTOutputReview {
        PSBTOutputReview(
            index: index,
            value: value,
            address: "tb1q\(index)",
            scriptPubKey: Data([0x00, 0x14]),
            isChange: isChange,
            path: isChange ? "m/84'/1'/0'/1/\(index)" : nil
        )
    }

    private func p2pkScript(_ publicKey: Data) -> Data {
        Data([UInt8(publicKey.count)]) + publicKey + Data([0xac])
    }

    private func fundedPSBT(
        root: HDKey,
        outputs: [TransactionOutput],
        outputMaps: [PSBTMap]
    ) throws -> (PSBT, HDKey) {
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x33, count: 32), previousOutputIndex: 0)],
            outputs: outputs
        )
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        let inputMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [inputMap], outputs: outputMaps)
        return (psbt, child)
    }

    private func fundedTwoOfTwoPSBT(
        root: HDKey,
        other: HDKey,
        wallet: MultisigWalletConfig,
        outputs: [TransactionOutput],
        outputMaps: [PSBTMap]
    ) throws -> PSBT {
        let deriv = wallet.addressFormat == .p2shP2wsh ? "m/48'/1'/0'/1'/0/0" : "m/48'/1'/0'/2'/0/0"
        let path = try DerivationPath(deriv)
        let derived = try wallet.derivedAddress(change: 0, index: 0, network: .testnet)
        let redeem = try wallet.redeemScript(change: 0, index: 0)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try Data(hex: derived.scriptPubKeyHex))
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x22, count: 32), previousOutputIndex: 0)],
            outputs: outputs
        )
        let ourChild = try root.derived(path: path)
        let otherChild = try other.derived(path: path)
        var entries = [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x05]), value: redeem),
            PSBTEntry(
                key: Data([0x06]) + ourChild.publicKey,
                value: PSBTDerivation(publicKey: ourChild.publicKey, masterFingerprint: root.fingerprint, path: path).encodedValue
            ),
            PSBTEntry(
                key: Data([0x06]) + otherChild.publicKey,
                value: PSBTDerivation(publicKey: otherChild.publicKey, masterFingerprint: other.fingerprint, path: path).encodedValue
            )
        ]
        if wallet.addressFormat == .p2shP2wsh {
            entries.append(PSBTEntry(key: Data([0x04]), value: Data([0x00, 0x20]) + SHA2.sha256(redeem)))
        }
        return try PSBT(unsignedTransaction: unsigned, inputs: [PSBTMap(entries: entries)], outputs: outputMaps)
    }

    private func changeDerivationMap(
        root: HDKey,
        path: DerivationPath? = nil,
        publicKey: Data? = nil
    ) throws -> PSBTMap {
        let changePath = try path ?? DerivationPath("m/84'/1'/0'/1/0")
        let key = try root.derived(path: changePath)
        let pub = publicKey ?? key.publicKey
        return PSBTMap(entries: [
            PSBTEntry(
                key: Data([0x02]) + pub,
                value: PSBTDerivation(publicKey: pub, masterFingerprint: root.fingerprint, path: changePath).encodedValue
            )
        ])
    }

    private func otherRoot() throws -> HDKey {
        try HDKey(seed: Data(repeating: 3, count: 64), network: .testnet)
    }

    private func twoOfTwo(
        ours: HDKey,
        other: HDKey,
        format: MultisigAddressFormat = .p2wsh
    ) throws -> MultisigWalletConfig {
        let deriv = format == .p2shP2wsh ? "m/48'/1'/0'/1'" : "m/48'/1'/0'/2'"
        let path = try DerivationPath(deriv)
        return MultisigWalletConfig(
            name: "CC-2-of-2",
            requiredSignatures: 2,
            totalSigners: 2,
            addressFormat: format,
            chain: "XTN",
            bip67: true,
            cosigners: [
                MultisigCosigner(fingerprint: ours.fingerprintHex, derivation: deriv.replacingOccurrences(of: "'", with: "h"),
                                 xpub: try ours.derived(path: path).neutered().serializePublic()),
                MultisigCosigner(fingerprint: other.fingerprintHex, derivation: deriv.replacingOccurrences(of: "'", with: "h"),
                                 xpub: try other.derived(path: path).neutered().serializePublic())
            ]
        )
    }

    private func twoOfTwoOutputDerivations(
        root: HDKey,
        other: HDKey,
        change: UInt32,
        index: UInt32,
        path: DerivationPath? = nil
    ) throws -> PSBTMap {
        let deriv = try path ?? DerivationPath("m/48'/1'/0'/2'/\(change)/\(index)")
        let ourChild = try root.derived(path: deriv)
        let otherChild = try other.derived(path: deriv)
        return PSBTMap(entries: [
            PSBTEntry(
                key: Data([0x02]) + ourChild.publicKey,
                value: PSBTDerivation(publicKey: ourChild.publicKey, masterFingerprint: root.fingerprint, path: deriv).encodedValue
            ),
            PSBTEntry(
                key: Data([0x02]) + otherChild.publicKey,
                value: PSBTDerivation(publicKey: otherChild.publicKey, masterFingerprint: other.fingerprint, path: deriv).encodedValue
            )
        ])
    }

    private func sighashFixture(root: HDKey, sighash: UInt32) throws -> (PSBT, HDKey, TransactionOutput, BitcoinTransaction) {
        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let child = try root.derived(path: path)
        let utxo = TransactionOutput(value: 100_000, scriptPubKey: try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: .nativeSegwit))
        let destination = try BitcoinAddress.derive(root: root, type: .nativeSegwit, change: false, index: 5)
        let unsigned = BitcoinTransaction(inputs: [TransactionInput(previousTxID: Data(repeating: 0x33, count: 32), previousOutputIndex: 0)],
                                          outputs: [TransactionOutput(value: 98_000, scriptPubKey: try Data(hex: destination.scriptPubKeyHex))])
        let derivation = PSBTDerivation(publicKey: child.publicKey, masterFingerprint: root.fingerprint, path: path)
        var sighashValue = Data()
        sighashValue.appendUInt32LE(sighash)
        let map = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x03]), value: sighashValue),
            PSBTEntry(key: Data([0x06]) + child.publicKey, value: derivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [map], outputs: [PSBTMap()])
        return (psbt, child, utxo, unsigned)
    }

    private func rootKey() throws -> HDKey {
        let mnemonic = try BIP39Mnemonic(phrase: mnemonicPhrase)
        return try HDKey(seed: mnemonic.seed(), network: .testnet)
    }
}

import XCTest
@testable import ColdcardCore

final class MultisigTests: XCTestCase {
    /// Firmware `testing/devtest/unit_multisig.py` 2-of-10 redeem script addresses.
    func testFirmwareUnitMultisigAddresses() throws {
        let script = try Data(hex:
            "52210202c68b0228cb577123c2f41275dadf8f4958890d3daf3728e38492f4913077dc" +
            "2102316dfd8d084a2b645061423013b52f513846e80c10816f66330f5609c8f6e7e2" +
            "21025328ece688cdc37d679b3af650f5d51487c1fe2fbd733b38cbfb58a9588a2155" +
            "210288eb170b0661a6e86d1f1ab53a1099970d1b4d4cdd44d503d926effeec1e2084" +
            "2102fc3285261cccf4e7a44219758ee0383d25133b19a9fa14441ecb6ce9f3a4a528" +
            "21038d00b6b4752dbba6afe6dcc00ef4b1fb0c212695f28a7908256808c2c201c435" +
            "21038d5bcc32c89e363d181a08eb1c7613c0ba9aa02643d04cf00ae2cfea4192c972" +
            "2103a11fd11e66e3d50818e3826a9b157245e6b361e32db9036768b54b4bc09adf09" +
            "2103d357b96bf98bcd5705d0f4745c2557d452d46a7cb9a6b193521de4516790f118" +
            "2103f5bf5e00104c8956127ff926c0c5dd74690f8e67a21898cecb256dda34428a79" +
            "5aae")
        let parsed = try MultisigScript.disassemble(script)
        XCTAssertEqual(parsed.requiredSignatures, 2)
        XCTAssertEqual(parsed.totalSigners, 10)
        XCTAssertEqual(parsed.publicKeys[0],
                       try Data(hex: "0202c68b0228cb577123c2f41275dadf8f4958890d3daf3728e38492f4913077dc"))
        XCTAssertEqual(try MultisigScript.address(script: script, format: .p2sh, network: .mainnet),
                       "3Kt6KxjirrFS7GexJiXLLhmuaMzSbjp275")
        XCTAssertEqual(try MultisigScript.address(script: script, format: .p2sh, network: .testnet),
                       "2NBSJPhfkUJknK4HVyr9CxemAniCcRfhqp4")
        XCTAssertEqual(try MultisigScript.address(script: script, format: .p2wsh, network: .mainnet),
                       "bc1qnjw7wy4e9tf4kkqaf43n2cyjwug0ystugum08c5j5hwhfncc4mkqftu4jr")
        XCTAssertEqual(try MultisigScript.address(script: script, format: .p2wsh, network: .testnet),
                       "tb1qnjw7wy4e9tf4kkqaf43n2cyjwug0ystugum08c5j5hwhfncc4mkq7r26gv")
        XCTAssertEqual(try MultisigScript.address(script: script, format: .p2wsh, network: .regtest),
                       "bcrt1qnjw7wy4e9tf4kkqaf43n2cyjwug0ystugum08c5j5hwhfncc4mkqn6quak")
    }

    func testXFPDisplayMatchesFirmware() {
        // Firmware `xfp2str(0x10203040) == '40302010'`.
        XCTAssertEqual(MultisigWalletConfig.fingerprintString(UInt32(0x10203040)), "40302010")
        XCTAssertEqual(MultisigWalletConfig.fingerprintValue("40302010"), UInt32(0x10203040))
    }

    func testExtendedKeyRoundTripAndSLIP132Normalize() throws {
        let mnemonic = try BIP39Mnemonic(phrase: Self.abandon)
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let path = try DerivationPath("m/48'/1'/0'/2'")
        let node = try root.derived(path: path).neutered()
        let xpub = node.serializePublic()
        let parsed = try HDKey(extendedKey: xpub)
        XCTAssertEqual(parsed.serializePublic(), xpub)
        XCTAssertEqual(parsed.publicKey, node.publicKey)
        let slip = node.serializePublic(version: MultisigAddressFormat.p2wsh.slip132PublicVersion(network: .testnet))
        XCTAssertTrue(slip.hasPrefix("Vpub") || slip.hasPrefix("vpub"))
        let normalized = try HDKey(extendedKey: slip).serializePublic()
        XCTAssertEqual(normalized, xpub)
    }

    func testBIP67SortsPubkeysInRedeemScript() throws {
        let keys = try (0..<3).map { index -> Data in
            let seed = Data(repeating: UInt8(index + 1), count: 32)
            return try HDKey(seed: seed, network: .testnet).publicKey
        }
        let script = try MultisigScript.redeem(required: 2, publicKeys: keys, bip67: true)
        let parsed = try MultisigScript.disassemble(script)
        XCTAssertEqual(parsed.publicKeys, keys.sorted { $0.lexicographicallyPrecedes($1) })
        let unsorted = try MultisigScript.redeem(required: 2, publicKeys: keys, bip67: false)
        XCTAssertEqual(try MultisigScript.disassemble(unsorted).publicKeys, keys)
    }

    func testUniqueNameAllocation() {
        XCTAssertEqual(MultisigWalletConfig.uniqueName("2-of-2", existing: []), "2-of-2")
        XCTAssertEqual(MultisigWalletConfig.uniqueName("2-of-2", existing: ["2-of-2"]), "2-of-2 #2")
        XCTAssertEqual(MultisigWalletConfig.uniqueName("2-of-2", existing: ["2-of-2", "2-of-2 #2"]), "2-of-2 #3")
    }

    func testParseSimpleTextRequiresOurKeyAndRoundTrips() throws {
        let ours = try Self.ourRoot()
        let other = try Self.otherRoot()
        let path = try DerivationPath("m/48'/1'/0'/2'")
        let ourNode = try ours.derived(path: path).neutered()
        let otherNode = try other.derived(path: path).neutered()
        let text = """
        Name: CC-2-of-2
        Policy: 2 of 2
        Format: p2wsh

        Derivation: m/48h/1h/0h/2h

        \(ours.fingerprintHex): \(ourNode.serializePublic())
        \(other.fingerprintHex): \(otherNode.serializePublic())
        """
        let imported = try MultisigWalletConfig.importFile(
            text, nameHint: "fromfile",
            context: MultisigImportContext(root: ours, allowUnsorted: false, disableChecks: false)
        )
        XCTAssertEqual(imported.name, "CC-2-of-2")
        XCTAssertEqual(imported.requiredSignatures, 2)
        XCTAssertEqual(imported.totalSigners, 2)
        XCTAssertEqual(imported.addressFormat, .p2wsh)
        XCTAssertTrue(imported.bip67)
        XCTAssertEqual(imported.cosigners.count, 2)
        let exported = imported.coldcardExport(headerComment: "exported from \(ours.fingerprintHex)")
        XCTAssertTrue(exported.contains("Name: CC-2-of-2"))
        XCTAssertTrue(exported.contains("Policy: 2 of 2"))
        XCTAssertTrue(exported.contains("Format: P2WSH"))
        let reimported = try MultisigWalletConfig.importFile(
            exported, nameHint: nil,
            context: MultisigImportContext(root: ours, allowUnsorted: false, disableChecks: false)
        )
        XCTAssertEqual(reimported.cosigners.map(\.xpub), imported.cosigners.map(\.xpub))
    }

    func testImportRejectsMissingOwnKey() throws {
        let ours = try Self.ourRoot()
        let other = try Self.otherRoot()
        let third = try HDKey(seed: Data(repeating: 9, count: 32), network: .testnet)
        let path = try DerivationPath("m/48'/1'/0'/2'")
        let text = """
        Policy: 2 of 2
        Format: p2wsh
        Derivation: m/48h/1h/0h/2h
        \(other.fingerprintHex): \(try other.derived(path: path).neutered().serializePublic())
        \(third.fingerprintHex): \(try third.derived(path: path).neutered().serializePublic())
        """
        XCTAssertThrowsError(try MultisigWalletConfig.importFile(
            text, nameHint: "no-me",
            context: MultisigImportContext(root: ours, allowUnsorted: false, disableChecks: false)
        )) { error in
            XCTAssertEqual(error as? MultisigError, .myKeyNotIncluded)
        }
    }

    func testDescriptorParseAndSerialize() throws {
        let ours = try Self.ourRoot()
        let other = try Self.otherRoot()
        let wallet = try Self.twoOfTwo(ours: ours, other: other)
        let descriptor = try wallet.descriptor()
        XCTAssertTrue(descriptor.hasPrefix("wsh(sortedmulti(2,"))
        XCTAssertTrue(descriptor.contains("#"))
        let parsed = try MultisigWalletConfig.importFile(
            descriptor, nameHint: nil,
            context: MultisigImportContext(root: ours, allowUnsorted: false, disableChecks: false)
        )
        XCTAssertEqual(parsed.requiredSignatures, 2)
        XCTAssertEqual(parsed.addressFormat, .p2wsh)
        XCTAssertTrue(parsed.bip67)
        XCTAssertEqual(parsed.cosigners.count, 2)
        let withoutChecksum = String(descriptor.split(separator: "#")[0])
        let unsorted = withoutChecksum.replacingOccurrences(of: "sortedmulti", with: "multi")
        XCTAssertThrowsError(try MultisigWalletConfig.importFile(
            unsorted, nameHint: nil,
            context: MultisigImportContext(root: ours, allowUnsorted: false, disableChecks: false)
        )) { error in
            XCTAssertEqual(error as? MultisigError, .unsortedNotAllowed)
        }
        XCTAssertNoThrow(try MultisigWalletConfig.importFile(
            unsorted, nameHint: nil,
            context: MultisigImportContext(root: ours, allowUnsorted: true, disableChecks: false)
        ))
    }

    func testDuplicateWalletDetection() throws {
        let ours = try Self.ourRoot()
        let other = try Self.otherRoot()
        let first = try Self.twoOfTwo(ours: ours, other: other, name: "A")
        let same = try Self.twoOfTwo(ours: ours, other: other, name: "B")
        let result = same.similarity(to: [first])
        XCTAssertTrue(result.isDuplicate)
        XCTAssertTrue(result.differences.contains("All details are the same as existing!"))
    }

    func testXPUBExportJSONContainsBIP48Paths() throws {
        let ours = try Self.ourRoot()
        let json = try MultisigXPUBExport.json(root: ours, account: 0)
        XCTAssertTrue(json.contains("\"xfp\": \"\(ours.fingerprintHex)\""))
        XCTAssertTrue(json.contains("p2wsh_deriv"))
        XCTAssertTrue(json.contains("m/48h/1h/0h/2h"))
        XCTAssertTrue(json.contains("p2sh_p2wsh_deriv"))
        XCTAssertTrue(json.contains("m/45h"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let parsed = try MultisigXPUBExport.cosigner(from: object, addressKey: "p2wsh")
        XCTAssertEqual(parsed.fingerprint.uppercased(), ours.fingerprintHex)
        XCTAssertEqual(parsed.derivation, "m/48h/1h/0h/2h")
    }

    func testAddressDerivationAndChangeMatch() throws {
        let ours = try Self.ourRoot()
        let other = try Self.otherRoot()
        let wallet = try Self.twoOfTwo(ours: ours, other: other)
        let first = try wallet.derivedAddress(change: 0, index: 0, network: .testnet)
        XCTAssertTrue(first.address.hasPrefix("tb1q"))
        XCTAssertTrue(first.paths[0].contains(ours.fingerprintHex))
        let script = try wallet.scriptPubKey(change: 0, index: 0)
        XCTAssertEqual(script, try Data(hex: first.scriptPubKeyHex))
        XCTAssertTrue(wallet.ownsScript(script, change: 0, index: 0))
        XCTAssertFalse(wallet.ownsScript(script, change: 1, index: 0))
    }

    func testElectrumAndCoreExports() throws {
        let ours = try Self.ourRoot()
        let wallet = try Self.twoOfTwo(ours: ours, other: try Self.otherRoot())
        let electrum = try wallet.electrumExport(myFingerprint: ours.fingerprintHex)
        XCTAssertTrue(electrum.contains("\"wallet_type\" : \"2of2\"") || electrum.contains("\"wallet_type\":\"2of2\""))
        XCTAssertTrue(electrum.contains("ckcc_xfp"))
        let core = try wallet.bitcoinCoreExport()
        XCTAssertTrue(core.hasPrefix("importdescriptors '"))
        XCTAssertTrue(core.contains("\"internal\": false") || core.contains("\"internal\":false"))
    }

    func testP2WSHPartialSignature() throws {
        let ours = try Self.ourRoot()
        let other = try Self.otherRoot()
        let wallet = try Self.twoOfTwo(ours: ours, other: other)
        let derived = try wallet.derivedAddress(change: 0, index: 0, network: .testnet)
        let redeem = try wallet.redeemScript(change: 0, index: 0)
        let utxo = TransactionOutput(value: 50_000, scriptPubKey: try Data(hex: derived.scriptPubKeyHex))
        let dest = try BitcoinAddress.derive(root: ours, type: .nativeSegwit, index: 1)
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x22, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 49_000, scriptPubKey: try Data(hex: dest.scriptPubKeyHex))]
        )
        let ourPath = try DerivationPath("m/48'/1'/0'/2'/0/0")
        let ourChild = try ours.derived(path: ourPath)
        let otherChild = try other.derived(path: ourPath)
        let ourDerivation = PSBTDerivation(publicKey: ourChild.publicKey, masterFingerprint: ours.fingerprint, path: ourPath)
        let otherDerivation = PSBTDerivation(publicKey: otherChild.publicKey, masterFingerprint: other.fingerprint, path: ourPath)
        let inputMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x05]), value: redeem),
            PSBTEntry(key: Data([0x06]) + ourChild.publicKey, value: ourDerivation.encodedValue),
            PSBTEntry(key: Data([0x06]) + otherChild.publicKey, value: otherDerivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [inputMap], outputs: [PSBTMap()])
        let review = psbt.review(root: ours, wallets: [wallet])
        XCTAssertEqual(review.signableInputCount, 1)
        XCTAssertEqual(review.multisigWalletName, wallet.name)
        let signed = psbt.signed(using: ours)
        XCTAssertEqual(signed.signedInputCount, 1)
    }

    func testSimulatorSeedFingerprintMatchesFirmware() throws {
        let root = try Self.simulatorRoot()
        XCTAssertEqual(root.fingerprintHex, "0F056943")
        XCTAssertEqual(MultisigWalletConfig.fingerprintString(root.ckccXFP), "0F056943")
        XCTAssertEqual(MultisigWalletConfig.fingerprintValue("0F056943"), UInt32(0x4369050f))
    }

    func testFirmwareExportFileImportAndDescriptorChecksum() throws {
        let root = try Self.simulatorRoot()
        let context = MultisigImportContext(root: root, allowUnsorted: false, disableChecks: false)
        XCTAssertTrue(MultisigWalletConfig.looksLikeImportable(Self.firmwareExportP2WSH))
        let imported = try MultisigWalletConfig.importFile(Self.firmwareExportP2WSH, nameHint: "export-p2wsh-myself",
                                                           context: context)
        XCTAssertEqual(imported.name, "CC-2-of-4")
        XCTAssertEqual(imported.requiredSignatures, 2)
        XCTAssertEqual(imported.totalSigners, 4)
        XCTAssertEqual(imported.addressFormat, .p2wsh)
        XCTAssertEqual(imported.chain, "XTN")
        XCTAssertEqual(imported.cosigners.map(\.fingerprint), ["0F056943", "6BA6CFD0", "747B698E", "7BB026BE"])
        XCTAssertTrue(imported.includesFingerprint(root.fingerprintHex))
        let descriptor = try imported.descriptor()
        XCTAssertEqual(descriptor.trimmingCharacters(in: .whitespacesAndNewlines), Self.firmwareDescP2WSH)
        let fromDesc = try MultisigWalletConfig.importFile(Self.firmwareDescP2WSH, nameHint: nil, context: context)
        XCTAssertEqual(fromDesc.cosigners.map(\.xpub), imported.cosigners.map(\.xpub))
        XCTAssertEqual(fromDesc.addressFormat, .p2wsh)
        XCTAssertTrue(fromDesc.bip67)
    }

    func testFirmwareP2SHAndWrappedExportFiles() throws {
        let context = MultisigImportContext(root: try Self.simulatorRoot(), allowUnsorted: false, disableChecks: false)
        let p2sh = try MultisigWalletConfig.importFile(Self.firmwareExportP2SH, nameHint: nil, context: context)
        XCTAssertEqual(p2sh.addressFormat, .p2sh)
        XCTAssertEqual(try p2sh.descriptor().trimmingCharacters(in: .whitespacesAndNewlines), Self.firmwareDescP2SH)
        let wrapped = try MultisigWalletConfig.importFile(Self.firmwareExportP2SHP2WSH, nameHint: nil, context: context)
        XCTAssertEqual(wrapped.addressFormat, .p2shP2wsh)
        XCTAssertEqual(try wrapped.descriptor().trimmingCharacters(in: .whitespacesAndNewlines),
                       Self.firmwareDescP2SHP2WSH)
    }

    func testFirmwareStorageJSONRoundTrip() throws {
        let wallet = try MultisigWalletConfig.fromFirmwareStorageJSON(Self.firmwareSettingP2WSH)
        XCTAssertEqual(wallet.name, "CC-2-of-4")
        XCTAssertEqual(wallet.requiredSignatures, 2)
        XCTAssertEqual(wallet.totalSigners, 4)
        XCTAssertEqual(wallet.addressFormat, .p2wsh)
        XCTAssertEqual(wallet.chain, "XTN")
        XCTAssertEqual(wallet.cosigners[0].fingerprint, "0F056943")
        XCTAssertEqual(wallet.cosigners[0].derivation, "m/48h/1h/0h/2h")
        let reparsed = try MultisigWalletConfig.fromFirmwareStorageJSON(try wallet.firmwareStorageJSON())
        XCTAssertEqual(reparsed.cosigners.map(\.xpub), wallet.cosigners.map(\.xpub))
        XCTAssertEqual(reparsed.addressFormat, .p2wsh)
        let p2sh = try MultisigWalletConfig.fromFirmwareStorageJSON(Self.firmwareSettingP2SH)
        XCTAssertEqual(p2sh.addressFormat, .p2sh)
        XCTAssertEqual(p2sh.cosigners[0].derivation, "m/45h")
        let wrapped = try MultisigWalletConfig.fromFirmwareStorageJSON(Self.firmwareSettingP2SHP2WSH)
        XCTAssertEqual(wrapped.addressFormat, .p2shP2wsh)
        XCTAssertEqual(wrapped.addressFormat.firmwareCode, 26)
    }

    func testCreateFromFirmwareCCXPJSONFiles() throws {
        let root = try Self.simulatorRoot()
        let context = MultisigImportContext(root: root, allowUnsorted: false, disableChecks: false)
        let wallet = try MultisigWalletConfig.createFromXPUBExports(
            files: Self.firmwareCCXPFiles,
            addressFormat: .p2wsh,
            requiredSignatures: 2,
            includeOwnIfMissing: false,
            context: context
        )
        XCTAssertEqual(wallet.name, "CC-2-of-4")
        XCTAssertEqual(wallet.totalSigners, 4)
        XCTAssertEqual(Set(wallet.cosigners.map(\.fingerprint)),
                       Set(["0F056943", "6BA6CFD0", "747B698E", "7BB026BE"]))
        let json = try MultisigXPUBExport.json(root: root, account: 0)
        XCTAssertTrue(json.contains("Vpub5mtnnUUL8u4oyRf5d2NZJqDypgmpx8FontedpqxNyjXTi6fLp8fmpp2wedS6UyuNpDgLDoVH23c6rYpFSEfB9jhdbD8gek2stjxhwJeE1Eq"))
        XCTAssertTrue(json.contains("\"xfp\": \"0F056943\""))
    }

    func testEnrollmentJSONUnwrapAndCCXPRejection() throws {
        let root = try Self.simulatorRoot()
        let context = MultisigImportContext(root: root, allowUnsorted: false, disableChecks: false)
        let wrapped = """
        {"desc":"\(Self.firmwareDescP2WSH)","name":"JSON-MS"}
        """
        let imported = try MultisigWalletConfig.importFile(wrapped, nameHint: "ignored", context: context)
        XCTAssertEqual(imported.name, "JSON-MS")
        XCTAssertThrowsError(try MultisigWalletConfig.importFile(Self.firmwareCCXPFiles[0], nameHint: nil,
                                                                 context: context)) { error in
            XCTAssertEqual(error as? MultisigError, .missingValue("desc"))
        }
    }

    func testPSBTEnrollmentAndFindMatch() throws {
        let ours = try Self.ourRoot()
        let other = try Self.otherRoot()
        let wallet = try Self.twoOfTwo(ours: ours, other: other)
        let path = try DerivationPath("m/48'/1'/0'/2'")
        let ourNode = try ours.derived(path: path).neutered()
        let otherNode = try other.derived(path: path).neutered()
        let xpubs = [
            try Self.globalXpub(root: ours, path: path, node: ourNode),
            try Self.globalXpub(root: other, path: path, node: otherNode)
        ]
        let context = MultisigImportContext(root: ours, allowUnsorted: false, disableChecks: false)
        XCTAssertThrowsError(try MultisigWalletConfig.importFromPSBT(
            addressFormat: .p2wsh, requiredSignatures: 2, totalSigners: 2, xpubs: xpubs,
            context: context, trust: .verify
        )) { error in
            XCTAssertEqual(error as? MultisigError, .xpubsDoNotMatchExisting)
        }
        let enrolled = try MultisigWalletConfig.importFromPSBT(
            addressFormat: .p2wsh, requiredSignatures: 2, totalSigners: 2, xpubs: xpubs,
            context: context, trust: .offer
        )
        XCTAssertTrue(enrolled.needsApproval)
        XCTAssertEqual(enrolled.wallet.name, "PSBT-2-of-2")
        XCTAssertEqual(enrolled.wallet.totalSigners, 2)
        let matched = try MultisigWalletConfig.resolvePSBT(
            xpubs: xpubs, addressFormat: .p2wsh, requiredSignatures: 2, totalSigners: 2,
            wallets: [wallet], context: context, trust: .verify
        )
        guard case .matched(let found) = matched else {
            return XCTFail("expected existing wallet match")
        }
        XCTAssertEqual(found.name, wallet.name)
        let paths = wallet.xfpPaths()
        XCTAssertEqual(MultisigWalletConfig.findMatch(wallets: [wallet], requiredSignatures: 2,
                                                      totalSigners: 2, xfpPaths: paths)?.name, wallet.name)
        XCTAssertEqual(MultisigTrustPolicy.default(hasWallets: true), .verify)
        XCTAssertEqual(MultisigTrustPolicy.default(hasWallets: false), .offer)
    }

    func testGuessAddressFormatAndPolicyFromPSBT() throws {
        XCTAssertEqual(MultisigWalletConfig.guessAddressFormat(witnessScript: Data([0xae]), redeemScript: nil), .p2wsh)
        XCTAssertEqual(MultisigWalletConfig.guessAddressFormat(witnessScript: Data([0xae]),
                                                               redeemScript: Data([0xa9])), .p2shP2wsh)
        XCTAssertEqual(MultisigWalletConfig.guessAddressFormat(witnessScript: nil, redeemScript: Data([0xae])), .p2sh)
        let ours = try Self.ourRoot()
        let other = try Self.otherRoot()
        let wallet = try Self.twoOfTwo(ours: ours, other: other)
        let derived = try wallet.derivedAddress(change: 0, index: 0, network: .testnet)
        let redeem = try wallet.redeemScript(change: 0, index: 0)
        let utxo = TransactionOutput(value: 50_000, scriptPubKey: try Data(hex: derived.scriptPubKeyHex))
        let dest = try BitcoinAddress.derive(root: ours, type: .nativeSegwit, index: 1)
        let unsigned = BitcoinTransaction(
            inputs: [TransactionInput(previousTxID: Data(repeating: 0x22, count: 32), previousOutputIndex: 0)],
            outputs: [TransactionOutput(value: 49_000, scriptPubKey: try Data(hex: dest.scriptPubKeyHex))]
        )
        let ourPath = try DerivationPath("m/48'/1'/0'/2'/0/0")
        let ourChild = try ours.derived(path: ourPath)
        let otherChild = try other.derived(path: ourPath)
        let ourDerivation = PSBTDerivation(publicKey: ourChild.publicKey, masterFingerprint: ours.fingerprint, path: ourPath)
        let otherDerivation = PSBTDerivation(publicKey: otherChild.publicKey, masterFingerprint: other.fingerprint, path: ourPath)
        let inputMap = PSBTMap(entries: [
            PSBTEntry(key: Data([0x01]), value: utxo.serialize()),
            PSBTEntry(key: Data([0x05]), value: redeem),
            PSBTEntry(key: Data([0x06]) + ourChild.publicKey, value: ourDerivation.encodedValue),
            PSBTEntry(key: Data([0x06]) + otherChild.publicKey, value: otherDerivation.encodedValue)
        ])
        let psbt = try PSBT(unsignedTransaction: unsigned, inputs: [inputMap], outputs: [PSBTMap()])
        let policy = try XCTUnwrap(psbt.guessMultisigPolicy())
        XCTAssertEqual(policy.format, .p2wsh)
        XCTAssertEqual(policy.requiredSignatures, 2)
        XCTAssertEqual(policy.totalSigners, 2)
        XCTAssertEqual(psbt.matchingMultisigWallet(wallets: [wallet])?.name, wallet.name)
        XCTAssertEqual(psbt.review(root: ours, wallets: [wallet]).multisigWalletName, wallet.name)
        XCTAssertEqual(psbt.signed(using: ours).signedInputCount, 1)
    }

    func testMultisigMenuCatalogMatchesFirmware() throws {
        XCTAssertEqual(MultisigMenuLayout.rootLabels(wallets: []), [
            "(none setup yet)", "Import", "Export XPUB", "Create Airgapped",
            "Trust PSBT?", "Skip Checks?", "Full Address View?", "Unsorted Multisig?"
        ])
        let wallet = try Self.twoOfTwo(ours: Self.ourRoot(), other: Self.otherRoot(), name: "House")
        XCTAssertEqual(MultisigMenuLayout.rootLabels(wallets: [wallet]), [
            "2/2: House", "Import", "Export XPUB", "Create Airgapped",
            "Trust PSBT?", "Skip Checks?", "Full Address View?", "Unsorted Multisig?"
        ])
        XCTAssertEqual(MultisigMenuLayout.walletActionLabels(name: "House", bip67: true), [
            "\"House\"", "View Details", "Rename", "Delete",
            "Coldcard Export", "Electrum Wallet", "Descriptors"
        ])
        XCTAssertEqual(MultisigMenuLayout.walletActionLabels(name: "Unsorted", bip67: false), [
            "\"Unsorted\"", "View Details", "Rename", "Delete", "Descriptors"
        ])
        XCTAssertEqual(MultisigMenuLayout.descriptorLabels(), [
            "View Descriptor", "Export", "Bitcoin Core"
        ])
        XCTAssertEqual(MultisigMenuLayout.addressExplorerWalletNames(account: 0, wallets: [wallet]), ["House"])
        XCTAssertEqual(MultisigMenuLayout.addressExplorerWalletNames(account: 1, wallets: [wallet]), [])
        XCTAssertEqual(MultisigMenuLayout.cccWalletRow(wallet), "↳ 2/2: House")
        XCTAssertTrue(wallet.includesFingerprint(try Self.ourRoot().fingerprintHex))
        XCTAssertEqual(
            MultisigMenuLayout.cccRelatedWallets(cccXFP: try Self.ourRoot().fingerprintHex, wallets: [wallet]).map(\.name),
            ["House"]
        )
        XCTAssertFalse(MultisigMenuLayout.qrAndMS(hasQR: true, walletCount: 0))
        XCTAssertTrue(MultisigMenuLayout.qrAndMS(hasQR: true, walletCount: 1))
        XCTAssertFalse(MultisigMenuLayout.qrAndMS(hasQR: false, walletCount: 1))
        XCTAssertEqual(MultisigMenuLayout.trustChoices, ["Verify Only", "Offer Import", "Trust PSBT"])
        XCTAssertEqual(MultisigMenuLayout.skipChoices, ["Normal", "Skip Checks"])
        XCTAssertEqual(MultisigMenuLayout.addressViewChoices, ["Partly Censor", "Show Full"])
        XCTAssertEqual(MultisigMenuLayout.unsortedChoices, ["Do Not Allow", "Allow"])
    }

    private static let abandon = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    /// Firmware `testing/constants.py` `simulator_fixed_tprv`.
    private static let simulatorTPRV = "tprv8ZgxMBicQKsPeXJHL3vPPgTAEqQ5P2FD9qDeCQT4Cp1EMY5QkwMPWFxHdxHrxZhhcVRJ2m7BNWTz9Xre68y7mX5vCdMJ5qXMUfnrZ2si2X4"

    private static func simulatorRoot() throws -> HDKey {
        try HDKey(extendedKey: simulatorTPRV, network: .testnet)
    }

    private static func ourRoot() throws -> HDKey {
        try HDKey(seed: try BIP39Mnemonic(phrase: abandon).seed(), network: .testnet)
    }

    private static func otherRoot() throws -> HDKey {
        try HDKey(seed: Data(repeating: 3, count: 64), network: .testnet)
    }

    private static func twoOfTwo(ours: HDKey, other: HDKey, name: String = "CC-2-of-2") throws -> MultisigWalletConfig {
        let path = try DerivationPath("m/48'/1'/0'/2'")
        return MultisigWalletConfig(
            name: name,
            requiredSignatures: 2,
            totalSigners: 2,
            addressFormat: .p2wsh,
            chain: "XTN",
            bip67: true,
            cosigners: [
                MultisigCosigner(fingerprint: ours.fingerprintHex, derivation: "m/48h/1h/0h/2h",
                                 xpub: try ours.derived(path: path).neutered().serializePublic()),
                MultisigCosigner(fingerprint: other.fingerprintHex, derivation: "m/48h/1h/0h/2h",
                                 xpub: try other.derived(path: path).neutered().serializePublic())
            ]
        )
    }

    private static func globalXpub(root: HDKey, path: DerivationPath, node: HDKey) throws -> PSBTGlobalXpub {
        PSBTGlobalXpub(fingerprint: root.fingerprint, path: path,
                       extendedKey: try Base58.checkDecode(node.serializePublic()))
    }

    /// Firmware `testing/data/multisig/export-p2wsh-myself.txt`
    private static let firmwareExportP2WSH = """
    # Coldcard Multisig setup file (created on 0F056943)
    #
    Name: CC-2-of-4
    Policy: 2 of 4
    Format: P2WSH

    Derivation: m/48'/1'/0'/2'

    0F056943: tpubDF2rnouQaaYrXF4noGTv6rQYmx87cQ4GrUdhpvXkhtChwQPbdGTi8GA88NUaSrwZBwNsTkC9bFkkC8vDyGBVVAQTZ2AS6gs68RQXtXcCvkP
    6BA6CFD0: tpubDFcrvj5n7gyaxWQkoX69k2Zij4vthiAwvN2uhYjDrE6wktKoQaE7gKVZRiTbYdrAYH1UFPGdzdtWJc6WfR2gFMq6XpxA12gCdQmoQNU9mgm
    747B698E: tpubDExj5FnaUnPAn7sHGUeBqD3buoNH5dqmjAT6884vbDpH1iDYWigb7kFo2cA97dc8EHb54u13TRcZxC4kgRS9gc3Ey2xc8c5urytEzTcp3ac
    7BB026BE: tpubDFiuHYSJhNbHcbLJoxWdbjtUcbKR6PvLq53qC1Xq6t93CrRx78W3wcng8vJyQnY3giMJZEgNCRVzTojLb8RqPFpW5Ms2dYpjcJYofN1joyu
    """

    /// Firmware `testing/data/multisig/desc-p2wsh-myself.txt`
    private static let firmwareDescP2WSH = "wsh(sortedmulti(2,[0f056943/48h/1h/0h/2h]tpubDF2rnouQaaYrXF4noGTv6rQYmx87cQ4GrUdhpvXkhtChwQPbdGTi8GA88NUaSrwZBwNsTkC9bFkkC8vDyGBVVAQTZ2AS6gs68RQXtXcCvkP/0/*,[6ba6cfd0/48h/1h/0h/2h]tpubDFcrvj5n7gyaxWQkoX69k2Zij4vthiAwvN2uhYjDrE6wktKoQaE7gKVZRiTbYdrAYH1UFPGdzdtWJc6WfR2gFMq6XpxA12gCdQmoQNU9mgm/0/*,[747b698e/48h/1h/0h/2h]tpubDExj5FnaUnPAn7sHGUeBqD3buoNH5dqmjAT6884vbDpH1iDYWigb7kFo2cA97dc8EHb54u13TRcZxC4kgRS9gc3Ey2xc8c5urytEzTcp3ac/0/*,[7bb026be/48h/1h/0h/2h]tpubDFiuHYSJhNbHcbLJoxWdbjtUcbKR6PvLq53qC1Xq6t93CrRx78W3wcng8vJyQnY3giMJZEgNCRVzTojLb8RqPFpW5Ms2dYpjcJYofN1joyu/0/*))#al5z7mcj"

    /// Firmware `testing/data/multisig/export-p2sh-myself.txt`
    private static let firmwareExportP2SH = """
    # Coldcard Multisig setup file (created on 0F056943)
    #
    Name: CC-2-of-4
    Policy: 2 of 4

    Derivation: m/45'

    0F056943: tpubD8NXmKsmWp3a3DXhbihAYbYLGaRNVdTnr6JoSxxfXYQcmwVtW2hv8QoDwng6JtEonmJoL3cNEwfd2cLXMpGezwZ2vL2dQ7259bueNKj9C8n
    6BA6CFD0: tpubD9429UXFGCTKJ9NdiNK4rC5ygqSUkginycYHccqSg5gkmyQ7PZRHNjk99M6a6Y3NY8ctEUUJvCu6iCCui8Ju3xrHRu3Ez1CKB4ZFoRZDdP9
    747B698E: tpubD97nVL37v5tWyMf9ofh5rznwhh1593WMRg6FT4o6MRJkKWANtwAMHYLrcJFsFmPfYbY1TE1LLQ4KBb84LBPt1ubvFwoosvMkcWJtMwvXgSc
    7BB026BE: tpubD9ArfXowvGHnuECKdGXVKDMfZVGdephVWg8fWGWStH3VKHzT4ph3A4ZcgXWqFu1F5xGTfxncmrnf3sLC86dup2a8Kx7z3xQ3AgeNTQeFxPa
    """

    /// Firmware `testing/data/multisig/desc-p2sh-myself.txt`
    private static let firmwareDescP2SH = "sh(sortedmulti(2,[0f056943/45h]tpubD8NXmKsmWp3a3DXhbihAYbYLGaRNVdTnr6JoSxxfXYQcmwVtW2hv8QoDwng6JtEonmJoL3cNEwfd2cLXMpGezwZ2vL2dQ7259bueNKj9C8n/0/*,[6ba6cfd0/45h]tpubD9429UXFGCTKJ9NdiNK4rC5ygqSUkginycYHccqSg5gkmyQ7PZRHNjk99M6a6Y3NY8ctEUUJvCu6iCCui8Ju3xrHRu3Ez1CKB4ZFoRZDdP9/0/*,[747b698e/45h]tpubD97nVL37v5tWyMf9ofh5rznwhh1593WMRg6FT4o6MRJkKWANtwAMHYLrcJFsFmPfYbY1TE1LLQ4KBb84LBPt1ubvFwoosvMkcWJtMwvXgSc/0/*,[7bb026be/45h]tpubD9ArfXowvGHnuECKdGXVKDMfZVGdephVWg8fWGWStH3VKHzT4ph3A4ZcgXWqFu1F5xGTfxncmrnf3sLC86dup2a8Kx7z3xQ3AgeNTQeFxPa/0/*))#x40t0prf"

    /// Firmware `testing/data/multisig/export-p2sh-p2wsh-myself.txt`
    private static let firmwareExportP2SHP2WSH = """
    # Coldcard Multisig setup file (created on 0F056943)
    #
    Name: CC-2-of-4
    Policy: 2 of 4
    Format: P2SH-P2WSH

    Derivation: m/48'/1'/0'/1'

    0F056943: tpubDF2rnouQaaYrUEy2JM1YD3RFzew4onawGM4X2Re67gguTf5CbHonBRiFGe3Xjz7DK88dxBFGf2i7K1hef3PM4cFKyUjcbJXddaY9F5tJBoP
    6BA6CFD0: tpubDFcrvj5n7gyatVbr8dHCUfHT4CGvL8hREBjtxc4ge7HZgqNuPhFimPRtVg6fRRwfXiQthV9EBjNbwbpgV2VoQeL1ZNXoAWXxP2L9vMtRjax
    747B698E: tpubDExj5FnaUnPAjjgzELoSiNRkuXJG8Cm1pbdiA4Hc5vkAZHphibeVcUp6mqH5LuNVKbtLVZxVSzyja5X26Cfmx6pzRH6gXBUJAH7MiqwNyuM
    7BB026BE: tpubDFiuHYSJhNbHaGtB5skiuDLg12tRboh2uVZ6KGXxr8WVr28pLcS7F3gv8SsHFa2tm1jtx3VAuw56YfgRkdo6DXyfp51oygTKY3nJFT5jBMt
    """

    /// Firmware `testing/data/multisig/desc-p2sh-p2wsh-myself.txt`
    private static let firmwareDescP2SHP2WSH = "sh(wsh(sortedmulti(2,[0f056943/48h/1h/0h/1h]tpubDF2rnouQaaYrUEy2JM1YD3RFzew4onawGM4X2Re67gguTf5CbHonBRiFGe3Xjz7DK88dxBFGf2i7K1hef3PM4cFKyUjcbJXddaY9F5tJBoP/0/*,[6ba6cfd0/48h/1h/0h/1h]tpubDFcrvj5n7gyatVbr8dHCUfHT4CGvL8hREBjtxc4ge7HZgqNuPhFimPRtVg6fRRwfXiQthV9EBjNbwbpgV2VoQeL1ZNXoAWXxP2L9vMtRjax/0/*,[747b698e/48h/1h/0h/1h]tpubDExj5FnaUnPAjjgzELoSiNRkuXJG8Cm1pbdiA4Hc5vkAZHphibeVcUp6mqH5LuNVKbtLVZxVSzyja5X26Cfmx6pzRH6gXBUJAH7MiqwNyuM/0/*,[7bb026be/48h/1h/0h/1h]tpubDFiuHYSJhNbHaGtB5skiuDLg12tRboh2uVZ6KGXxr8WVr28pLcS7F3gv8SsHFa2tm1jtx3VAuw56YfgRkdo6DXyfp51oygTKY3nJFT5jBMt/0/*)))#3ryykxyk"

    /// Firmware `testing/data/multisig/setting-p2wsh-myself.json`
    private static let firmwareSettingP2WSH = #"["CC-2-of-4", [2, 4], [[1130956047, "tpubDF2rnouQaaYrXF4noGTv6rQYmx87cQ4GrUdhpvXkhtChwQPbdGTi8GA88NUaSrwZBwNsTkC9bFkkC8vDyGBVVAQTZ2AS6gs68RQXtXcCvkP"], [3503269483, "tpubDFcrvj5n7gyaxWQkoX69k2Zij4vthiAwvN2uhYjDrE6wktKoQaE7gKVZRiTbYdrAYH1UFPGdzdtWJc6WfR2gFMq6XpxA12gCdQmoQNU9mgm"], [2389277556, "tpubDExj5FnaUnPAn7sHGUeBqD3buoNH5dqmjAT6884vbDpH1iDYWigb7kFo2cA97dc8EHb54u13TRcZxC4kgRS9gc3Ey2xc8c5urytEzTcp3ac"], [3190206587, "tpubDFiuHYSJhNbHcbLJoxWdbjtUcbKR6PvLq53qC1Xq6t93CrRx78W3wcng8vJyQnY3giMJZEgNCRVzTojLb8RqPFpW5Ms2dYpjcJYofN1joyu"]], {"pp": "m/48'/1'/0'/2'", "ch": "XTN", "ft": 14}]"#

    /// Firmware `testing/data/multisig/setting-p2sh-myself.json`
    private static let firmwareSettingP2SH = #"["CC-2-of-4", [2, 4], [[1130956047, "tpubD8NXmKsmWp3a3DXhbihAYbYLGaRNVdTnr6JoSxxfXYQcmwVtW2hv8QoDwng6JtEonmJoL3cNEwfd2cLXMpGezwZ2vL2dQ7259bueNKj9C8n"], [3503269483, "tpubD9429UXFGCTKJ9NdiNK4rC5ygqSUkginycYHccqSg5gkmyQ7PZRHNjk99M6a6Y3NY8ctEUUJvCu6iCCui8Ju3xrHRu3Ez1CKB4ZFoRZDdP9"], [2389277556, "tpubD97nVL37v5tWyMf9ofh5rznwhh1593WMRg6FT4o6MRJkKWANtwAMHYLrcJFsFmPfYbY1TE1LLQ4KBb84LBPt1ubvFwoosvMkcWJtMwvXgSc"], [3190206587, "tpubD9ArfXowvGHnuECKdGXVKDMfZVGdephVWg8fWGWStH3VKHzT4ph3A4ZcgXWqFu1F5xGTfxncmrnf3sLC86dup2a8Kx7z3xQ3AgeNTQeFxPa"]], {"ch": "XTN", "pp": "m/45'"}]"#

    /// Firmware `testing/data/multisig/setting-p2sh-p2wsh-myself.json`
    private static let firmwareSettingP2SHP2WSH = #"["CC-2-of-4", [2, 4], [[1130956047, "tpubDF2rnouQaaYrUEy2JM1YD3RFzew4onawGM4X2Re67gguTf5CbHonBRiFGe3Xjz7DK88dxBFGf2i7K1hef3PM4cFKyUjcbJXddaY9F5tJBoP"], [3503269483, "tpubDFcrvj5n7gyatVbr8dHCUfHT4CGvL8hREBjtxc4ge7HZgqNuPhFimPRtVg6fRRwfXiQthV9EBjNbwbpgV2VoQeL1ZNXoAWXxP2L9vMtRjax"], [2389277556, "tpubDExj5FnaUnPAjjgzELoSiNRkuXJG8Cm1pbdiA4Hc5vkAZHphibeVcUp6mqH5LuNVKbtLVZxVSzyja5X26Cfmx6pzRH6gXBUJAH7MiqwNyuM"], [3190206587, "tpubDFiuHYSJhNbHaGtB5skiuDLg12tRboh2uVZ6KGXxr8WVr28pLcS7F3gv8SsHFa2tm1jtx3VAuw56YfgRkdo6DXyfp51oygTKY3nJFT5jBMt"]], {"pp": "m/48'/1'/0'/1'", "ch": "XTN", "ft": 26}]"#

    /// Firmware `testing/data/multisig/ccxp-*.json`
    private static let firmwareCCXPFiles = [
        """
        {"p2sh_deriv": "m/45'", "p2sh": "tpubD8NXmKsmWp3a3DXhbihAYbYLGaRNVdTnr6JoSxxfXYQcmwVtW2hv8QoDwng6JtEonmJoL3cNEwfd2cLXMpGezwZ2vL2dQ7259bueNKj9C8n", "p2sh_p2wsh_deriv": "m/48'/1'/0'/1'", "p2sh_p2wsh": "Upub5T4XUooQzDXL58NCHk8ZCw9BsRSLCtnyHeZEExAq1XdnBFXiXVrHFuvvmh3TnCR7XmKHxkwqdACv68z7QKT1vwru9L1SZSsw8B2fuBvtSa6", "p2wsh_deriv": "m/48'/1'/0'/2'", "p2wsh": "Vpub5mtnnUUL8u4oyRf5d2NZJqDypgmpx8FontedpqxNyjXTi6fLp8fmpp2wedS6UyuNpDgLDoVH23c6rYpFSEfB9jhdbD8gek2stjxhwJeE1Eq", "account": "0", "xfp": "0F056943"}
        """,
        """
        {"p2sh_deriv": "m/45'", "p2sh": "tpubD9429UXFGCTKJ9NdiNK4rC5ygqSUkginycYHccqSg5gkmyQ7PZRHNjk99M6a6Y3NY8ctEUUJvCu6iCCui8Ju3xrHRu3Ez1CKB4ZFoRZDdP9", "p2sh_p2wsh_deriv": "m/48'/1'/0'/1'", "p2sh_p2wsh": "Upub5TeXciynXKx4VP1282QDUZ1NvxnBjEuTFVEcB8bRXxESQRqRKuJDqseZzj6bTeFZkMbYi4qo9rsQij79EJZUGywajDod8etFscpgaTSShLd", "p2wsh_deriv": "m/48'/1'/0'/2'", "p2wsh": "Vpub5nUnvPehg1VYQh13dGznx1P9moac3SNUrn3qhU9r85RhXabYbSSBNsNNwyR7akozAZJw1SZmRRjry1zY8PWMuw8Ga1vQZ5qzPjKyTDQwtzs", "account": "0", "xfp": "6BA6CFD0"}
        """,
        """
        {"p2sh_deriv": "m/45'", "p2sh": "tpubD97nVL37v5tWyMf9ofh5rznwhh1593WMRg6FT4o6MRJkKWANtwAMHYLrcJFsFmPfYbY1TE1LLQ4KBb84LBPt1ubvFwoosvMkcWJtMwvXgSc", "p2sh_p2wsh_deriv": "m/48'/1'/0'/1'", "p2sh_p2wsh": "Upub5SzPmFgatRMeLd6ADjvTiG9gnHoXXJy3qu8RNapLymh3GtHDeogzgy2nGtH1P7gPYF4zW9f4R8UYMCoUqUjSpSSZb8NWVKpbesbtP21e6Z4", "p2wsh_deriv": "m/48'/1'/0'/2'", "p2wsh": "Vpub5mpf4vMW36u8EJTa6EYq3Bs2xY1zRN3JfaU283VYs592nQVHhatepJ8cYs7f9kZwrZtXpxJAtDTvcbxn9PuqMBLR1DvrgfFhdJSR3Fb5yob", "account": "0", "xfp": "747B698E"}
        """,
        """
        {"p2sh_deriv": "m/45'", "p2sh": "tpubD9ArfXowvGHnuECKdGXVKDMfZVGdephVWg8fWGWStH3VKHzT4ph3A4ZcgXWqFu1F5xGTfxncmrnf3sLC86dup2a8Kx7z3xQ3AgeNTQeFxPa", "p2sh_p2wsh_deriv": "m/48'/1'/0'/1'", "p2sh_p2wsh": "Upub5TkZyYLK71ZmBAHM5Gsju74bsoPgzuu4vo3oXo4hjyTNZcbLGpUcKXubdVsDHnLnyevYxdBjt4ZuKnxtVurm5sbEyvHdwpod2eGpubnG9yQ", "p2wsh_deriv": "m/48'/1'/0'/2'", "p2wsh": "Vpub5naqHD1EFh7F4mvbdiRGoihufKy8S87smV4mBvxTNjTnyYhhHzi7eAfVfBGVSuVsJzemKHyVdDMM8DdN46uX3q7g7YqHBbzXNd6yi8VEVoW", "account": "0", "xfp": "7BB026BE"}
        """
    ]
}

import XCTest
@testable import ColdcardCore

final class DescriptorAndMessageTests: XCTestCase {
    func testDescriptorChecksumFromColdcardDocumentation() {
        let raw = "wpkh([0f056943/84h/0h/123h]xpub6CaWStGvcXqSW9BzU2vpCoP7aWjz9VfR5DS2nuYWVvKV2nug2dESg3HdFsaWHeoZaxuAhNcPB3TH2gq8MugS3JX1yGuhB4QbC2BneaYqB16/<0;1>/*)"
        XCTAssertEqual(DescriptorChecksum.checksum(raw), "yk84tprf")
    }

    func testWalletExportAndMessageSigning() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let json = try WalletExporter.genericJSON(root: root)
        XCTAssertTrue(String(decoding: json, as: UTF8.self).contains("bip84"))
        XCTAssertTrue(String(decoding: json, as: UTF8.self).contains("p2wpkh"))

        let path = try DerivationPath("m/84'/1'/0'/0/0")
        let signed = try BitcoinMessageSigner.sign("Coldcard Q simulator", root: root, path: path, type: .nativeSegwit)
        let compact = try XCTUnwrap(Data(base64Encoded: signed.signatureBase64))
        XCTAssertEqual(compact.count, 65)
        XCTAssertTrue((39...42).contains(compact[0]))
        let child = try root.derived(path: path)
        XCTAssertTrue(Secp256k1.verify(hash: BitcoinMessageSigner.messageHash(signed.message),
                                       derSignature: try SecpTestDER.fromCompact(compact), publicKey: child.publicKey))
        XCTAssertNoThrow(try BitcoinMessageSigner.verify(message: signed.message, address: signed.address,
                                                         signatureBase64: signed.signatureBase64))
        let parsed = try BitcoinMessageSigner.parseArmored(signed.armored)
        XCTAssertEqual(parsed.message, signed.message)
        XCTAssertEqual(parsed.address, signed.address)
        XCTAssertEqual(parsed.signature, signed.signatureBase64)
        let wrapped = try BitcoinMessageSigner.sign("Coldcard Q simulator", root: root,
                                                    path: try DerivationPath("m/49'/1'/0'/0/0"), type: .wrappedSegwit)
        XCTAssertNoThrow(try BitcoinMessageSigner.verify(message: wrapped.message, address: wrapped.address,
                                                         signatureBase64: wrapped.signatureBase64))
        let legacy = try BitcoinMessageSigner.sign("Coldcard Q simulator", root: root,
                                                   path: try DerivationPath("m/44'/1'/0'/0/0"), type: .legacy)
        XCTAssertNoThrow(try BitcoinMessageSigner.verify(message: legacy.message, address: legacy.address,
                                                         signatureBase64: legacy.signatureBase64))
        let hash = SHA2.sha256(Data("file".utf8))
        XCTAssertEqual(BitcoinMessageSigner.fileHashMessage(hashesAndNames: [(hash, "addresses.csv")]),
                       hash.hexString + "  addresses.csv")
        let listed = BitcoinMessageSigner.parseFileHashMessage(hash.hexString + "  addresses.csv")
        XCTAssertEqual(listed?.count, 1)
        XCTAssertEqual(listed?.first?.filename, "addresses.csv")
    }

    func testMessageValidationMatchesFirmware() {
        XCTAssertNoThrow(try BitcoinMessageSigner.validate("Hello Coldcard"))
        XCTAssertThrowsError(try BitcoinMessageSigner.validate(" leading"))
        XCTAssertThrowsError(try BitcoinMessageSigner.validate("trailing "))
        XCTAssertThrowsError(try BitcoinMessageSigner.validate("too   many"))
        XCTAssertThrowsError(try BitcoinMessageSigner.validate("x"))
        XCTAssertEqual(BitcoinMessageSigner.addressType(fromSubpath: "m/84h/1h/0h/0/0"), .nativeSegwit)
        XCTAssertEqual(BitcoinMessageSigner.addressType(fromSubpath: "m/49h/1h/0h/0/0"), .wrappedSegwit)
        XCTAssertEqual(BitcoinMessageSigner.addressType(fromSubpath: "m/44h/1h/0h/0/0"), .legacy)
        XCTAssertEqual(BitcoinMessageSigner.addressType(fromSubpath: ""), .legacy)
        XCTAssertEqual(BitcoinMessageSigner.signatureFilename(forInputFilename: "note.txt"), "note.sig")
        XCTAssertEqual(BitcoinMessageSigner.signedMessageFilename(forInputFilename: "note.txt"), "note-signed.txt")
        let sparrow = BitcoinMessageSigner.parseSignRequest("signmessage m/84'/1'/0'/0/0 ascii:hello there")
        XCTAssertEqual(sparrow?.message, "hello there")
        XCTAssertEqual(sparrow?.subpath, "m/84'/1'/0'/0/0")
        XCTAssertEqual(sparrow?.addressType, .nativeSegwit)
        let json = BitcoinMessageSigner.parseSignRequest("{\"msg\":\"hi there\",\"subpath\":\"m/44'/1'/0'/0/0\"}")
        XCTAssertEqual(json?.message, "hi there")
        XCTAssertEqual(json?.addressType, .legacy)
        let jsonFmt = BitcoinMessageSigner.parseSignRequest("{\"msg\":\"hi there\",\"subpath\":\"m/44'/1'/0'/0/0\",\"addr_fmt\":\"p2wpkh\"}")
        XCTAssertEqual(jsonFmt?.addressType, .nativeSegwit)
        let threeLine = BitcoinMessageSigner.parseSignRequest("hello there\nm/49'/1'/0'/0/0\np2pkh")
        XCTAssertEqual(threeLine?.message, "hello there")
        XCTAssertEqual(threeLine?.addressType, .legacy)
        let armored = SignedBitcoinMessage(message: "hi", address: "tb1q", signatureBase64: "xx", path: "m")
        XCTAssertTrue(armored.armored.hasSuffix("-----\n"))
    }

    /// Firmware `sign_with_own_address` uses `ux_input_text` default `max_len=100`.
    /// USB / SD / NFC / notes use `MSG_SIGNING_MAX_LENGTH` (240) in `validate_text_for_signing`.
    func testOwnAddressAndUSBMessageLengthLimits() {
        XCTAssertEqual(BitcoinMessageSigner.uxInputMaximumLength, 100)
        XCTAssertEqual(BitcoinMessageSigner.maximumLength, 240)

        let ownAddressOK = String(repeating: "a", count: 100)
        let ownAddressTooLong = String(repeating: "a", count: 101)
        XCTAssertNoThrow(try BitcoinMessageSigner.validate(ownAddressOK))
        XCTAssertThrowsError(try BitcoinMessageSigner.validate(ownAddressTooLong)) { error in
            XCTAssertEqual(error as? MessageSigningError, .tooLong(100))
        }

        let usbOK = String(repeating: "a", count: 240)
        let usbTooLong = String(repeating: "a", count: 241)
        XCTAssertNoThrow(try BitcoinMessageSigner.validate(usbOK, maxLength: BitcoinMessageSigner.maximumLength))
        XCTAssertThrowsError(try BitcoinMessageSigner.validate(usbTooLong, maxLength: BitcoinMessageSigner.maximumLength)) { error in
            XCTAssertEqual(error as? MessageSigningError, .tooLong(240))
        }
        XCTAssertThrowsError(try BitcoinMessageSigner.validate(usbTooLong))
    }

    /// Firmware `parse_msg_sign_request`: JSON that parses but has missing/null `msg`
    /// raises `AssertionError("MSG required")` and must not fall through to line parsing.
    func testParseSignRequestJSONMissingMsgDoesNotFallThrough() {
        XCTAssertNil(BitcoinMessageSigner.parseSignRequest("{\"subpath\":\"m/44'/1'/0'/0/0\"}"))
        XCTAssertNil(BitcoinMessageSigner.parseSignRequest("{\"msg\":null,\"subpath\":\"m/44'/1'/0'/0/0\"}"))
        XCTAssertNil(BitcoinMessageSigner.parseSignRequest("{\n  \"subpath\": \"m/44'/1'/0'/0/0\"\n}"))
        XCTAssertNil(BitcoinMessageSigner.parseSignRequest("{\"msg\":123}"))
        XCTAssertNil(BitcoinMessageSigner.parseSignRequest("{\"msg\":\"hello\",\"subpath\":1}"))

        let valid = BitcoinMessageSigner.parseSignRequest("{\"msg\":\"hi there\",\"subpath\":\"m/44'/1'/0'/0/0\"}")
        XCTAssertEqual(valid?.message, "hi there")
        XCTAssertEqual(valid?.subpath, "m/44'/1'/0'/0/0")

        let line = BitcoinMessageSigner.parseSignRequest("hello there")
        XCTAssertEqual(line?.message, "hello there")
        XCTAssertEqual(valid?.allowTabAndNewline, true)
        XCTAssertEqual(line?.allowTabAndNewline, false)
        XCTAssertFalse(BitcoinMessageSigner.isQRSignMessagePayload("hello there"))
        XCTAssertTrue(BitcoinMessageSigner.isQRSignMessagePayload("signmessage m/84'/1'/0'/0/0 ascii:hello there"))
        XCTAssertTrue(BitcoinMessageSigner.isQRSignMessagePayload("{\"msg\":\"hi there\"}"))
        XCTAssertTrue(BitcoinMessageSigner.isQRSignMessagePayload("{\"msg\":null}"))
        let short = BitcoinMessageSigner.simpleTextQRDisplay("hello there")
        XCTAssertEqual(short.shown, "hello there")
        XCTAssertTrue(short.canSign)
        let long = String(repeating: "a", count: 241)
        let truncated = BitcoinMessageSigner.simpleTextQRDisplay(long)
        XCTAssertEqual(truncated.shown, String(repeating: "a", count: 240) + "...")
        XCTAssertFalse(truncated.canSign)
    }

    func testDisplayUnitsAndNamedExports() throws {
        XCTAssertEqual(DisplayUnits.btc.format(100_000_000, network: .mainnet), "1.00000000 BTC")
        XCTAssertEqual(DisplayUnits.btc.format(10_000_000, network: .testnet), "0.10000000 XTN")
        XCTAssertEqual(DisplayUnits.sats.format(21, network: .testnet), "21 sats")
        XCTAssertFalse(DisplayUnits.btc.format(123_456_789, network: .mainnet).contains(","))
        XCTAssertEqual(DisplayUnits.mbtc.format(10_000_000, network: .regtest), "100.00000 mXRT")
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let wasabi = try WalletExporter.wasabiWallet(root: root)
        let wasabiObject = try XCTUnwrap(JSONSerialization.jsonObject(with: wasabi) as? [String: Any])
        XCTAssertEqual(wasabiObject["ColdCardFirmwareVersion"] as? String, WalletExporter.coldcardFirmwareVersion)
        XCTAssertEqual(WalletExporter.coldcardFirmwareVersion, "1.5.0Q")
        XCTAssertTrue((wasabiObject["ExtPubKey"] as? String)?.hasPrefix("xpub") == true)
        XCTAssertNotNil(wasabiObject["MasterFingerprint"] as? String)
        let generic = String(decoding: try WalletExporter.genericJSON(root: root), as: UTF8.self)
        XCTAssertTrue(generic.contains("bip48_1"))
        XCTAssertTrue(generic.contains("bip48_2"))
        let electrum = String(decoding: try WalletExporter.electrumWallet(root: root, type: .legacy), as: UTF8.self)
        XCTAssertTrue(electrum.contains("\"ckcc_xfp\" : \(Int(root.ckccXFP))")
                      || electrum.contains("\"ckcc_xfp\": \(Int(root.ckccXFP))"))
        XCTAssertTrue(try WalletExporter.dumpSummary(root: root).contains("Coldcard Wallet Summary File"))
        XCTAssertTrue(try WalletExporter.keyExpression(root: root, type: .nativeSegwit).hasPrefix("["))
        XCTAssertEqual(WalletExporter.truncateAddress("tb1qabcdefghijklmnopqrstuvwxyz1234567890abcd"), "tb1qabcdefgh⋯34567890abcd")
        let core = try WalletExporter.bitcoinCore(root: root)
        XCTAssertTrue(core.contains("importmulti"))
        XCTAssertTrue(core.contains("\"internal\": false") || core.contains("\"internal\":false"))
        XCTAssertTrue(core.contains("\"range\": [0, 100]") || core.contains("\"range\":[0,100]"))
        let combined = try WalletExporter.descriptorExport(root: root, type: .nativeSegwit, combined: true)
        XCTAssertTrue(combined.contains("<0;1>"))
        let split = try WalletExporter.descriptorExport(root: root, type: .nativeSegwit, combined: false)
        XCTAssertFalse(split.contains("<0;1>"))
        XCTAssertTrue(split.contains("/0/*"))
        XCTAssertTrue(split.contains("/1/*"))
        let summary = try WalletExporter.dumpSummary(root: root)
        XCTAssertTrue(summary.contains("## For BIP-44 / Electrum:"))
        XCTAssertTrue(summary.contains("##SLIP-132##"))
        let unchained = String(decoding: try WalletExporter.unchained(root: root), as: UTF8.self)
        XCTAssertTrue(unchained.contains("Vpub") || unchained.contains("vpub") || unchained.contains("\"p2wsh\""))
        XCTAssertTrue(electrum.contains("Coldcard Import"))
        XCTAssertFalse(electrum.contains("Blue "))
    }

    func testValidateUsesASCIIByteLengthAndFirmwareCopy() {
        XCTAssertEqual(try BitcoinMessageSigner.validate("Hello Coldcard"), "Hello Coldcard")
        XCTAssertThrowsError(try BitcoinMessageSigner.validate(" leading")) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "leading space(s) in msg")
        }
        XCTAssertThrowsError(try BitcoinMessageSigner.validate("trailing ")) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "trailing space(s) in msg")
        }
        XCTAssertThrowsError(try BitcoinMessageSigner.validate("too   many")) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "too many spaces together in msg(max. 3)")
        }
        XCTAssertThrowsError(try BitcoinMessageSigner.validate("x")) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "msg too short (min. 2)")
        }
        XCTAssertThrowsError(try BitcoinMessageSigner.validate("café")) { error in
            XCTAssertEqual(error as? MessageSigningError, .mustBeAsciiPrintable)
        }
        XCTAssertThrowsError(try BitcoinMessageSigner.validate("ok\tno")) { error in
            XCTAssertEqual(error as? MessageSigningError, .mustBeAsciiPrintable)
        }
        XCTAssertEqual(try BitcoinMessageSigner.validate("ok\tno", allowTabAndNewline: true), "ok\tno")
        XCTAssertThrowsError(try BitcoinMessageSigner.validate("ok\u{0001}no", allowTabAndNewline: true)) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription,
                           "must be ascii printable, tab, or newline")
        }
        let ascii240 = String(repeating: "a", count: 240)
        XCTAssertNoThrow(try BitcoinMessageSigner.validate(ascii240, maxLength: BitcoinMessageSigner.maximumLength))
        XCTAssertThrowsError(try BitcoinMessageSigner.validate(ascii240 + "a",
                                                               maxLength: BitcoinMessageSigner.maximumLength)) { error in
            XCTAssertEqual(error as? MessageSigningError, .tooLong(240))
        }
    }

    func testSparrowSignRequestKeepsEmptyFieldsAndSkipsLeadingSpace() {
        let ok = BitcoinMessageSigner.parseSignRequest("signmessage m/84'/1'/0'/0/0 ascii:hello there")
        XCTAssertEqual(ok?.message, "hello there")
        XCTAssertEqual(ok?.subpath, "m/84'/1'/0'/0/0")
        XCTAssertEqual(ok?.addressType, .nativeSegwit)

        // Two spaces after the mark → empty subpath field; third token is not `ascii:`.
        let collapsed = BitcoinMessageSigner.parseSignRequest("signmessage  m/84'/1'/0'/0/0 ascii:hello")
        XCTAssertNotEqual(collapsed?.message, "hello")

        let emptyPath = BitcoinMessageSigner.parseSignRequest("signmessage  ascii:hello")
        XCTAssertEqual(emptyPath?.message, "hello")
        XCTAssertEqual(emptyPath?.subpath, "")
        XCTAssertEqual(emptyPath?.addressType, .legacy)

        // Firmware does not trim before `split(" ", 2)`, so a leading space is not Sparrow.
        let leading = BitcoinMessageSigner.parseSignRequest("  signmessage m/84'/1'/0'/0/0 ascii:hello")
        XCTAssertNotEqual(leading?.subpath, "m/84'/1'/0'/0/0")
    }

    func testVerifyArmoredStoriesMatchFirmware() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let path = try DerivationPath("m/44'/1'/0'/0/0")
        let signed = try BitcoinMessageSigner.sign("coldcard", root: root, path: path, type: .legacy)

        let correct = BitcoinMessageSigner.verifyArmoredSignedMessage(signed.armored, digestCheck: false)
        XCTAssertEqual(correct.title, "CORRECT")
        XCTAssertTrue(correct.body.hasPrefix("Good signature by address:\n"))
        XCTAssertTrue(correct.body.contains(signed.address))

        var wrongHeader = Data(base64Encoded: signed.signatureBase64)!
        wrongHeader[0] = 39 + (wrongHeader[0] - 31)  // p2wpkh header on a p2pkh address
        let warnedArmor = SignedBitcoinMessage(message: signed.message, address: signed.address,
                                               signatureBase64: wrongHeader.base64EncodedString(),
                                               path: signed.path).armored
        let warned = BitcoinMessageSigner.verifyArmoredSignedMessage(warnedArmor, digestCheck: false)
        XCTAssertEqual(warned.title, "CORRECT")
        XCTAssertTrue(warned.body.hasPrefix("Correctly signed, but not by this Coldcard. "))
        XCTAssertTrue(warned.body.contains("Specified address format does not match signature header byte format."))

        let truncated = String(signed.armored.dropFirst())
        let failure = BitcoinMessageSigner.verifyArmoredSignedMessage(truncated, digestCheck: false)
        XCTAssertEqual(failure.title, "FAILURE")
        XCTAssertTrue(failure.body.hasPrefix("Malformed signature file. "))
        XCTAssertTrue(failure.body.contains("Armor text MUST be surrounded by exactly five (5) dashes."))

        let p2tr = signed.armored.replacingOccurrences(of: signed.address,
            with: "bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y")
        let badFmt = BitcoinMessageSigner.verifyArmoredSignedMessage(p2tr, digestCheck: false)
        XCTAssertEqual(badFmt.title, "ERROR")
        XCTAssertEqual(badFmt.body, "Invalid address format - must be one of p2pkh, p2sh-p2wpkh, or p2wpkh.")

        let junkSig = SignedBitcoinMessage(message: "aaaaaaaaa",
                                           address: "tb1qk3vdwdewzqkmagakdxfga3nrqgxnpw74h4w5p4",
                                           signatureBase64: String(repeating: "$", count: 88),
                                           path: "m").armored
        let parsedFail = BitcoinMessageSigner.verifyArmoredSignedMessage(junkSig, digestCheck: false)
        XCTAssertEqual(parsedFail.title, "ERROR")
        XCTAssertTrue(parsedFail.body.contains("Parsing signature failed"))
    }

    func testVerifySignedFileDigestCopy() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let contents = Data(repeating: 0x30, count: 100)
        let origDigest = SHA2.sha256(contents).hexString
        let message = BitcoinMessageSigner.fileHashMessage(hashesAndNames: [(SHA2.sha256(contents), "to_sign.txt")])
        let path = try DerivationPath("m/44'/1'/0'/0/0")
        let signed = try BitcoinMessageSigner.sign(message, root: root, path: path, type: .legacy)

        let matching = BitcoinMessageSigner.verifyArmoredSignedMessage(
            signed.armored, digestCheck: true, fileBytes: { name in
                name == "to_sign.txt" ? contents : nil
            }
        )
        XCTAssertEqual(matching.title, "CORRECT")
        XCTAssertTrue(matching.body.hasPrefix("Good signature by address:\n"))

        let missing = BitcoinMessageSigner.verifyArmoredSignedMessage(
            signed.armored, digestCheck: true, fileBytes: { _ in nil }
        )
        XCTAssertEqual(missing.title, "WARNING")
        XCTAssertTrue(missing.body.contains("Good signature by address:"))
        XCTAssertTrue(missing.body.contains("'to_sign.txt' is not present. Contents verification not possible."))

        let changed = Data("changed".utf8)
        let modDigest = SHA2.sha256(changed).hexString
        let mismatch = BitcoinMessageSigner.verifyArmoredSignedMessage(
            signed.armored, digestCheck: true, fileBytes: { _ in changed }
        )
        XCTAssertEqual(mismatch.title, "ERROR")
        XCTAssertTrue(mismatch.body.contains("Referenced file 'to_sign.txt' has wrong contents."))
        XCTAssertTrue(mismatch.body.contains("Got:\n\(origDigest)"))
        XCTAssertTrue(mismatch.body.contains("Expected:\n\(modDigest)"))

        let nfcSkips = BitcoinMessageSigner.verifyArmoredSignedMessage(
            signed.armored, digestCheck: false, fileBytes: { _ in nil }
        )
        XCTAssertEqual(nfcSkips.title, "CORRECT")
        XCTAssertFalse(nfcSkips.body.contains("not present"))

        let twoMissing = BitcoinMessageSigner.fileHashMessage(hashesAndNames: [
            (SHA2.sha256(contents), "a.txt"),
            (SHA2.sha256(contents), "b.txt")
        ])
        let signedTwo = try BitcoinMessageSigner.sign(twoMissing, root: root, path: path, type: .legacy,
                                                      allowTabAndNewline: true)
        let multi = BitcoinMessageSigner.verifyArmoredSignedMessage(
            signedTwo.armored, digestCheck: true, fileBytes: { _ in nil }
        )
        XCTAssertEqual(multi.title, "WARNING")
        XCTAssertTrue(multi.body.contains("Files:\n> a.txt\n> b.txt\nare not present. Contents verification not possible."))
    }

    func testKeyExpressionKindsMatchFirmwareDerivations() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let xfp = root.fingerprint.hexString.lowercased()

        let segwit = try WalletExporter.keyExpression(root: root, type: .nativeSegwit)
        XCTAssertTrue(segwit.hasPrefix("[\(xfp)/84h/1h/0h]tpub"))
        let classic = try WalletExporter.keyExpression(root: root, type: .legacy)
        XCTAssertTrue(classic.hasPrefix("[\(xfp)/44h/1h/0h]tpub"))
        let wrapped = try WalletExporter.keyExpression(root: root, type: .wrappedSegwit)
        XCTAssertTrue(wrapped.hasPrefix("[\(xfp)/49h/1h/0h]tpub"))

        let multiWSH = try WalletExporter.keyExpression(root: root, path: DerivationPath("m/48'/1'/0'/2'"))
        XCTAssertTrue(multiWSH.hasPrefix("[\(xfp)/48h/1h/0h/2h]tpub"))
        let multiSH = try WalletExporter.keyExpression(root: root, path: DerivationPath("m/48'/1'/0'/1'"))
        XCTAssertTrue(multiSH.hasPrefix("[\(xfp)/48h/1h/0h/1h]tpub"))
        XCTAssertNotEqual(multiWSH, multiSH)
    }

    func testAddressSummaryCSVMatchesFirmwareHeader() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let address = try BitcoinAddress.derive(root: root, type: .nativeSegwit, account: 0, change: false, index: 0)
        let csv = WalletExporter.addressSummaryCSV(addresses: [address])
        XCTAssertTrue(csv.hasPrefix("\"Index\",\"Payment Address\",\"Derivation\"\n"))
        XCTAssertTrue(csv.contains(address.address))
        XCTAssertTrue(csv.contains(address.path))
    }
}

private enum SecpTestDER {
    static func fromCompact(_ compact: Data) throws -> Data {
        func integer(_ data: Data) -> Data {
            var value = Array(data.drop { $0 == 0 })
            if value.isEmpty { value = [0] }
            if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
            return Data([0x02, UInt8(value.count)] + value)
        }
        let r = integer(compact.subdata(in: 1..<33))
        let s = integer(compact.subdata(in: 33..<65))
        return Data([0x30, UInt8(r.count + s.count)]) + r + s
    }
}

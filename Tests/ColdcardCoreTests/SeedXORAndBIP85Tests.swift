import XCTest
@testable import ColdcardCore

final class SeedXORAndBIP85Tests: XCTestCase {
    func testXORRoundTripDeterministic() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let entropy = mnemonic.entropy
        let parts = try SeedXOR.split(entropy, parts: 2)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(try SeedXOR.combine(parts), entropy)
        let again = try SeedXOR.split(entropy, parts: 2)
        XCTAssertEqual(parts, again)
        XCTAssertEqual(try BIP39Mnemonic(entropy: parts[0]).words.count, 12)
    }

    func testXORThreePartsAndZeroDetect() throws {
        let mnemonic = try BIP39Mnemonic(entropy: Data(repeating: 7, count: 32))
        let parts = try SeedXOR.split(mnemonic.entropy, parts: 3)
        XCTAssertEqual(try SeedXOR.combine(parts), mnemonic.entropy)
        XCTAssertTrue(try SeedXOR.combine([Data(repeating: 1, count: 16), Data(repeating: 1, count: 16)]).allSatisfy { $0 == 0 })
    }

    func testBIP85KindMenuIsUntitledAndUsesFirmwareLabels() {
        XCTAssertEqual(BIP85MenuCopy.kindMenuTitle, "")
        XCTAssertEqual(BIP85Kind.allCases.map(\.menuTitle), [
            "12 words", "18 words", "24 words", "WIF (privkey)",
            "XPRV (BIP-32)", "32-bytes hex", "64-bytes hex", "Passwords"
        ])
    }

    func testBIP85PasswordAndWords() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let words = try BIP85.derive(root: root, kind: .words12, index: 0)
        let derived = try BIP39Mnemonic(entropy: words.entropy)
        XCTAssertEqual(derived.words.count, 12)
        XCTAssertFalse(words.derivedXFP?.isEmpty ?? true)
        let pw = try BIP85.derive(root: root, kind: .password, index: 0)
        XCTAssertEqual(pw.qr.count, 21)
        XCTAssertEqual(pw.path, "m/83696968h/707764h/21h/0h")
        let hex = try BIP85.derive(root: root, kind: .hex32, index: 0)
        XCTAssertEqual(hex.entropy.count, 32)
        let xprv = try BIP85.derive(root: root, kind: .xprv, index: 0)
        XCTAssertTrue(xprv.qr.hasPrefix("tprv") || xprv.qr.hasPrefix("xprv"))
    }

    func testBIP322TaggedHashAndToSpend() {
        let hash = BIP322.messageHash("hello")
        XCTAssertEqual(hash.count, 32)
        let challenge = Data(repeating: 0x51, count: 1) + Data([0x20]) + Data(repeating: 2, count: 32)
        let tx = BIP322.toSpend(messageHash: hash, challenge: challenge)
        XCTAssertEqual(tx.version, 0)
        XCTAssertEqual(tx.inputs[0].previousOutputIndex, 0xffff_ffff)
        XCTAssertEqual(tx.outputs[0].value, 0)
        XCTAssertEqual(BIP322.addressFormatName(Data([0x00, 0x14]) + Data(repeating: 1, count: 20)), "p2wpkh")
        XCTAssertNil(BIP322.relativeTimelock(sequence: 0xffff_ffff))
        XCTAssertEqual(BIP322.relativeTimelock(sequence: 6)?.value, 6)
    }

    func testXORPartWordLayoutMatchesQFirmware() throws {
        let twelve = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").words
        let rendered12 = SeedXOR.renderPartWords(twelve)
        XCTAssertTrue(rendered12.contains(" 1: abandon     7: abandon"))
        XCTAssertTrue(rendered12.contains(" 6: abandon    12: about"))
        XCTAssertEqual(rendered12.split(whereSeparator: \.isNewline).count, 6)

        let entropy24 = Data(repeating: 7, count: 32)
        let twentyFour = try BIP39Mnemonic(entropy: entropy24).words
        let rendered24 = SeedXOR.renderPartWords(twentyFour)
        XCTAssertTrue(rendered24.hasPrefix("1:"))
        XCTAssertTrue(rendered24.contains(" 9:"))
        XCTAssertTrue(rendered24.contains("17:"))
        XCTAssertEqual(rendered24.split(whereSeparator: \.isNewline).count, 8)

        let entropy18 = Data(repeating: 3, count: 24)
        let eighteen = try BIP39Mnemonic(entropy: entropy18).words
        XCTAssertEqual(eighteen.count, 18)
        let rendered18 = SeedXOR.renderPartWords(eighteen)
        XCTAssertTrue(rendered18.hasPrefix("1:"))
        XCTAssertTrue(rendered18.contains(" 7:"))
        XCTAssertTrue(rendered18.contains("13:"))
        XCTAssertEqual(rendered18.split(whereSeparator: \.isNewline).count, 6)
    }

    func testXORStoriesMatchFirmwareCopy() {
        XCTAssertTrue(SeedXORStories.splitIntro.contains("We recommend spliting into just two parts"))
        XCTAssertTrue(SeedXORStories.splitIntro.hasSuffix("into. \n") || SeedXORStories.splitIntro.hasSuffix("into. "))
        XCTAssertEqual(SeedXORStories.splitIntoTitle(3), "Split Into 3 Parts")
        XCTAssertTrue(SeedXORStories.splitIntoParts(2).contains("press (2). Otherwise, press ENTER to continue."))
        XCTAssertEqual(
            SeedXORStories.quizPassed,
            "Quiz Passed!\n\nYou have confirmed the details of the new split."
        )
        XCTAssertEqual(SeedXORStories.quizTitle(partIndex: 0, wordNumber: 7), "Word A7 is?")
        XCTAssertEqual(SeedXORStories.quizTitle(partIndex: 1, wordNumber: 1), "Word B1 is?")
        XCTAssertTrue(SeedXORStories.restoreIntro().contains("Press ENTER for 24 words XOR, press (1) for 12 words XOR"))
        XCTAssertFalse(SeedXORStories.restoreExistingSeed(canIncludeCurrent: false).contains("Press (1)"))
        XCTAssertTrue(SeedXORStories.restoreExistingSeed(canIncludeCurrent: true).contains("Press (1) to include this Coldcard's seed words"))
        XCTAssertTrue(SeedXORStories.restoreVault(matchingCount: 3).contains("and then (1) to select seeds"))
        let progress = SeedXORStories.restoreProgress(
            partsEntered: 2, wordCount: 24, checksumWord: "about", zeroWarning: true
        )
        XCTAssertTrue(progress.contains("You've entered 2 parts so far."))
        XCTAssertTrue(progress.contains("24: about"))
        XCTAssertTrue(progress.contains("ZERO WARNING"))
        XCTAssertTrue(progress.contains("Or (2) if done with all words."))
        XCTAssertEqual(
            SeedXORStories.ephemeralOrigin(parts: 2, checksumWord: "about"),
            "SeedXOR(2 parts, check: \"about\")"
        )
        XCTAssertEqual(SeedXORStories.vaultPickLabel(vaultIndex: 0, fingerprint: "[ABCD1234]"), " 0: [ABCD1234]")
        XCTAssertEqual(SeedXORStories.generatingPause, "Generating...")
        XCTAssertTrue(SeedXORStories.splitIntro.contains("Press 2, 3 or 4 to select number of parts"))
        XCTAssertTrue(SeedXORStories.splitIntoParts(4).contains("If you would prefer a random split using the TRNG, press (2)."))
        XCTAssertEqual(SeedXORStories.recordPartsTitle, "Record these:")
        XCTAssertTrue(SeedXORStories.quizPassed.hasPrefix("Quiz Passed!"))
        XCTAssertTrue(SeedXORStories.restoreProgress(
            partsEntered: 1, wordCount: 24, checksumWord: nil, zeroWarning: false
        ).contains("You've entered 1 parts so far."))
    }

    func testXORRecordPartsUsesQWordLayout() throws {
        let words = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").words
        let recorded = SeedXORStories.recordParts(wordLists: [words, words], checksumWord: "about")
        XCTAssertTrue(recorded.hasPrefix("2 lists of 12-words each:"))
        XCTAssertTrue(recorded.contains("Part A:"))
        XCTAssertTrue(recorded.contains(" 1: abandon     7: abandon"))
        XCTAssertTrue(recorded.contains("12: about"))
        XCTAssertTrue(recorded.contains("Please check and double check your notes. There will be a test! "))
        XCTAssertFalse(recorded.contains("QR key shows"))
        XCTAssertFalse(recorded.contains("Press (4) to view QR Codes"))
    }
}

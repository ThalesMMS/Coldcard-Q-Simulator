import XCTest
@testable import ColdcardCore

final class TrickPinTests: XCTestCase {
    func testDeltaPINValidationVectors() {
        let cases: [(String, String, Bool, UInt16)] = [
            ("12-12", "23-23", false, 0x1212),
            ("99-99", "23-23", false, 0x9999),
            ("123-123", "44-44", true, 0),
            ("123-123", "444-444", true, 0),
            ("123-123", "443-123", true, 0),
            ("443-123", "444-444", false, 0x3123),
            ("123-121", "123-124", false, 0xfff1),
            ("123-122", "123-144", false, 0xff22),
            ("123-123", "123-444", false, 0xf123),
            ("123-124", "124-444", false, 0x312f)
        ]
        for (truePIN, fake, expectProblem, expectArg) in cases {
            let (problem, arg) = TrickPins.validateDeltaPIN(truePIN: truePIN, proposed: fake)
            XCTAssertEqual(problem != nil, expectProblem, "\(truePIN) vs \(fake)")
            XCTAssertEqual(arg, expectArg, "\(truePIN) vs \(fake)")
        }
    }

    func testBrickTrickLoginDoesNotLookLikeWrongPIN() throws {
        var table = TrickPinTable()
        try table.add(pin: "11-11", flags: .brick, arg: 0)
        XCTAssertEqual(table.decision(forPIN: "11-11"), .brick(wipeSeed: false))
        XCTAssertEqual(table.decision(forPIN: "12-12"), .notATrick)
    }

    func testSilentWipePretendsWrongAfterWipe() throws {
        var table = TrickPinTable()
        try table.add(pin: "22-22", flags: [.wipe, .fakeOut], arg: 0)
        XCTAssertEqual(table.decision(forPIN: "22-22"), .fakeWrongPIN(wipeSeed: true))
    }

    func testSayWipedStopLockup() throws {
        var table = TrickPinTable()
        try table.add(pin: "33-33", flags: .wipe, arg: 0)
        XCTAssertEqual(table.decision(forPIN: "33-33"), .wipeLockup)
    }

    func testDuressWordWalletLogin() throws {
        var table = TrickPinTable()
        let entropy = Data(repeating: 7, count: 32)
        try table.add(pin: "44-44", flags: .wordWallet, arg: 1001, xdata: entropy)
        let decision = table.decision(forPIN: "44-44")
        guard case .login(let session) = decision else {
            return XCTFail("expected duress login")
        }
        XCTAssertEqual(session.wallet, .words(entropy))
        XCTAssertFalse(session.wipeSeed)
        XCTAssertFalse(session.deltaMode)
    }

    func testWipeThenDuressWallet() throws {
        var table = TrickPinTable()
        let entropy = Data(repeating: 9, count: 16)
        try table.add(pin: "55-55", flags: [.wipe, .wordWallet], arg: 2001, xdata: entropy)
        guard case .login(let session) = table.decision(forPIN: "55-55") else {
            return XCTFail("expected login")
        }
        XCTAssertTrue(session.wipeSeed)
        XCTAssertEqual(session.wallet, .words(entropy))
    }

    func testDeltaModeLogin() throws {
        var table = TrickPinTable()
        try table.add(pin: "123-124", flags: .deltaMode, arg: 0xfff1)
        guard case .login(let session) = table.decision(forPIN: "123-124") else {
            return XCTFail("expected delta login")
        }
        XCTAssertTrue(session.deltaMode)
        XCTAssertEqual(session.wallet, .realSeed)
    }

    func testWrongPINCatchallAfterNFailures() throws {
        var table = TrickPinTable()
        try table.add(pin: TrickPins.wrongPINCode, flags: .wipe, arg: 3)
        XCTAssertEqual(table.wrongPINDecision(failCount: 2), .notATrick)
        XCTAssertEqual(table.wrongPINDecision(failCount: 3), .wipeLockup)
    }

    func testWrongPINLastChanceWipesThenBricks() throws {
        var table = TrickPinTable()
        try table.add(pin: TrickPins.wrongPINCode, flags: [.wipe, .brick], arg: 2)
        XCTAssertEqual(table.wrongPINDecision(failCount: 1), .notATrick)
        XCTAssertEqual(table.wrongPINDecision(failCount: 2), .brick(wipeSeed: true))
    }

    func testRebootAndBlankAndCountdown() throws {
        var table = TrickPinTable()
        try table.add(pin: "66-66", flags: .reboot, arg: 0)
        XCTAssertEqual(table.decision(forPIN: "66-66"), .reboot(wipeSeed: false))
        try table.add(pin: "77-77", flags: .blankWallet, arg: 0)
        guard case .login(let blank) = table.decision(forPIN: "77-77") else {
            return XCTFail("blank")
        }
        XCTAssertEqual(blank.wallet, .blankAppearance)
        try table.add(pin: "88-88", flags: [.wipe, .countdown], arg: 60)
        guard case .login(let cd) = table.decision(forPIN: "88-88") else {
            return XCTFail("countdown")
        }
        XCTAssertEqual(cd.countdownMinutes, 60)
        XCTAssertTrue(cd.wipeSeed)
        XCTAssertFalse(cd.brickAfterCountdown)
        try table.add(pin: "99-99", flags: [.wipe, .brick, .countdown], arg: 15)
        guard case .login(let brickCD) = table.decision(forPIN: "99-99") else {
            return XCTFail("countdown brick")
        }
        XCTAssertTrue(brickCD.brickAfterCountdown)
        XCTAssertEqual(brickCD.countdownMinutes, 15)
    }

    func testHideRestoreAndTruePINConflict() throws {
        var table = TrickPinTable()
        try table.add(pin: "11-22", flags: .brick, arg: 0)
        try table.hide(pin: "11-22")
        XCTAssertTrue(table.visiblePINs(hiding: nil).isEmpty)
        XCTAssertEqual(table.decision(forPIN: "11-22"), .brick(wipeSeed: false))
        XCTAssertTrue(table.forgottenPIN(matching: "11-22"))
        XCTAssertTrue(table.restore(pin: "11-22"))
        XCTAssertEqual(table.visiblePINs(hiding: nil), ["11-22"])
        XCTAssertEqual(table.checkNewMainPIN("11-22"), "That PIN is already in use as a Trick PIN.")
        try table.add(pin: "12-12", flags: .deltaMode, arg: 0x1212)
        XCTAssertNotNil(table.checkNewMainPIN("99-9999"))
    }

    func testSlotBudgetForWallets() throws {
        var table = TrickPinTable()
        for index in 0..<12 {
            try table.add(pin: String(format: "%02d-%02d", index, index), flags: .brick, arg: 0)
        }
        XCTAssertThrowsError(try table.add(pin: "88-88", flags: .xprvWallet, arg: 0)) { error in
            XCTAssertEqual(error as? TrickPinError, .noSpaceLeft)
        }
        try table.add(pin: "77-77", flags: .wordWallet, arg: 1001)
        XCTAssertThrowsError(try table.add(pin: "66-66", flags: .brick, arg: 0)) { error in
            XCTAssertEqual(error as? TrickPinError, .noSpaceLeft)
        }
    }

    func testHideCurrentLoginPINFromMenu() throws {
        var table = TrickPinTable()
        try table.add(pin: "11-11", flags: .deltaMode, arg: 0)
        try table.add(pin: "22-22", flags: .brick, arg: 0)
        XCTAssertEqual(table.visiblePINs(hiding: "11-11"), ["22-22"])
    }

    func testCannotHideDeltaPIN() throws {
        var table = TrickPinTable()
        try table.add(pin: "12-13", flags: .deltaMode, arg: 0)
        XCTAssertThrowsError(try table.hide(pin: "12-13")) { error in
            XCTAssertEqual(error as? TrickPinError, .cannotHideDelta)
        }
    }

    func testWrongAttemptOrdinals() {
        XCTAssertEqual(TrickPins.wrongAttemptOrdinal(0), "ANY")
        XCTAssertEqual(TrickPins.wrongAttemptOrdinal(1), "ANY")
        XCTAssertEqual(TrickPins.wrongAttemptOrdinal(2), "2nd")
        XCTAssertEqual(TrickPins.wrongAttemptOrdinal(3), "3rd")
        XCTAssertEqual(TrickPins.wrongAttemptOrdinal(4), "4th")
    }

    func testLegacyDuressAndBIP85Secrets() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let words = try TrickPins.constructDuressSecret(flags: .wordWallet, arg: 1001, root: root)
        XCTAssertEqual(words?.path, "BIP85(words=24, index=1001)")
        XCTAssertEqual(words?.secret.count, 32)
        let twelve = try TrickPins.constructDuressSecret(flags: .wordWallet, arg: 2001, root: root)
        XCTAssertEqual(twelve?.secret.count, 16)
        let legacy = try TrickPins.constructDuressSecret(flags: .xprvWallet, arg: 0, root: root)
        XCTAssertEqual(legacy?.path, TrickPins.legacyDuressPath)
        XCTAssertEqual(legacy?.secret.count, 64)
        let node = try root.derived(path: DerivationPath(TrickPins.legacyDuressPath))
        XCTAssertEqual(legacy?.secret, node.chainCode + (node.privateKey ?? Data()))
    }

    func testPolicyUnlockAndLookBlank() throws {
        var table = TrickPinTable()
        try table.add(pin: "10-10", flags: .firmwareDefined, arg: TrickPins.spendingPolicyUnlockArg)
        guard case .login(let session) = table.decision(forPIN: "10-10") else {
            return XCTFail("policy")
        }
        XCTAssertTrue(session.spendingPolicyUnlock)
        try table.add(pin: "10-11", flags: [.firmwareDefined, .wipe], arg: TrickPins.spendingPolicyUnlockArg)
        guard case .login(let wiped) = table.decision(forPIN: "10-11") else {
            return XCTFail("policy wipe")
        }
        XCTAssertTrue(wiped.wipeSeed)
        XCTAssertTrue(wiped.spendingPolicyUnlock)
    }

    func testTruePINIsNotATrick() throws {
        var table = TrickPinTable()
        try table.add(pin: "11-11", flags: .brick, arg: 0)
        XCTAssertEqual(table.decision(forPIN: "12-12"), .notATrick)
        XCTAssertEqual(table.wrongPINDecision(failCount: 1), .notATrick)
    }

    func testDeltaModeCorruptsPSBTAndMessageSignatures() throws {
        let mnemonic = try BIP39Mnemonic(entropy: Data(repeating: 1, count: 16))
        let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
        let psbt = try DemoPSBT.make(root: root)
        let honest = psbt.signed(using: root)
        let delta = psbt.signed(using: root, deltaMode: true)
        XCTAssertEqual(honest.signedInputCount, 1)
        XCTAssertEqual(delta.signedInputCount, 1)
        XCTAssertNotEqual(honest.data, delta.data)

        let path = DerivationPath.account(type: .nativeSegwit, network: .testnet).appending(0).appending(0)
        let honestMsg = try BitcoinMessageSigner.sign("hello", root: root, path: path, type: .nativeSegwit)
        let deltaMsg = try BitcoinMessageSigner.sign("hello", root: root, path: path, type: .nativeSegwit, deltaMode: true)
        XCTAssertNotEqual(honestMsg.signatureBase64, deltaMsg.signatureBase64)
        XCTAssertEqual(honestMsg.address, deltaMsg.address)
    }
}

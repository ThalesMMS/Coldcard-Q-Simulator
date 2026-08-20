import XCTest
@testable import ColdcardCore

/// Firmware `actions.clear_seed`, `any_active_duress_ux`, `convert_ephemeral_to_master`.
final class SeedDangerTests: XCTestCase {
    func testDestroySeedFirstConfirmMatchesFirmware() {
        XCTAssertEqual(SeedDanger.destroyFirstTitle, "Are you SURE ?!?")
        XCTAssertEqual(
            SeedDanger.destroyFirstBody,
            "Wipe seed words and reset wallet. All funds will be lost. You better have a backup of the seed words. All settings like multisig wallets are also wiped. Saved temporary seed settings and Seed Vault are lost. Trick PINs are also completely removed."
        )
        XCTAssertNil(SeedDanger.destroyFirstConfirmKey)
    }

    func testDestroySeedAgainBodyOmitsConfirmKeySuffix() {
        XCTAssertEqual(SeedDanger.destroyAgainTitle, "AGAIN...")
        XCTAssertEqual(SeedDanger.destroyAgainConfirmKey, "4")
        XCTAssertEqual(
            SeedDanger.destroyAgainBody,
            """
            Are you REALLY sure though???

            This action will certainly cause you to lose all funds associated with this wallet, unless you have a backup of the seed words and know how to import them into a new wallet.
            """
        )
        XCTAssertFalse(SeedDanger.destroyAgainBody.contains("Press (4)"))
        XCTAssertFalse(SeedDanger.destroyAgainBody.contains("prove you read"))
    }

    func testDuressBlockCopyMatchesFirmware() {
        XCTAssertEqual(
            SeedDanger.duressBlockBody,
            "You have one or more duress wallets defined under Trick PINs. Please empty them, and clear associated Trick PINs before continuing."
        )
    }

    func testDestroySeedDuressGateMatchesFirmwareHobbledSkip() {
        XCTAssertTrue(SeedDanger.shouldBlockDestroyForDuress(hobbled: false, hasActiveDuress: true))
        XCTAssertFalse(SeedDanger.shouldBlockDestroyForDuress(hobbled: true, hasActiveDuress: true))
        XCTAssertFalse(SeedDanger.shouldBlockDestroyForDuress(hobbled: false, hasActiveDuress: false))
        XCTAssertFalse(SeedDanger.shouldBlockDestroyForDuress(hobbled: true, hasActiveDuress: false))
    }

    func testVisibleDuressPINBlocksDestroyAndHiddenDoesNot() throws {
        var table = TrickPinTable()
        XCTAssertFalse(table.hasDuressWallet)

        try table.add(pin: "11-11", flags: .brick, arg: 0)
        XCTAssertFalse(table.hasDuressWallet)

        try table.add(pin: "44-44", flags: .wordWallet, arg: 1001)
        XCTAssertTrue(table.hasDuressWallet)
        XCTAssertTrue(SeedDanger.shouldBlockDestroyForDuress(hobbled: false, hasActiveDuress: table.hasDuressWallet))

        try table.hide(pin: "44-44")
        XCTAssertFalse(table.hasDuressWallet)

        table.clearAll()
        XCTAssertTrue(table.slots.isEmpty)
        try table.add(pin: "55-55", flags: .xprvWallet, arg: 0)
        XCTAssertTrue(table.hasDuressWallet)
    }

    func testLockDownSeedStoryMatchesFirmwareTemporaryWords() {
        XCTAssertEqual(SeedDanger.lockDownConfirmKey, "4")
        XCTAssertEqual(SeedDanger.lockDownTitle, "Are you SURE ?!?")
        XCTAssertEqual(
            SeedDanger.lockDownStory(isPassphraseWallet: false, masterHasWords: true, currentHasWords: true),
            "Convert currently used temporary seed to master seed. Old master seed words themselves are erased forever, and its settings blanked. This action is destructive and may affect funds, if any, on old master seed. Make sure all duress wallets associated with previous seed are deleted, otherwise they will be carried forward without being properly generated from new master seed. Saved temporary seed settings and Seed Vault are lost. A reboot is part of this process. PIN code, and temporary seed funds are not affected."
        )
    }

    func testLockDownSeedStoryPassphraseAndXPRVVariants() {
        let passphrase = SeedDanger.lockDownStory(
            isPassphraseWallet: true, masterHasWords: true, currentHasWords: true
        )
        XCTAssertTrue(passphrase.contains("Convert currently used BIP-39 passphrase wallet to master seed"))
        XCTAssertTrue(passphrase.contains("but the passphrase itself is erased and unrecoverable."))
        XCTAssertTrue(passphrase.contains("PIN code, and BIP-39 passphrase wallet funds are not affected."))

        let xprvMaster = SeedDanger.lockDownStory(
            isPassphraseWallet: false, masterHasWords: false, currentHasWords: false
        )
        XCTAssertTrue(xprvMaster.contains("Old master seed is erased forever,"))
        XCTAssertTrue(xprvMaster.contains("The resulting wallet cannot be used with any other passphrase."))
    }

    func testLockDownDisplayedStoryIncludesUXConfirmSuffix() {
        let body = SeedDanger.lockDownConfirmBody(
            isPassphraseWallet: false, masterHasWords: true, currentHasWords: true
        )
        XCTAssertTrue(body.contains("Press (4) to prove you read to the end of this message and accept all consequences."))
        XCTAssertTrue(body.hasPrefix(SeedDanger.lockDownStory(
            isPassphraseWallet: false, masterHasWords: true, currentHasWords: true
        )))
    }

    func testDestroySeedClearingAndAbortMatchFirmware() {
        XCTAssertEqual(SeedDanger.clearingTitle, "Clearing...")
        XCTAssertEqual(SeedDanger.abortedPause, "Aborted.")
        XCTAssertFalse(SeedDanger.clearingTitle.contains("Seed destroyed"))
        XCTAssertFalse(SeedDanger.destroyFirstBody.contains("Seed destroyed. PIN remains."))
        XCTAssertFalse(SeedDanger.destroyAgainBody.contains("Empty Wallet"))
    }
}

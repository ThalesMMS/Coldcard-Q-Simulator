import Foundation
import Testing
@testable import ColdcardCore

/// Firmware `SeedVaultMenu._detail` (`seed.py`):
/// `"Name:\n%s\n\nMaster XFP: %s\nSecret Type: %s\n\nOrigin:\n%s\n\n"`
@Test func seedVaultDetailStoryMatchesFirmwareWords() throws {
    let mnemonic = try BIP39Mnemonic(phrase:
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    let encoded = SecretStash.encode(entropy: mnemonic.entropy)
    let body = SeedVaultMenuCopy.detailStory(
        label: "[0F056943]",
        xfp: "0F056943",
        encodedSecret: encoded,
        origin: "Dice"
    )
    #expect(body == "Name:\n[0F056943]\n\nMaster XFP: 0F056943\nSecret Type: 12 words\n\nOrigin:\nDice\n\n")
}

@Test func seedVaultDetailStoryMatchesFirmware24WordsAndOrigin() throws {
    let mnemonic = try BIP39Mnemonic(entropy: Data(repeating: 0, count: 32))
    let encoded = SecretStash.encode(entropy: mnemonic.entropy)
    let origin = "BIP85 Derived from [0F056943], index=0"
    let body = SeedVaultMenuCopy.detailStory(
        label: "Vault seed",
        xfp: "ABCD1234",
        encodedSecret: encoded,
        origin: origin
    )
    #expect(body == "Name:\nVault seed\n\nMaster XFP: ABCD1234\nSecret Type: 24 words\n\nOrigin:\n\(origin)\n\n")
}

/// Firmware `SeedVaultMenu` parent row `'%2d: %s' % (i+1, rec.label)` (`seed.py:1320`).
@Test func seedVaultParentRowUsesPaddedIndex() {
    #expect(SeedVaultMenuCopy.parentRowLabel(index: 0, label: "[7126EB3C]") == " 1: [7126EB3C]")
    #expect(SeedVaultMenuCopy.parentRowLabel(index: 9, label: "Vault") == "10: Vault")
    #expect(SeedVaultMenuCopy.storedLabel(custom: "", fingerprint: "7126EB3C") == "[7126EB3C]")
    #expect(SeedVaultMenuCopy.storedLabel(custom: "Vault", fingerprint: "7126EB3C") == "Vault")
}

/// Firmware notes `'%d: %s' % (note.idx+1, note.title)` (`notes.py`) — no width padding.
@Test func noteParentRowUsesUnpaddedIndex() {
    #expect(NoteMenuCopy.parentRowLabel(index: 0, title: "note0") == "1: note0")
    #expect(NoteMenuCopy.parentRowLabel(index: 9, title: "secret-PWD") == "10: secret-PWD")
}

@Test func seedVaultDetailStoryMatchesFirmwareXPRV() {
    let encoded = SecretStash.encode(chainCode: Data(repeating: 1, count: 32),
                                     privateKey: Data(repeating: 2, count: 32))
    let body = SeedVaultMenuCopy.detailStory(
        label: "Imported",
        xfp: "DEADBEEF",
        encodedSecret: encoded,
        origin: "Imported XPRV"
    )
    #expect(body == "Name:\nImported\n\nMaster XFP: DEADBEEF\nSecret Type: xprv\n\nOrigin:\nImported XPRV\n\n")
}

@Test func seedVaultDeleteStoryIncludesKeepSettingsEscapeWhenNotActive() {
    let body = SeedVaultMenuCopy.deleteStory(xfp: "0F056943", currentlyActive: false)
    #expect(SeedVaultMenuCopy.deleteTitle(xfp: "0F056943") == "[0F056943]")
    #expect(body.hasPrefix("Remove seed from seed vault and delete its settings?"))
    #expect(body.contains("Press ENTER to continue, press (1) to only remove from seed vault and keep encrypted settings for later use."))
    #expect(body.contains("WARNING: Funds will be lost if wallet is not backed-up elsewhere."))
}

@Test func seedVaultDeleteStoryOmitsKeepSettingsWhenActiveTmp() {
    let body = SeedVaultMenuCopy.deleteStory(xfp: "ABCD1234", currentlyActive: true)
    #expect(body.hasPrefix("Remove seed from seed vault?\n\n"))
    #expect(!body.contains("press (1)"))
    #expect(body.contains("WARNING: Funds will be lost if wallet is not backed-up elsewhere."))
}

@Test func seedVaultOfferAndSavedCopyMatchFirmware() {
    #expect(SeedVaultMenuCopy.offer == """
    Press (1) to store temporary seed into Seed Vault. This way you can easily switch to this secret and use it as temporary seed in future.

    Press ENTER to continue without saving.
    """)
    #expect(SeedVaultMenuCopy.savedStory(xfp: "0F056943") == "[0F056943]\nSaved to Seed Vault")
}

@Test func seedVaultEphemeralAppliedStoryMatchesFirmware() {
    #expect(SeedVaultMenuCopy.ephemeralAppliedStory() == "New temporary master key is in effect now.")
    #expect(
        SeedVaultMenuCopy.ephemeralAppliedStory(bip39pw: "satoshi")
            == "New temporary master key is in effect now.\n\nPassphrase: satoshi"
    )
}

@Test func seedVaultOfferGateMatchesFirmwareSkipRules() {
    #expect(SeedVaultMenuCopy.shouldOfferVault(
        enabled: true, secretBlank: false, deltaMode: false, hobbled: false,
        alreadyVaulted: false, newXFP: "AAAAAAAA", masterXFP: "BBBBBBBB"
    ))
    #expect(!SeedVaultMenuCopy.shouldOfferVault(
        enabled: false, secretBlank: false, deltaMode: false, hobbled: false,
        alreadyVaulted: false, newXFP: "AAAAAAAA", masterXFP: "BBBBBBBB"
    ))
    #expect(!SeedVaultMenuCopy.shouldOfferVault(
        enabled: true, secretBlank: false, deltaMode: false, hobbled: false,
        alreadyVaulted: true, newXFP: "AAAAAAAA", masterXFP: "BBBBBBBB"
    ))
    #expect(!SeedVaultMenuCopy.shouldOfferVault(
        enabled: true, secretBlank: false, deltaMode: false, hobbled: false,
        alreadyVaulted: false, newXFP: "[AAAA]", masterXFP: "aaaa"
    ))
    #expect(!SeedVaultMenuCopy.shouldOfferVault(
        enabled: true, secretBlank: false, deltaMode: false, hobbled: true,
        alreadyVaulted: false, newXFP: "AAAAAAAA", masterXFP: "BBBBBBBB"
    ))
}

@Test func seedVaultRenameCapAndEnableDisableCopyMatchFirmware() {
    #expect(SeedVaultMenuCopy.renameMaxLength == 40)
    #expect(SeedVaultMenuCopy.disableBlocked == "Please remove all seeds from the vault before disabling.")
    #expect(SeedVaultMenuCopy.enableStory.contains("Enable Seed Vault?"))
    #expect(SeedVaultMenuCopy.enableStory.contains("WARNING: Seed Vault is encrypted (AES-256-CTR) by your seed,"))
}

@Test func bip39PassphraseLimitsAndOriginMatchFirmware() {
    #expect(BIP39Passphrase.maxLength == 100)
    #expect(BIP39Passphrase.sanitized(String(repeating: "a", count: 101)).count == 100)
    #expect(BIP39Passphrase.sanitized("ok\u{0007}no") == "okno")
    #expect(BIP39Passphrase.sanitized("space ok") == "space ok")
    #expect(BIP39Passphrase.sanitized("tilde~") == "tilde~")
    #expect(BIP39Passphrase.origin(parentXFP: "0F056943") == "BIP-39 Passphrase on [0F056943]")
    #expect(BIP39Passphrase.parentSeedLabel(tmpActive: false, parentXFP: "ABCD1234")
        == "master seed [ABCD1234]")
    #expect(BIP39Passphrase.parentSeedLabel(tmpActive: true, parentXFP: "ABCD1234")
        == "current active temporary seed [ABCD1234]")
    #expect(BIP39Passphrase.applyFooter.contains("save to MicroSD for future."))
    #expect(BIP39Passphrase.keychainStandIn.contains("Keychain"))
    #expect(BIP39Passphrase.inputHint == "TAB to auto-complete. QR to scan.")
}

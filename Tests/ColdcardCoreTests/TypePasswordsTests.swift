import Testing
@testable import ColdcardCore

/// Firmware `drv_entro.password_entry` / `send_keystrokes` (USB HID replaced by clipboard).
@Test func typePasswordsIndexClampsToDefaultBIP32Max() {
    #expect(TypePasswords.parseIndex("") == 0)
    #expect(TypePasswords.parseIndex("0") == 0)
    #expect(TypePasswords.parseIndex("10") == 10)
    #expect(TypePasswords.parseIndex("9999") == 9999)
    #expect(TypePasswords.parseIndex("10000") == 9999)
    #expect(TypePasswords.parseIndex("99999") == 9999)
}

@Test func typePasswordsDigitEntryMatchesUxEnterNumber() {
    #expect(TypePasswords.appendDigit("", "1") == "1")
    #expect(TypePasswords.appendDigit("0", "0") == "0")
    #expect(TypePasswords.appendDigit("999", "9") == "9999")
    #expect(TypePasswords.appendDigit("9999", "8") == "9998")
    #expect(TypePasswords.appendDigit("1000", "0") == "1000")
}

@Test func typePasswordsHomeItemFollowsKeyboardEMUPredicate() {
    #expect(TypePasswords.isHomeItemVisible(keyboardEmuEnabled: true, hasSecrets: true))
    #expect(!TypePasswords.isHomeItemVisible(keyboardEmuEnabled: false, hasSecrets: true))
    #expect(!TypePasswords.isHomeItemVisible(keyboardEmuEnabled: true, hasSecrets: false))
}

@Test func typePasswordsSendPromptMatchesFirmwareCopy() {
    let path = TypePasswords.path(index: 1000)
    let body = TypePasswords.sendPrompt(okKey: "ENTER", password: "abcDEF123+/", path: path)
    #expect(body.contains("Place mouse at required password prompt, then press ENTER to send keystrokes."))
    #expect(body.contains("Password:\nabcDEF123+/"))
    #expect(body.contains("Path:\n\(path)"))
    #expect(path == "m/83696968h/707764h/21h/1000h")
}

@Test func typePasswordsKeystrokesAppendCarriageReturn() {
    #expect(TypePasswords.keystrokes(password: "pw") == "pw\r")
}

@Test func typePasswordsSentConfirmsClipboardAndTypedKeys() {
    let body = TypePasswords.sentConfirmation(password: "pw")
    #expect(body.hasPrefix("Sent."))
    #expect(body.contains("Copied to clipboard."))
    #expect(body.contains("Would have typed:\npw\n[Enter]"))
}

@Test func typePasswordsBIP85MatchesFirmwareIndexes() throws {
    let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
    for index in [UInt32(0), 10, 100, 1000, 9999] {
        let result = try BIP85.derive(root: root, kind: .password, index: index)
        #expect(result.path == TypePasswords.path(index: index))
        #expect(result.qr.count == BIP85.passwordLength)
        #expect(!result.qr.contains("="))
        #expect(result.qr == TypePasswords.clipboardPayload(password: result.qr))
    }
}

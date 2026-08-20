import Foundation
import Testing
@testable import ColdcardCore

private let abandon = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

@Test func microSD2FAFilenameMatchesFirmwareShape() {
    let name = MicroSD2FA.tokenFilename(serial: MicroSD2FA.simulatorSerial)
    #expect(name.hasPrefix("."))
    #expect(name.hasSuffix(".2fa"))
    let hex = String(name.dropFirst().dropLast(4))
    #expect(hex.count == 16)
    #expect(hex.allSatisfy { $0.isHexDigit })
    #expect(name == MicroSD2FA.tokenFilename(serial: MicroSD2FA.simulatorSerial))
    #expect(MicroSD2FA.visibleTokenFilename() == String(name.dropFirst()))
    #expect(MicroSD2FA.encryptionPath == "m/2147431408h/0h")
    #expect(MicroSD2FA.looksLikeTokenFilename(name))
    #expect(MicroSD2FA.looksLikeTokenFilename(MicroSD2FA.visibleTokenFilename()))
}

@Test func microSD2FAMenuTitlesFollowFirmware() {
    #expect(MicroSD2FA.menuTitles(nonces: []) == ["Add Card"])
    #expect(MicroSD2FA.menuTitles(nonces: ["aa"]) == ["Add Card", "Check Card", "Remove Card #1"])
    #expect(MicroSD2FA.menuTitles(nonces: ["aa", "bb"]) == [
        "Add Card", "Check Card", "Remove Card #1", "Remove Card #2"
    ])
}

@Test func microSD2FACopyMatchesFirmware() {
    #expect(MicroSD2FA.intro.hasPrefix("When enabled, this feature requires a specially prepared MicroSD card"))
    #expect(MicroSD2FA.intro.contains("the seed is wiped."))
    #expect(MicroSD2FA.introQExtra.contains("authorized card is in the top slot (slot A)."))
    #expect(MicroSD2FA.alreadyEnrolled == "Need a different MicroSD card. This card would already be accepted.")
    #expect(MicroSD2FA.enrollConfirm(existingCount: 0).contains("it must be"))
    #expect(MicroSD2FA.enrollConfirm(existingCount: 1).contains("this card or one of the others"))
    #expect(MicroSD2FA.checkFail == "This card would NOT be accepted during login.")
    #expect(MicroSD2FA.checkPass == "This card is enrolled and would be accepted during login.")
    #expect(MicroSD2FA.removeConfirm == "Remove this card from authorized set?")
    #expect(MicroSD2FA.needsCard == "Please insert a MicroSD card before attempting this operation.")
    #expect(MicroSD2FA.saved == "Saved.")
    #expect(MicroSD2FA.seedWipedTitle == "Seed Wiped")
    #expect(MicroSD2FA.checkFailTitle == "FAIL")
    #expect(MicroSD2FA.checkPassTitle == "PASS")
}

@Test func microSD2FATokenRoundTripAndPolicy() throws {
    let mnemonic = try BIP39Mnemonic(phrase: abandon)
    let root = try HDKey(seed: mnemonic.seed(), network: .testnet)
    let key = try MicroSD2FA.encryptionKey(root: root, salt: MicroSD2FA.documentsCardSalt)
    let nonce = MicroSD2FA.nonceHex(from: Data(repeating: 0xab, count: 8))
    #expect(nonce == "abababababababab")

    let token = try MicroSD2FA.sealToken(nonce: nonce, key: key)
    #expect(MicroSD2FA.readNonce(from: token, key: key) == nonce)
    #expect(MicroSD2FA.readNonce(from: token, key: Data(repeating: 1, count: 32)) == nil)
    #expect(MicroSD2FA.readNonce(from: Data("nope".utf8), key: key) == nil)

    #expect(MicroSD2FA.authorizedCardPresent(fileData: token, enrolledNonces: [nonce], key: key))
    #expect(!MicroSD2FA.authorizedCardPresent(fileData: nil, enrolledNonces: [nonce], key: key))
    #expect(!MicroSD2FA.authorizedCardPresent(fileData: token, enrolledNonces: ["deadbeef"], key: key))
    #expect(!MicroSD2FA.authorizedCardPresent(fileData: Data(), enrolledNonces: [nonce], key: key))

    #expect(MicroSD2FA.loginDecision(enrolledNonces: [], authorized: false) == .proceed)
    #expect(MicroSD2FA.loginDecision(enrolledNonces: [nonce], authorized: true) == .proceed)
    #expect(MicroSD2FA.loginDecision(enrolledNonces: [nonce], authorized: false) == .wipe)

    #expect(MicroSD2FA.removing("aa", from: ["aa"]) == [])
    #expect(MicroSD2FA.removing("aa", from: ["aa", "bb"]) == ["bb"])
}

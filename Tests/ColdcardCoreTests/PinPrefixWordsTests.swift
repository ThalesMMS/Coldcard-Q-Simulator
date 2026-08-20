import Foundation
import Testing
@testable import ColdcardCore

/// Firmware `mathcheck.py` / `docs/pin-entry.md` pairing secret used to check `pin_hash`.
private let mathcheckPairingSecret = try! Data(hex: "2744eaab79b539cc72fc032b7516875ae0a63e8ab22f4cbf529d21f5ea665aa7")

@Test func purposeWordsIsFirmwareLittleEndianConstant() {
    // pins.h PIN_PURPOSE_WORDS 0x2e6d6773; pin-entry.md PURPOSE_WORDS hex 73676d2e
    #expect(PinPrefixWords.purposeWords.hexString == "73676d2e")
    #expect(PinPrefixWords.pairingSecretLength == 32)
}

@Test func pinHashMatchesMathcheckPairingSecretPlusPurposeWordsPlusPrefix() throws {
    // mathcheck.py: SHA256(SHA256(pairing_secret + PURPOSE_WORDS + pin))
    let digest = PinPrefixWords.pinHash(pairingSecret: mathcheckPairingSecret, pinPrefix: Data("12".utf8))
    #expect(digest.hexString == "8c34015541a47cc94cb62797078ba9cb95e032917736a5dc86e4631ec81a83fb")
}

@Test func wordIndicesUnpackLittleEndian22BitsLikePincodesPrefixWords() throws {
    // pincodes.prefix_words: bits = unpack('<I', digest[:4]); w1=(bits>>11)&0x7ff; w2=bits&0x7ff
    let zero = Data([0x00, 0x00, 0x00, 0x00])
    #expect(PinPrefixWords.wordIndices(digest: zero)! == (0, 0))

    let abilityAbandon = Data([0x00, 0x08, 0x00, 0x00])
    #expect(PinPrefixWords.wordIndices(digest: abilityAbandon)! == (1, 0))
}

@Test func prefixWordsMatchFirmwareHashThen22BitWordSelection() throws {
    let words = PinPrefixWords.words(pairingSecret: mathcheckPairingSecret, pinPrefix: "12")
    #expect(words?.0 == "age")
    #expect(words?.1 == "muscle")
    #expect(PinPrefixWords.displayString(pairingSecret: mathcheckPairingSecret, pinPrefix: "12") == "age  muscle")
}

@Test func differentPrefixesAndSecretsChangeTheWords() throws {
    let a = PinPrefixWords.displayString(pairingSecret: mathcheckPairingSecret, pinPrefix: "12")
    let b = PinPrefixWords.displayString(pairingSecret: mathcheckPairingSecret, pinPrefix: "435")
    let otherSecret = Data(repeating: 0x22, count: 32)
    let c = PinPrefixWords.displayString(pairingSecret: otherSecret, pinPrefix: "12")
    #expect(a == "age  muscle")
    #expect(b == "nice  traffic")
    #expect(a != b)
    #expect(a != c)
    #expect(PinPrefixWords.displayString(pairingSecret: mathcheckPairingSecret, pinPrefix: "") == "")
}

@Test func prefixWordsAreNotSHA256OfSaltConcatenatedWithUTF8Prefix() throws {
    let saltStyle = SHA2.sha256(mathcheckPairingSecret + Data("12".utf8))
    let firmware = PinPrefixWords.pinHash(pairingSecret: mathcheckPairingSecret, pinPrefix: Data("12".utf8))
    #expect(saltStyle != firmware)
}

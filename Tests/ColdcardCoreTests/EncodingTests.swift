import Foundation
import Testing
@testable import ColdcardCore

@Test func base58Vectors() throws {
    #expect(Base58.encode(Data()) == "")
    #expect(Base58.encode(Data([0])) == "1")
    #expect(Base58.encode(try Data(hex: "000001")) == "112")
    #expect(try Base58.decode("StV1DL6CwTryKyV") == Data("hello world".utf8))
    let checked = Base58.checkEncode(version: Data([0]), payload: Data(repeating: 0, count: 20))
    #expect(checked == "1111111111111111111114oLvT2")
    #expect(try Base58.checkDecode(checked) == Data(repeating: 0, count: 21))
}

@Test func bech32RoundTrip() throws {
    let program = try Data(hex: "751e76e8199196d454941c45d1b3a323f1433bd6")
    let address = try Bech32.encodeSegwit(hrp: "bc", version: 0, program: program)
    #expect(address == "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    let decoded = try Bech32.decodeSegwit(address)
    #expect(decoded.hrp == "bc")
    #expect(decoded.version == 0)
    #expect(decoded.program == program)
}

@Test func bip39VectorOne() throws {
    let entropy = Data(repeating: 0, count: 16)
    let mnemonic = try BIP39Mnemonic(entropy: entropy)
    #expect(mnemonic.phrase == "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    #expect(mnemonic.entropy == entropy)
    #expect(mnemonic.seed(passphrase: "TREZOR").hexString == "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04")
    #expect(try BIP39Mnemonic.fromSeedQR(mnemonic.seedQR) == mnemonic)
}

@Test func bip39PredictsNextCharactersAndChecksumWords() throws {
    let abandon = BIP39Mnemonic.predict(prefix: "aban")
    #expect(abandon.completedWord == "abandon")
    let act = BIP39Mnemonic.predict(prefix: "act")
    #expect(act.nextCharacters.contains("i") || act.nextCharacters.contains("o") || act.nextCharacters.contains("r") || act.completedWord != nil)
    let preceding = Array(repeating: "abandon", count: 11)
    let candidates = BIP39Mnemonic.checksumCandidates(precedingWords: preceding)
    #expect(candidates.contains("about"))
    #expect(!candidates.isEmpty)
}

@Test func notesQRTitleRulesMatchFirmwareQuickCreate() {
    #expect(SecureNotes.titleForScannedText("otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP") == "Example:alice@google.com")
    #expect(SecureNotes.titleForScannedText("otpauth://totp/ACME%20Inc:user?secret=x") == "ACME Inc:user")
    #expect(SecureNotes.titleForScannedText("otpauth-migration://offline?data=xxx") == "Google Auth")
    #expect(SecureNotes.titleForScannedText("https://example.com/path") == "example.com")
    #expect(SecureNotes.titleForScannedText("hello world from qr") == "Scanned")
}

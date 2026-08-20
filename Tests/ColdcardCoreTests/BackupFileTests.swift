import Foundation
import Testing
@testable import ColdcardCore

@Test func backupTextRoundTripMatchesFirmwareShape() throws {
    let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    let body = try BackupFile.render(
        mnemonic: mnemonic,
        chain: "XTN",
        chainName: "Bitcoin Testnet 4",
        xprv: "tprv8ZgxMBicQKsPe",
        xpub: "tpubD6NzVbkrYhZ4",
        rawSecretHex: "8001020304",
        settings: [
            ("secnap", true),
            ("seedvault", false),
            ("seeds", [] as [Any]),
            ("bkpw", "should-not-appear"),
            ("xfp", "AABBCCDD"),
            ("notes", [["title": "Hello"]])
        ]
    )
    #expect(body.hasPrefix("# Coldcard backup file! DO NOT CHANGE.\n"))
    #expect(body.contains("# Private key details: Bitcoin Testnet 4"))
    #expect(body.contains("mnemonic = \"\(mnemonic)\""))
    #expect(body.contains("chain = \"XTN\""))
    #expect(body.contains("raw_secret = \"8001020304\""))
    #expect(body.contains("setting.secnap = true"))
    #expect(body.contains("setting.notes"))
    #expect(!body.contains("setting.bkpw"))
    #expect(!body.contains("setting.xfp"))
    #expect(!body.contains("setting.seedvault"))
    #expect(!body.contains("setting.seeds"))
    #expect(body.contains("\n# EOF\n"))

    let parsed = BackupFile.parse(body)
    #expect(BackupFile.stringValue(parsed, "mnemonic") == mnemonic)
    #expect(BackupFile.stringValue(parsed, "chain") == "XTN")
    #expect(BackupFile.jsonBool(BackupFile.settingValues(parsed)["secnap"]))
}

@Test func backupPasswordHintMatchesFirmware() {
    let words = (0..<12).map { _ in "abandon" }.enumerated().map { index, word in
        index == 0 ? "ability" : (index == 11 ? "zoo" : word)
    }
    #expect(
        BackupFile.passwordReuseHint(words.joined(separator: " "))
            == " 1: ability\n   ...\n12: zoo"
    )
    #expect(BackupFile.passwordReuseHint("custom-long-password-value") == " c...e")
    #expect(
        BackupFile.reusePasswordStory("custom-long-password-value")
            == "Use same backup file password as last time?\n\n c...e"
    )
}

@Test func backupCleartextAndCopyStoriesMatchFirmware() {
    #expect(
        BackupFile.cleartextConfirm(what: BackupFile.moneyForFree)
            == "The file will **NOT** be encrypted and anyone who finds the file will get all of your money for free!"
    )
    #expect(
        BackupFile.cleartextConfirm(what: BackupFile.notesAndPasswords)
            == "The file will **NOT** be encrypted and anyone who finds the file will get all of your notes & passwords!"
    )
    #expect(
        BackupFile.firstCopyWritten("backup.7z")
            == """
            Backup file written:

            backup.7z

            To view or restore the file, you must have the full password.

            Insert another SD card and press (2) to make another copy.
            """
    )
    #expect(
        BackupFile.subsequentCopyWritten(copyNumber: 2, filename: "backup.7z")
            == """
            File (#2) written:

            backup.7z

            Press ENTER for another copy, or press CANCEL to stop.
            """
    )
}

@Test func backupVerifyAndRestoreCopyMatchesFirmware() {
    #expect(BackupFile.unableToOpen == "Unable to open backup file.")
    #expect(BackupFile.unableToReadHeaders == "Unable to read backup file headers. Might be truncated.")
    #expect(BackupFile.unableToVerifyContents == "Unable to verify backup file contents.")
    #expect(
        BackupFile.verifyFailure(problem: BackupFile.unableToVerifyContents, error: "size")
            == "Unable to verify backup file contents.\n\nError: size"
    )
    #expect(
        BackupFile.decryptFailed(tried: "word word")
            == "Unable to decrypt backup file. Incorrect password?\n\nTried:\n\nword word"
    )
    #expect(BackupFile.restoreTitle(xfp: "0F056943") == "[0F056943]")
    #expect(
        BackupFile.customPasswordStory
            == "Press (1) if your password is custom string, press ENTER for 12 word password."
    )
    #expect(BackupFile.customPasswordTitle == "Custom PWD?")
    #expect(BackupFile.innerFilename(word: "ability", number: 7) == "ability7.txt")
    #expect(BackupFile.innerFilename(word: "zoo", number: 0, ext: "json") == "zoo0.json")
    #expect(BackupFile.isEncryptedBackupFilename("Backup.7Z"))
    #expect(BackupFile.isCleartextBackupFilename("backup.txt"))
    #expect(!BackupFile.isEncryptedBackupFilename("backup.txt"))
}

@Test func backupPasswordGridIsColumnMajorPairs() {
    let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
    let rendered = SeedXOR.renderPartWords(words)
    #expect(rendered.split(separator: "\n").count == 6)
    #expect(rendered.contains(" 1: one         7: seven"))
    #expect(rendered.contains(" 6: six        12: twelve"))
}

@Test func backupRawSecretHexStripsTrailingZerosAndRoundTrips() throws {
    #expect(BackupFile.strippedRawSecretHex("800abc000") == "800abc")
    let encoded = SecretStash.encode(entropy: Data(repeating: 0xAB, count: 16))
    let stripped = BackupFile.strippedRawSecretHex(encoded.hexString)
    #expect(!stripped.hasSuffix("0"))
    let restored = try BackupFile.deserializeSecret(stripped)
    #expect(try SecretStash.decode(restored) == SecretStash.decode(encoded))
}

@Test func backupRenderExceedsVerifyMinimumSize() throws {
    let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    let body = try BackupFile.render(
        mnemonic: mnemonic,
        chain: "XTN",
        chainName: "Bitcoin Testnet 4",
        xprv: "tprv8ZgxMBicQKsPe5Wjz7iCC1xNqjJizV7u7ibKtLhb8g1N3KWr5fN8wKqKqKqKqKqKqKqKqKqKqKqKqKqKqKqKqKqKqKq",
        xpub: "tpubD6NzVbkrYhZ4XgiXtGrdW5ZDDaESdHhHq5VqHEg5Xyc4gLGaQ5k7CqKqKqKqKqKqKqKqKqKqKqKqKqKqKqKqKqKqKqKq",
        rawSecretHex: SecretStash.encode(entropy: try BIP39Mnemonic(phrase: mnemonic).entropy).hexString
    )
    #expect(body.utf8.count > 400)
    #expect(BackupFile.isPlausibleInnerSize(body.utf8.count))
}

@Test func backupDeserializeSecretPadsOddHex() throws {
    let raw = try BackupFile.deserializeSecret("80")
    #expect(raw.count == SecretStash.encodedLength)
    #expect(raw[0] == 0x80)
    #expect(BackupFile.network(fromChain: "BTC") == .mainnet)
    #expect(BackupFile.network(fromChain: "XTN") == .testnet)
    #expect(BackupFile.network(fromChain: "XRT") == .regtest)
}

@Test func backupWordPasswordGridFormatMatchesUxQ1() {
    let words = Array(BIP39EnglishWords.all.prefix(12))
    let line = SeedXOR.renderPartWords(words).split(separator: "\n")[0]
    let expected = String(
        format: "%2d: %@   %2d: %@",
        1, SeedXOR.leftAligned(words[0], width: 8),
        7, words[6]
    )
    #expect(String(line) == expected)
}

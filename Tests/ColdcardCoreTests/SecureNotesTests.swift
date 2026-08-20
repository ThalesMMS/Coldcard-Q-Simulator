import Foundation
import Testing
@testable import ColdcardCore

@Test func crc32MatchesPythonBinAscii() {
    #expect(CRC32.hash(Data()) == 0)
    #expect(CRC32.hash(Data("123456789".utf8)) == 0xCBF4_3926)
}

@Test func compat7zAESMatchesFirmwareCommentVector() throws {
    let key = try Data(hex: "886660203c30b116ac07bc8d24066697f35e476e7f07d6118ea9f27fbfb5d27b")
    let iv = try Data(hex: "ca9f7eae1b7261630000000000000000")
    var plain = Data("Hello\n".utf8)
    plain.append(Data(repeating: 0, count: 10))
    let cipher = AES256CTR.cryptCBC(encrypt: true, key: key, iv: iv, data: plain)
    #expect(cipher == (try Data(hex: "56c1d8417e533c947bc6dd472b4e073f")))
    #expect(AES256CTR.cryptCBC(encrypt: false, key: key, iv: iv, data: cipher) == plain)
}

@Test func compat7zKeyDerivationMatchesFirmwareTestPassword() throws {
    let key = Compat7z.calculateKey(password: "test", salt: Data(), roundsPow: 19)
    #expect(key == (try Data(hex: "886660203c30b116ac07bc8d24066697f35e476e7f07d6118ea9f27fbfb5d27b")))
}

@Test func compat7zRoundTripJSONNotes() throws {
    let json = try SecureNotes.encodeNotesJSON([["title": "Hello", "misc": "world"]])
    let salt = Data(repeating: 0x11, count: 16)
    let iv = Data(repeating: 0x22, count: 16)
    let archive = try Compat7z.encrypt(
        plaintext: json,
        password: "test password 32 characters long!!",
        innerName: "able42.json",
        salt: salt,
        iv: iv
    )
    #expect(Compat7z.isFirmware7z(archive))
    let decoded = try Compat7z.decrypt(archive, password: "test password 32 characters long!!")
    #expect(decoded.filename == "able42.json")
    #expect(decoded.plaintext == json)
    #expect(throws: Compat7zError.wrongPassword) {
        _ = try Compat7z.decrypt(archive, password: "wrong")
    }
}

@Test func secureNotesExportFilenamesAndStories() {
    #expect(SecureNotes.jsonFilename(all: true, isPassword: false) == "cc-notes.json")
    #expect(SecureNotes.jsonFilename(all: false, isPassword: true) == "cc-password.json")
    #expect(SecureNotes.jsonFilename(all: false, isPassword: false) == "cc-note.json")
    #expect(SecureNotes.sevenZipFilename(jsonName: "cc-notes.json") == "cc-notes.7z")
    #expect(SecureNotes.successStory(encrypted: true, filename: "cc-notes.7z", signatureFilename: nil)
            == "Encrypted export file written:\n\ncc-notes.7z")
    #expect(SecureNotes.successStory(encrypted: false, filename: "cc-note.json", signatureFilename: "cc-note.sig")
            == "Export file written:\n\ncc-note.json\n\nSignature file written:\n\ncc-note.sig")
}

@Test func secureNotesExportPromptPutsQRWarningLast() {
    let prompt = SecureNotes.exportPrompt(item: "all notes & passwords", virtualDiskEnabled: false)
    #expect(prompt.hasPrefix("Press (1) to save all notes & passwords to SD Card"))
    #expect(prompt.hasSuffix(SecureNotes.qrExportWarning))
    #expect(prompt.contains("QR to show QR code."))
    #expect(!prompt.contains("Press ENTER to save"))
}

@Test func secureNotesImportPromptMatchesFirmware() {
    #expect(SecureNotes.importPrompt(virtualDiskEnabled: false)
            == "Press (1) to import secure notes and/or passwords from SD Card, (B) for lower slot, QR to scan QR code.")
}

@Test func secureNotesSortingIsNotLocalized() {
    let groups = SecureNotes.sortedGroupNames(["banana", "Apple", "apple"])
    #expect(groups == ["Apple", "apple", "banana"])
    #expect(SecureNotes.compareTitles("apple", "Zebra"))
    #expect(!SecureNotes.compareTitles("Zebra", "apple"))
}

@Test func secureNotesPassphrasePredicateUsesUntrimmedValue() {
    #expect(SecureNotes.isB39PassApplicable("hello", readOnly: false, relatedKeys: false, wordBased: true))
    #expect(!SecureNotes.isB39PassApplicable("hello\n", readOnly: false, relatedKeys: false, wordBased: true))
    #expect(SecureNotes.isB39PassApplicable("hello ", readOnly: false, relatedKeys: false, wordBased: true))
    #expect(SecureNotes.rstripPassphrase("hello \n\t") == "hello")
    #expect(SecureNotes.rstripPassphrase("  hello") == "  hello")
    #expect(!SecureNotes.isB39PassApplicable("hello", readOnly: true, relatedKeys: false, wordBased: true))
    #expect(SecureNotes.isB39PassApplicable("hello", readOnly: true, relatedKeys: true, wordBased: true))
    #expect(!SecureNotes.isB39PassApplicable("hello", readOnly: false, relatedKeys: true, wordBased: false))
}

@Test func secureNotesDensePasswordAndToggleCase() {
    let secret = Data(repeating: 0x01, count: 64)
    let dense = SecureNotes.densePassword(from: secret)
    #expect(dense.count == 21)
    #expect(!dense.contains("+"))
    #expect(!dense.contains("/"))
    #expect(SecureNotes.toggleCase("Hello") == "hello")
    #expect(SecureNotes.toggleCase("hello") == "HELLO")
    #expect(SecureNotes.toggleCase("") == "")
}

@Test func emulatedKeyboardCanTypeMatchesFirmwareCharMap() {
    #expect(EmulatedKeyboard.canType("Abc 123/+-*"))
    #expect(!EmulatedKeyboard.canType("p@ss!"))
    #expect(SecureNotes.sendPasswordUntypeable.contains("cannot type"))
}

@Test func secureNotesImportTaster() throws {
    let json = try SecureNotes.encodeNotesJSON([["title": "n"]])
    #expect(SecureNotes.isImportCandidate(filename: "cc-notes.json", data: json))
    #expect(SecureNotes.isImportCandidate(filename: "cc-notes.7z", data: Data(repeating: 1, count: 16)))
    #expect(!SecureNotes.isImportCandidate(filename: "other.json", data: Data("{}\n".utf8)))
    #expect(!SecureNotes.isImportCandidate(filename: "note.txt", data: json))
    #expect(SecureNotes.isImportSizeOK(8))
    #expect(SecureNotes.isImportSizeOK(100_000))
    #expect(!SecureNotes.isImportSizeOK(7))
    #expect(!SecureNotes.isImportSizeOK(100_001))
    #expect(SecureNotes.incorrectFormatMessage == "Incorrect format")
}

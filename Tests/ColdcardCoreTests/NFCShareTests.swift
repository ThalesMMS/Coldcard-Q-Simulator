import Foundation
import Testing
@testable import ColdcardCore

@Test func nfcShareFilenameTasterMatchesFirmwareShareFile() {
    #expect(NFCShare.isSuitableFilename("signed.psbt"))
    #expect(NFCShare.isSuitableFilename("abc.TXN"))
    #expect(NFCShare.isSuitableFilename("note.txt"))
    #expect(NFCShare.isSuitableFilename("wallet.json"))
    #expect(NFCShare.isSuitableFilename("digest.sig"))
    #expect(!NFCShare.isSuitableFilename("backup.7z"))
    #expect(NFCShare.kind(forFilename: "x.psbt") == .psbt)
    #expect(NFCShare.kind(forFilename: "x.sig") == .text)
}

@Test func nfcShareParsesFirmwareEphemeralSeedNFCPayload() throws {
    let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    let tokens = NFCShare.seedWordList(from: phrase)
    #expect(tokens?.count == 12)
    let expanded = try NFCShare.expandBIP39Words(tokens ?? [])
    #expect(try BIP39Mnemonic(words: expanded).words.last == "about")
    let truncated = phrase.split(separator: " ").map { String($0.prefix(4)) }.joined(separator: " ")
    let short = NFCShare.seedWordList(from: truncated)
    #expect(short?.count == 12)
    #expect(try NFCShare.expandBIP39Words(short ?? []) == expanded)
    #expect(NFCShare.seedWordList(from: "too short") == nil)
    #expect(NFCShare.seedWordList(fromUTF8: Data([0xff, 0xfe])) == nil)
}

@Test func nfcStartMsgSignAcceptsOneToThreeLines() {
    #expect(NFCShare.nfcSignMessagePayload(from: "hello there") == "hello there")
    #expect(NFCShare.nfcSignMessagePayload(from: "hello there\nm/84h/1h/0h/0/0") != nil)
    #expect(NFCShare.nfcSignMessagePayload(from: "hello there\nm/84h/1h/0h/0/0\np2wpkh") != nil)
    #expect(NFCShare.nfcSignMessagePayload(from: "a\nb\nc\nd") == nil)
    #expect(NFCShare.nfcSignMessagePayload(from: "{\"msg\":\"hi there\"}") != nil)
}

import Foundation
import Testing
@testable import ColdcardCore

@Test func hobbledScanAnythingCopyMatchesFirmware() {
    #expect(ScanAnything.hobbledBlockedTitle == "Sorry")
    #expect(ScanAnything.hobbledBlockedBody == "Blocked when Spending Policy is in force.")
}

@Test func hobbledScanAnythingWhitelistMatchesFirmware() {
    let allowed: [ScanAnythingKind] = [.psbt, .addr, .vmsg, .text, .xpub, .teleport]
    for kind in allowed {
        #expect(ScanAnything.allowsHobbled(kind, relatedKeys: false))
        #expect(ScanAnything.allowsHobbled(kind, relatedKeys: true))
    }

    #expect(!ScanAnything.allowsHobbled(.xprv, relatedKeys: false))
    #expect(!ScanAnything.allowsHobbled(.words, relatedKeys: false))
    #expect(ScanAnything.allowsHobbled(.xprv, relatedKeys: true))
    #expect(ScanAnything.allowsHobbled(.words, relatedKeys: true))

    for kind: ScanAnythingKind in [.wif, .txn, .multi, .smsg, .json] {
        #expect(!ScanAnything.allowsHobbled(kind, relatedKeys: false))
        #expect(!ScanAnything.allowsHobbled(kind, relatedKeys: true))
    }
}

@Test func scanAnythingClassifiesSecretsLikeFirmware() throws {
    let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    #expect(ScanAnything.classifyText(mnemonic.phrase) == .words)
    #expect(ScanAnything.classifyText(mnemonic.words.map { String($0.prefix(4)) }.joined(separator: " ")) == .words)
    #expect(ScanAnything.classifyText(mnemonic.seedQR) == .words)

    let root = try HDKey(seed: mnemonic.seed(passphrase: ""), network: .testnet)
    let xprv = try root.serializePrivate()
    #expect(ScanAnything.classifyText(xprv) == .xprv)
    #expect(ScanAnything.classifyText("bitcoin:" + xprv) == .xprv)

    let wif = try root.wif()
    #expect(ScanAnything.classifyText(wif) == .wif)

    let xpub = root.serializePublic()
    #expect(ScanAnything.classifyText(xpub) == .xpub)

    let addr = try BitcoinAddress.derive(root: root, type: .nativeSegwit, account: 0, index: 0)
    #expect(ScanAnything.classifyText(addr.address) == .addr)
    #expect(ScanAnything.classifyText("bitcoin:\(addr.address)?amount=1") == .addr)

    #expect(ScanAnything.classifyText("hello from a QR") == .text)
    #expect(ScanAnything.classifyText("signmessage m/84'/1'/0'/0/0 ascii:hello there") == .smsg)
    #expect(ScanAnything.classifyText("{\"msg\":\"hi there\"}") == .smsg)
}

@Test func scanAnythingClassifiesPSBTAndBlockedBBQrTypes() throws {
    let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    let root = try HDKey(seed: mnemonic.seed(passphrase: ""), network: .testnet)
    let psbt = try DemoPSBT.make(root: root)
    let payload = psbt.serialize().base64EncodedString()
    #expect(payload.count > 100)
    #expect(ScanAnything.classifyText(payload) == .psbt)
    #expect(ScanAnything.classifyBBQr(fileType: "P") == .psbt)
    #expect(ScanAnything.classifyBBQr(fileType: "T") == .txn)
    #expect(ScanAnything.classifyBBQr(fileType: "E") == .teleport)
    #expect(ScanAnything.classifyBBQr(fileType: "R") == .teleport)
    #expect(ScanAnything.classifyBBQr(fileType: "J", utf8Body: "{\"name\":\"x\"}") == .json)
    #expect(ScanAnything.classifyBBQr(fileType: "J", utf8Body: "{\"msg\":\"hi\"}") == .smsg)
    #expect(ScanAnything.classifyBBQr(fileType: "U", utf8Body: mnemonic.phrase) == .words)
    #expect(ScanAnything.classifyBBQr(fileType: "X") == nil)

    let armored = """
    -----BEGIN BITCOIN SIGNED MESSAGE-----
    hello from a reasonably long signed-message QR payload used as vmsg
    -----BEGIN BITCOIN SIGNATURE-----
    tb1qtest
    signature
    -----END BITCOIN SIGNATURE-----
    """
    #expect(armored.count > 100)
    #expect(ScanAnything.classifyText(armored) == .vmsg)

    #expect(ScanAnything.classifyText("wsh(sortedmulti(2,[aaaaaaaa/48h/1h/0h/2h]tpubD6NzVbkrYhZ4XgiXtGrdW5XDAPFCL9h7we1vwNCpn8tGbBbkJYbx5GMMfLkbxx/0/*,[bbbbbbbb/48h/1h/0h/2h]tpubD6NzVbkrYhZ4Ybbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/0/*))") == .multi)
}

@Test func relatedKeysGateMatchesOkeys() throws {
    let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    let words = ScanAnything.classifyText(mnemonic.phrase)
    let xprv = ScanAnything.classifyText(try HDKey(seed: mnemonic.seed(passphrase: ""), network: .testnet).serializePrivate())
    #expect(words == .words)
    #expect(xprv == .xprv)
    #expect(!ScanAnything.allowsHobbled(words, relatedKeys: false))
    #expect(!ScanAnything.allowsHobbled(xprv, relatedKeys: false))
    #expect(ScanAnything.allowsHobbled(words, relatedKeys: true))
    #expect(ScanAnything.allowsHobbled(xprv, relatedKeys: true))
}

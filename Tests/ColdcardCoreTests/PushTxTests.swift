import Foundation
import Testing
@testable import ColdcardCore

@Test func pushTxURLMatchesFirmwareSharePushTx() throws {
    let txn = Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    let url = try PushTx.txnToPushTxURL(
        prefix: "https://mempool.space/pushtx#",
        transaction: txn,
        network: .testnet
    )
    #expect(url == "https://mempool.space/pushtx#t=AQAAAAAAAAA&c=ncvPMxgg9Lg&n=XTN")
    let mainnet = try PushTx.txnToPushTxURL(
        prefix: "https://coldcard.com/pushtx#",
        transaction: txn,
        network: .mainnet
    )
    #expect(mainnet == "https://coldcard.com/pushtx#t=AQAAAAAAAAA&c=ncvPMxgg9Lg")
    #expect(!mainnet.contains("&n="))
}

@Test func pushTxHostLabelMatchesFirmwareSplit() {
    #expect(PushTx.hostLabel(for: "https://selfhosted.com/pushtx#") == "selfhosted.com")
    #expect(PushTx.hostLabel(for: "http://127.0.0.1:80?") == "127.0.0.1:80?")
    #expect(PushTx.chooserIndex(current: nil) == 3)
    #expect(PushTx.chooserIndex(current: "https://coldcard.com/pushtx#") == 0)
    #expect(PushTx.chooserIndex(current: "https://example.com/p#") == 2)
}

@Test func pushTxCustomURLValidationMatchesFirmware() {
    #expect(PushTx.validateCustomURL("https://example.com/p#") == nil)
    #expect(PushTx.validateCustomURL("http://127.0.0.1:80?") == nil)
    #expect(PushTx.validateCustomURL("https://x.com/p&") == nil)
    #expect(PushTx.validateCustomURL("ftp://example.com/p#") == "Must start with http:// or https://.")
    #expect(PushTx.validateCustomURL("https://x#") == "Too short.")
    #expect(PushTx.validateCustomURL("https://example.com/p") == "Final char must be # or ? or &.")
}

@Test func pushTxDecodesFirmwareHexAndBinaryTxnFiles() throws {
    let binary = Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    #expect(try PushTx.decodeTxnFile(binary) == binary)
    let hex = Data("0100000000000000\n".utf8)
    #expect(try PushTx.decodeTxnFile(hex) == binary)
    #expect(PushTx.txidFromFilename("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789.txn") != nil)
    #expect(PushTx.txidFromFilename("signed.txn") == nil)
}

@Test func pushTxParsesNFCAddressAndSeedPayloads() throws {
    let shown = try PushTx.parseShowAddress("m/84h/1h/0h/0/0\np2wpkh")
    #expect(shown.type == .nativeSegwit)
    let classic = try PushTx.parseShowAddress("m/44h/1h/0h/0/5")
    #expect(classic.type == .legacy)
    let words = try PushTx.parseEphemeralSeedWords(
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    )
    #expect(words.count == 12)
    let mnemonic = try BIP39Mnemonic(entropy: Data(repeating: 0, count: 16))
    let root = try HDKey(seed: mnemonic.seed(passphrase: ""), network: .testnet)
    let receive = try BitcoinAddress.derive(root: root, type: .nativeSegwit, account: 0, index: 0)
    let bip21 = try PushTx.parseBIP21("bitcoin:\(receive.address)?amount=1")
    #expect(bip21.address == receive.address.lowercased())
    #expect(bip21.args["amount"] == "1")
}

@Test func pushTxMultisigSniffMatchesFirmwareNFCFilter() throws {
    let descriptor = "wsh(sortedmulti(2,[aaaaaaaa/48h/1h/0h/2h]tpubD6NzVbkrYhZ4XgiXtGrdW5XDAPFCL9h7we1vwNCpn8tGbBbkJYbx5GMMfLkbxxv" +
        "wNCpn8tGbBbkJYbx5GMMfLkbxxaaaaaaaaaaaaaaaaaaaaaaaaaaaa/0/*,[bbbbbbbb/48h/1h/0h/2h]tpubD6NzVbkrYhZ4Y" +
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/0/*))#checksum"
    #expect(PushTx.looksLikeMultisig(descriptor))
    let imported = try PushTx.parseMultisigConfig(descriptor)
    #expect(imported.config.contains("sortedmulti(2"))
    #expect(!PushTx.looksLikeMultisig("too short"))
}

@Test func addressOwnershipFindsFirstReceiveAddress() throws {
    let mnemonic = try BIP39Mnemonic(entropy: Data(repeating: 0, count: 16))
    let root = try HDKey(seed: mnemonic.seed(passphrase: ""), network: .testnet)
    let first = try BitcoinAddress.derive(root: root, type: .nativeSegwit, account: 0, index: 0)
    let hit = AddressOwnership.search(address: first.address, root: root, accounts: [0], perChain: 4)
    #expect(hit?.derived.address == first.address)
    #expect(hit?.walletName == AddressType.nativeSegwit.displayName)
    #expect(AddressOwnership.search(address: "tb1qnotours00000000000000000000000000000000",
                                    root: root, accounts: [0], perChain: 2) == nil)
}

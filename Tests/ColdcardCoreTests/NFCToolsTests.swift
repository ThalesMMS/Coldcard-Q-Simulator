import Foundation
import Testing
@testable import ColdcardCore

@Test func nfcShowAddressDerivesExactCustomPath() throws {
    let mnemonic = try BIP39Mnemonic(entropy: Data(repeating: 0, count: 16))
    let root = try HDKey(seed: mnemonic.seed(passphrase: ""), network: .testnet)
    let shown = try PushTx.parseShowAddress("m/84h/1h/0h/0/7\np2wpkh")
    let derived = try BitcoinAddress.derive(root: root, path: DerivationPath(shown.path), type: shown.type)
    let expected = try BitcoinAddress.derive(root: root, type: .nativeSegwit, account: 0, index: 7)
    #expect(derived.address == expected.address)
    #expect(derived.path == "m/84h/1h/0h/0/7")
}

@Test func nfcShowAddressDefaultsToClassicAndRejectsGarbage() throws {
    let classic = try PushTx.parseShowAddress("m/44h/1h/0h/0/5")
    #expect(classic.type == .legacy)
    #expect(throws: PushTxError.self) {
        try PushTx.parseShowAddress("m/84h/1h/0h/0/0\np2tr")
    }
    #expect(throws: PushTxError.self) {
        try PushTx.parseShowAddress("m/84h/1h/0h/0/0\np2wpkh\nextra")
    }
}

@Test func nfcVerifyFindsWIFStoreAndRejectsWrongChain() throws {
    let mnemonic = try BIP39Mnemonic(entropy: Data(repeating: 0, count: 16))
    let root = try HDKey(seed: mnemonic.seed(passphrase: ""), network: .testnet)
    let foreign = try HDKey(seed: Data(repeating: 7, count: 32), network: .testnet)
    guard let privateKey = foreign.privateKey else {
        Issue.record("missing private key")
        return
    }
    let item = WIFStoreItem(publicKeyHex: foreign.publicKey.hexString, privateKeyHex: privateKey.hexString)
    let addr = try BitcoinAddress.address(publicKey: foreign.publicKey, type: .nativeSegwit, network: .testnet)
    let hit = try AddressOwnership.searchUX(
        address: addr, args: [:], root: root, wifKeys: [item], wallets: [], accounts: [0], perChain: 2
    )
    #expect(hit == .wif(storeIndex: 1))
    #expect(throws: AddressOwnershipError.invalidOnChain("Testnet")) {
        try AddressOwnership.searchUX(
            address: "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH",
            args: [:], root: root, wifKeys: [], wallets: [], accounts: [0], perChain: 1
        )
    }
}

@Test func nfcImportParsesJSONDescriptorWrapper() throws {
    let descriptor = "wsh(sortedmulti(2,[aaaaaaaa/48h/1h/0h/2h]tpubD6NzVbkrYhZ4XgiXtGrdW5XDAPFCL9h7we1vwNCpn8tGbBbkJYbx5GMMfLkbxxv" +
        "wNCpn8tGbBbkJYbx5GMMfLkbxxaaaaaaaaaaaaaaaaaaaaaaaaaaaa/0/*,[bbbbbbbb/48h/1h/0h/2h]tpubD6NzVbkrYhZ4Y" +
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/0/*))#checksum"
    let json = "{\"name\":\"Team\",\"desc\":\"\(descriptor)\"}"
    let imported = try PushTx.parseMultisigConfig(json)
    #expect(imported.name == "Team")
    #expect(imported.config.contains("sortedmulti(2"))
    #expect(PushTx.looksLikeMultisig(descriptor))
}

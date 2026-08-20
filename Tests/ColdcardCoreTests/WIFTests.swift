import Foundation
import Testing
@testable import ColdcardCore

@Test func wifRoundTripMatchesHDKeyEncoding() throws {
    let root = try HDKey(seed: Data(repeating: 7, count: 32), network: .testnet)
    let wif = try root.wif()
    let decoded = try WIF.decode(wif)
    #expect(decoded.compressed)
    #expect(decoded.isTestnet)
    #expect(decoded.privateKey == root.privateKey)
    #expect(decoded.publicKey == root.publicKey)
    #expect(decoded.encode(network: .testnet) == wif)
}

@Test func wifMainnetAndTestnetPrefixes() throws {
    let seed = Data(repeating: 9, count: 32)
    let testnet = try HDKey(seed: seed, network: .testnet)
    let mainnet = try HDKey(seed: seed, network: .mainnet)
    let testWIF = try testnet.wif()
    let mainWIF = try mainnet.wif()
    #expect(testWIF.hasPrefix("c"))
    #expect(mainWIF.hasPrefix("K") || mainWIF.hasPrefix("L"))
    #expect(throws: WIFError.wrongNetwork) {
        try WIF.decodeForStore(mainWIF, network: .testnet)
    }
    #expect(throws: WIFError.wrongNetwork) {
        try WIF.decodeForStore(testWIF, network: .mainnet)
    }
}

@Test func wifUncompressedIsRejectedForStoreImport() throws {
    let root = try HDKey(seed: Data(repeating: 3, count: 32), network: .testnet)
    let uncompressed = try root.wif(compressed: false)
    let decoded = try WIF.decode(uncompressed)
    #expect(!decoded.compressed)
    #expect(decoded.publicKey.count == 65)
    #expect(throws: WIFError.uncompressedOnly) {
        try WIF.decodeForStore(uncompressed, network: .testnet)
    }
}

@Test func wifImportSkipsGarbageAndFailsWhenNothingValid() {
    let garbage = "not-a-wif;cPPBMnQzGV4QAqD2HNPamprjvnmv6dQ2oysHCUVSRv2yXkVvWVtX"
    #expect(throws: WIFError.noValidKey(duplicates: false)) {
        try WIFStoreLogic.parseImport(garbage, network: .testnet, existing: [])
    }
}

@Test func wifStoreRejectsDuplicatesAndEnforcesCapacity() throws {
    let keys = try (0..<3).map { index in
        let root = try HDKey(seed: Data(repeating: UInt8(index + 1), count: 32), network: .testnet)
        return try WIF.decodeForStore(root.wif(), network: .testnet)
    }
    let first = try WIFStoreLogic.merge(existing: [], incoming: keys)
    #expect(first.count == 3)
    #expect(throws: WIFError.noValidKey(duplicates: true)) {
        try WIFStoreLogic.merge(existing: first, incoming: keys)
    }

    let many = try (0..<31).map { index in
        var seed = Data(count: 32)
        seed[0] = UInt8(index + 10)
        seed[1] = UInt8(index)
        let root = try HDKey(seed: seed, network: .testnet)
        return try WIF.decodeForStore(root.wif(), network: .testnet)
    }
    #expect(throws: WIFError.capacity(attempted: 31, remaining: 30)) {
        try WIFStoreLogic.merge(existing: [], incoming: many)
    }

    let almostFull = Array(many.prefix(29))
    #expect(throws: WIFError.capacity(attempted: 2, remaining: 1)) {
        try WIFStoreLogic.merge(existing: almostFull, incoming: Array(many.suffix(2)))
    }
}

@Test func wifMenuLabelTruncatesForQ() throws {
    let wif = "cUR6JLQCmdPPt3op4jEYmFhjHpWC2AoZaWmZqoDaBQYMXN4QeKuc"
    #expect(WIFStoreLogic.menuLabel(index: 0, wif: wif, qwerty: true) == " 1: cUR6JLQCmdPP⋯BQYMXN4QeKuc")
    #expect(WIFStoreLogic.menuLabel(index: 9, wif: wif, qwerty: false) == "10: cUR6J⋯QeKuc")
}

/// Firmware `WIFStoreMenu.construct` (`wif.py`): empty store keeps Import WIF plus inert `(none yet)`.
@Test func wifEmptyStoreKeepsInertNoneYetNextToImport() {
    #expect(WIFStoreLogic.rootMenuTitles(itemLabels: [], hobbled: false) == [
        "Import WIF", "(none yet)"
    ])
    #expect(WIFStoreLogic.rootMenuTitles(itemLabels: [], hobbled: true) == ["(none yet)"])
}

@Test func wifStoreOmitsImportWhenFullAndAddsExportWhenTwoOrMore() {
    let one = [" 1: abc"]
    #expect(WIFStoreLogic.rootMenuTitles(itemLabels: one, hobbled: false) == [
        "Import WIF", " 1: abc"
    ])
    let two = [" 1: abc", " 2: def"]
    #expect(WIFStoreLogic.rootMenuTitles(itemLabels: two, hobbled: false) == [
        "Import WIF", " 1: abc", " 2: def", "Export All", "Clear All"
    ])
    #expect(WIFStoreLogic.rootMenuTitles(itemLabels: two, hobbled: true) == [
        " 1: abc", " 2: def", "Export All"
    ])
    let full = (0..<WIF.maxStoreItems).map { String(format: "%2d: k", $0 + 1) }
    let titles = WIFStoreLogic.rootMenuTitles(itemLabels: full, hobbled: false)
    #expect(!titles.contains("Import WIF"))
    #expect(titles.contains("Export All"))
    #expect(titles.contains("Clear All"))
    #expect(!titles.contains("(none yet)"))
}

@Test func wifDescriptorsAndAddressesMatchSinglesigScripts() throws {
    let root = try HDKey(seed: Data(repeating: 11, count: 32), network: .testnet)
    let decoded = try WIF.decodeForStore(root.wif(), network: .testnet)
    guard let publicKey = decoded.publicKey else {
        Issue.record("WIF store item missing public key")
        return
    }
    for type in AddressType.singlesigExportOrder {
        let addr = try BitcoinAddress.address(publicKey: publicKey, type: type, network: .testnet)
        let expected = try BitcoinAddress.address(publicKey: root.publicKey, type: type, network: .testnet)
        #expect(addr == expected)
        let descriptor = try WIFStoreLogic.descriptor(publicKeyHex: decoded.publicKeyHex, type: type)
        #expect(descriptor.contains(decoded.publicKeyHex))
        #expect(descriptor.contains("#"))
        switch type {
        case .nativeSegwit: #expect(descriptor.hasPrefix("wpkh("))
        case .legacy: #expect(descriptor.hasPrefix("pkh("))
        case .wrappedSegwit: #expect(descriptor.hasPrefix("sh(wpkh("))
        case .taproot: Issue.record("taproot is not a WIF Store address type")
        }
    }
}

@Test func wifMessageSignUsesEmptyPathAndRecoverableAddress() throws {
    let root = try HDKey(seed: Data(repeating: 13, count: 32), network: .testnet)
    let decoded = try WIF.decodeForStore(root.wif(), network: .testnet)
    guard let privateKey = decoded.privateKey, let publicKey = decoded.publicKey else {
        Issue.record("WIF store item missing key material")
        return
    }
    let signed = try BitcoinMessageSigner.sign(
        "Coinkite",
        privateKey: privateKey,
        publicKey: publicKey,
        type: .nativeSegwit,
        network: .testnet
    )
    #expect(signed.path == "m")
    #expect(signed.message == "Coinkite")
    let warning = try BitcoinMessageSigner.verify(
        message: signed.message,
        address: signed.address,
        signatureBase64: signed.signatureBase64
    )
    #expect(warning.isEmpty)
}

@Test func firmwareImportFailureVectors() {
    #expect(throws: WIFError.wrongNetwork) {
        try WIF.decodeForStore("Ky2BtsR8qRN91PjktxaTQWMgJZUWSBJLjwip642vvoNyH1PeEpUP", network: .testnet)
    }
    #expect(throws: WIFError.uncompressedOnly) {
        try WIF.decodeForStore("91zb4oYGEvwEroihAbkdeoBpLSKnZYMdD1CPhfQD76fxrfNSp5J", network: .testnet)
    }
    #expect(throws: WIFError.self) {
        try WIF.decode("cWALDjUu1tszsCBMjBjL4mhYj2wHUWYDR8Q8aSjLKzjkWaXMLRaY")
    }
    #expect(throws: WIFError.self) {
        try WIF.decode("cMahea7zqjxrtgAbB7LSGbcQUr1uX1ojuat9jZodMN87J7g8rY9t")
    }
    #expect(throws: WIFError.self) {
        try WIF.decode("cPPBMnQzGV4QAqD2HNPamprjvnmv6dQ2oysHCUVSRv2yXkVvWVtX")
    }
}

import XCTest
@testable import ColdcardCore

/// Firmware `export.py` remaining parity: OrderedDict key order, public.txt, QR threshold, .sig story.
final class WalletExportParityTests: XCTestCase {
    private func abandonRoot() throws -> HDKey {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        return try HDKey(seed: mnemonic.seed(), network: .testnet)
    }

    func testWasabiJSONKeyOrderMatchesFirmwareOrderedDict() throws {
        let json = String(decoding: try WalletExporter.wasabiWallet(root: try abandonRoot()), as: UTF8.self)
        XCTAssertEqual(
            jsonObjectKeys(json),
            ["ColdCardFirmwareVersion", "MasterFingerprint", "ExtPubKey"]
        )
    }

    func testElectrumJSONKeyOrderMatchesFirmwareOrderedDict() throws {
        let root = try abandonRoot()
        let json = String(decoding: try WalletExporter.electrumWallet(root: root, type: .nativeSegwit), as: UTF8.self)
        XCTAssertEqual(
            jsonObjectKeys(json),
            ["seed_version", "use_encryption", "wallet_type", "keystore"]
        )
        XCTAssertEqual(
            nestedObjectKeys(json, key: "keystore"),
            ["type", "hw_type", "label", "ckcc_xfp", "ckcc_xpub", "derivation", "xpub"]
        )
    }

    func testGenericJSONKeyOrderMatchesFirmwareOrderedDict() throws {
        let json = String(decoding: try WalletExporter.firmwareGenericJSON(root: try abandonRoot()), as: UTF8.self)
        XCTAssertEqual(
            jsonObjectKeys(json),
            ["chain", "xfp", "account", "xpub", "bip44", "bip49", "bip84", "bip48_1", "bip48_2", "bip45"]
        )
        XCTAssertEqual(
            nestedObjectKeys(json, key: "bip44"),
            ["name", "xfp", "deriv", "xpub", "desc", "first"]
        )
        XCTAssertEqual(
            nestedObjectKeys(json, key: "bip84"),
            ["name", "xfp", "deriv", "xpub", "desc", "_pub", "first"]
        )
        XCTAssertEqual(
            nestedObjectKeys(json, key: "bip48_1"),
            ["name", "xfp", "deriv", "xpub", "desc"]
        )
    }

    func testUnchainedJSONIteratesMSStdDerivationsWithP2SHInsideLoop() throws {
        let json = String(decoding: try WalletExporter.unchained(root: try abandonRoot()), as: UTF8.self)
        XCTAssertEqual(
            jsonObjectKeys(json),
            ["xfp", "account", "p2sh_deriv", "p2sh", "p2sh_p2wsh_deriv", "p2sh_p2wsh", "p2wsh_deriv", "p2wsh"]
        )
        let accountOne = String(decoding: try WalletExporter.unchained(root: try abandonRoot(), account: 1), as: UTF8.self)
        XCTAssertEqual(
            jsonObjectKeys(accountOne),
            ["xfp", "account", "p2sh_p2wsh_deriv", "p2sh_p2wsh", "p2wsh_deriv", "p2wsh"]
        )
    }

    func testBitcoinCoreEmbeddedJSONFieldOrderMatchesFirmware() throws {
        let core = try WalletExporter.bitcoinCore(root: try abandonRoot())
        let importDesc = try XCTUnwrap(embeddedJSON(in: core, after: "importdescriptors '"))
        let importMulti = try XCTUnwrap(embeddedJSON(in: core, after: "importmulti '"))
        XCTAssertEqual(
            nestedObjectKeys("{\"item\":" + firstArrayObject(importDesc) + "}", key: "item"),
            ["desc", "active", "timestamp", "internal", "range"]
        )
        XCTAssertEqual(
            nestedObjectKeys("{\"item\":" + firstArrayObject(importMulti) + "}", key: "item"),
            ["desc", "range", "timestamp", "internal", "keypool", "watchonly"]
        )
    }

    func testDumpSummaryHasNoBlankLineAfterXpubBlock() throws {
        let root = try abandonRoot()
        let summary = try WalletExporter.dumpSummary(root: root)
        let xpub = try root.derived(path: DerivationPath.account(type: .legacy, network: .testnet)).neutered().serializePublic()
        XCTAssertTrue(summary.contains("m/44h/1h/0h => \(xpub)\nm/44h/1h/0h/0/0 => "))
        XCTAssertFalse(summary.contains("##SLIP-132##\n\nm/"))
        XCTAssertTrue(summary.contains("##SLIP-132##\nm/"))
        XCTAssertFalse(summary.contains("# Your Multisig Wallets"))
    }

    func testDumpSummaryAppendsMultisigSection() throws {
        let root = try abandonRoot()
        let other = try HDKey(seed: Data(repeating: 3, count: 64), network: .testnet)
        let path = try DerivationPath("m/48'/1'/0'/2'")
        let wallet = MultisigWalletConfig(
            name: "CC-2-of-2",
            requiredSignatures: 2,
            totalSigners: 2,
            addressFormat: .p2wsh,
            chain: "XTN",
            bip67: true,
            cosigners: [
                MultisigCosigner(fingerprint: root.fingerprintHex, derivation: "m/48h/1h/0h/2h",
                                 xpub: try root.derived(path: path).neutered().serializePublic()),
                MultisigCosigner(fingerprint: other.fingerprintHex, derivation: "m/48h/1h/0h/2h",
                                 xpub: try other.derived(path: path).neutered().serializePublic())
            ]
        )
        let summary = try WalletExporter.dumpSummary(root: root, wallets: [wallet])
        XCTAssertTrue(summary.contains("\n# Your Multisig Wallets\n\n"))
        XCTAssertTrue(summary.contains("Name: CC-2-of-2"))
        XCTAssertTrue(summary.contains("Policy: 2 of 2"))
        XCTAssertTrue(summary.contains("\n---\n"))
    }

    func testWalletExportQRUsesSingleQRAtOrBelow2000Characters() {
        XCTAssertEqual(WalletExporter.qrCharacterLimit, 2000)
        XCTAssertFalse(WalletExporter.usesBBQr(body: String(repeating: "a", count: 2000)))
        XCTAssertTrue(WalletExporter.usesBBQr(body: String(repeating: "a", count: 2001)))
        XCTAssertTrue(WalletExporter.usesBBQr(body: "short", forceBBQr: true))
        XCTAssertEqual(WalletExporter.bbqrTypeCode(isJSON: true), "J")
        XCTAssertEqual(WalletExporter.bbqrTypeCode(isJSON: false), "U")
    }

    func testDetachedSignatureStoryAndDerivationsMatchExportContents() {
        XCTAssertEqual(
            WalletExporter.fileWrittenStory(title: "Generic Export", filename: "coldcard-export.json",
                                            signatureFilename: "coldcard-export.sig"),
            "Generic Export file written:\n\ncoldcard-export.json\n\nGeneric Export signature file written:\n\ncoldcard-export.sig"
        )
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .generic, coinType: 1, account: 2).derive,
                       "m/44h/1h/2h/0/0")
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .generic, coinType: 1, account: 2).addressType,
                       .legacy)
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .electrum(.nativeSegwit), coinType: 1).derive,
                       "m/84h/1h/0h/0/0")
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .electrum(.nativeSegwit), coinType: 1).addressType,
                       .nativeSegwit)
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .wasabi, coinType: 1).derive,
                       "m/84h/1h/0h/0/0")
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .wasabi, coinType: 1).addressType,
                       .nativeSegwit)
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .unchained, coinType: 1, account: 0).derive,
                       "m/48h/1h/0h/2h/0/0")
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .unchained, coinType: 1).addressType,
                       .legacy)
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .bitcoinCore, coinType: 1, account: 3).derive,
                       "m/84h/1h/3h/0/0")
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .dumpSummary, coinType: 1).derive,
                       "m/44h/1h/0h/0/0")
        XCTAssertEqual(WalletExporter.detachedSignatureContext(format: .descriptor(.wrappedSegwit), coinType: 1, account: 1).derive,
                       "m/49h/1h/1h/0/0")
        XCTAssertEqual(
            WalletExporter.detachedSignatureContext(
                format: .keyExpression(derive: "m/48h/1h/0h/2h", addressType: .legacy), coinType: 1
            ).derive,
            "m/48h/1h/0h/2h/0/0"
        )
    }
}

private func jsonObjectKeys(_ json: String) -> [String] {
    var keys: [String] = []
    var depth = 0
    var index = json.startIndex
    while index < json.endIndex {
        let character = json[index]
        if character == "{" || character == "[" {
            depth += 1
            index = json.index(after: index)
            continue
        }
        if character == "}" || character == "]" {
            depth -= 1
            index = json.index(after: index)
            continue
        }
        if character == "\"" {
            let start = json.index(after: index)
            var cursor = start
            var escaped = false
            while cursor < json.endIndex {
                if escaped {
                    escaped = false
                    cursor = json.index(after: cursor)
                    continue
                }
                if json[cursor] == "\\" {
                    escaped = true
                    cursor = json.index(after: cursor)
                    continue
                }
                if json[cursor] == "\"" { break }
                cursor = json.index(after: cursor)
            }
            let value = String(json[start..<cursor])
            let closing = cursor
            var after = json.index(after: closing)
            while after < json.endIndex, json[after].isWhitespace {
                after = json.index(after: after)
            }
            if after < json.endIndex, json[after] == ":" {
                if depth == 1 { keys.append(value) }
                index = json.index(after: after)
            } else {
                index = json.index(after: closing)
            }
            continue
        }
        index = json.index(after: index)
    }
    return keys
}

private func nestedObjectKeys(_ json: String, key: String) -> [String] {
    guard let range = json.range(of: "\"\(key)\"") else { return [] }
    var index = range.upperBound
    while index < json.endIndex, json[index] != "{" {
        index = json.index(after: index)
    }
    guard index < json.endIndex else { return [] }
    var depth = 0
    var end = index
    while end < json.endIndex {
        if json[end] == "{" { depth += 1 }
        if json[end] == "}" {
            depth -= 1
            if depth == 0 {
                return jsonObjectKeys(String(json[index...end]))
            }
        }
        end = json.index(after: end)
    }
    return []
}

private func embeddedJSON(in text: String, after marker: String) -> String? {
    guard let start = text.range(of: marker)?.upperBound else { return nil }
    guard let end = text[start...].firstIndex(of: "'") else { return nil }
    return String(text[start..<end])
}

private func firstArrayObject(_ json: String) -> String {
    guard let start = json.firstIndex(of: "{") else { return json }
    var depth = 0
    var end = start
    while end < json.endIndex {
        if json[end] == "{" { depth += 1 }
        if json[end] == "}" {
            depth -= 1
            if depth == 0 { return String(json[start...end]) }
        }
        end = json.index(after: end)
    }
    return json
}

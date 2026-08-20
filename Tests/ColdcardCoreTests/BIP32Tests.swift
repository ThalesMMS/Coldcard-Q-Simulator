import XCTest
@testable import ColdcardCore

final class BIP32Tests: XCTestCase {
    func testBIP39VectorMasterXPrv() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(passphrase: "TREZOR"), network: .mainnet)
        XCTAssertEqual(try root.serializePrivate(), "xprv9s21ZrQH143K3h3fDYiay8mocZ3afhfULfb5GX8kCBdno77K4HiA15Tg23wpbeF1pLfs1c5SPmYHrEpTuuRhxMwvKDwqdKiGJS9XFKzUsAF")
    }

    func testStringPathDeeperThanMaxDepthIsRejected() {
        let allowed = "m/" + Array(repeating: "0", count: DerivationPath.maxDepth).joined(separator: "/")
        XCTAssertNoThrow(try DerivationPath(allowed))
        let tooDeep = "m/" + Array(repeating: "0", count: DerivationPath.maxDepth + 1).joined(separator: "/")
        XCTAssertThrowsError(try DerivationPath(tooDeep)) { error in
            guard case BIP32Error.invalidPath = error else {
                return XCTFail("expected invalidPath, got \(error)")
            }
        }
    }

    func testPublicAndPrivateNonHardenedDerivationMatch() throws {
        let seed = try Data(hex: "000102030405060708090a0b0c0d0e0f")
        let root = try HDKey(seed: seed, network: .mainnet)
        let fromPrivate = try root.derived(index: 7).neutered()
        let fromPublic = try root.neutered().derived(index: 7)
        XCTAssertEqual(fromPrivate.publicKey, fromPublic.publicKey)
        XCTAssertEqual(fromPrivate.chainCode, fromPublic.chainCode)
        XCTAssertEqual(fromPrivate.serializePublic(), fromPublic.serializePublic())
    }

    func testBIP84FirstAddress() throws {
        let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let root = try HDKey(seed: mnemonic.seed(), network: .mainnet)
        let address = try BitcoinAddress.derive(root: root, type: .nativeSegwit, index: 0)
        XCTAssertEqual(address.path, "m/84h/0h/0h/0/0")
        XCTAssertEqual(address.address, "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
    }

    func testAddressFamilies() throws {
        let root = try HDKey(seed: Data(repeating: 7, count: 32), network: .testnet)
        for type in AddressType.allCases {
            let derived = try BitcoinAddress.derive(root: root, type: type, index: 0)
            XCTAssertFalse(derived.address.isEmpty)
            XCTAssertFalse(derived.scriptPubKeyHex.isEmpty)
        }
    }
}

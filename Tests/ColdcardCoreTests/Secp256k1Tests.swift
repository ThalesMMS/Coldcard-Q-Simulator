import XCTest
@testable import ColdcardCore

final class Secp256k1Tests: XCTestCase {
    func testGeneratorPublicKey() throws {
        let privateKey = Data(repeating: 0, count: 31) + Data([1])
        let pubkey = try Secp256k1.publicKey(fromPrivateKey: privateKey)
        XCTAssertEqual(pubkey.hexString, "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
        XCTAssertEqual(try Secp256k1.parsePublicKey(pubkey), try Secp256k1.publicPoint(fromPrivateKey: privateKey))
    }

    func testDeterministicSignatureRoundTrip() throws {
        let privateKey = try Data(hex: "1e99423a4ed27608a15a2616f74f33c62b9f5635d4a294d2f2f908b9d327a33d")
        let hash = SHA2.sha256(Data("Coldcard Q Swift simulator".utf8))
        let signature1 = try Secp256k1.sign(hash: hash, privateKey: privateKey)
        let signature2 = try Secp256k1.sign(hash: hash, privateKey: privateKey)
        XCTAssertEqual(signature1, signature2)
        let pubkey = try Secp256k1.publicKey(fromPrivateKey: privateKey)
        XCTAssertTrue(Secp256k1.verify(hash: hash, derSignature: signature1.der, publicKey: pubkey))
        XCTAssertFalse(Secp256k1.verify(hash: SHA2.sha256(Data("different".utf8)), derSignature: signature1.der, publicKey: pubkey))
        var compact = Data([31 + signature1.recoveryID])
        compact.append(signature1.r)
        compact.append(signature1.s)
        XCTAssertEqual(try Secp256k1.recoverPublicKey(hash: hash, compactSignature: compact), pubkey)
    }

    func testPrivateKeyAddition() throws {
        let one = Data(repeating: 0, count: 31) + Data([1])
        let two = Data(repeating: 0, count: 31) + Data([2])
        let three = try Secp256k1.addPrivateKeys(one, two)
        XCTAssertEqual(three, Data(repeating: 0, count: 31) + Data([3]))
    }
}

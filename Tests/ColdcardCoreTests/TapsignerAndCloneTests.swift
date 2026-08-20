import Foundation
import Testing
@testable import ColdcardCore

@Test func aes128ECBMatchesFIPS197AppendixC1() throws {
    // CTR of zeros with the FIPS-197 C.1 block as the counter equals AES-128 ECB.
    let key = try Data(hex: "000102030405060708090a0b0c0d0e0f")
    let block = try Data(hex: "00112233445566778899aabbccddeeff")
    let expected = try Data(hex: "69c4e0d86a7b0430d8cdb78070b4c55a")
    let zeros = Data(repeating: 0, count: 16)
    #expect(try AESCTR.crypt(key: key, nonce: block, data: zeros) == expected)
}

@Test func tapsignerDecryptsRealBackup4VMI3() throws {
    let ciphertext = try Data(hex: "d56f7b3b0c5d05edf3ae05aa4466234ef462eab68ad6af031ae8a56287b984bedb7eb7658ecfe158e6987e118008c11f52df63068b75ed4b060c173d2950ba06aa63bf3b719913b44e2bf576e0527cd8222199098576bed7b14a8f838b0ad0856c79014142078ab1b519e4f1560d5c7e312c7dbab1e7896a82d7d4a7")
    let backup = try TapsignerBackup.decrypt(backupKeyHex: "cb5bec9ddea4e85558bb54f41dcb1d2e", data: ciphertext)
    #expect(backup.extendedPrivateKey.hasPrefix("xprv"))
    let xpub = try masterPublic(fromExtendedPrivate: backup.extendedPrivateKey, network: .mainnet)
    #expect(xpub == "xpub661MyMwAqRbcFkTtUfByC6u46vJtdw6xFHUFhjc2AvA16BJCUPoeuwQcthN6yshHR34WZBT5gsHYVtha2QD9j9QozJf9ENeHS6TDgSAFBeX")
}

@Test func tapsignerDecryptsRealBackupO4MZA() throws {
    let ciphertext = try Data(hex: "52414a776f1fa63aa0c885056f2b82c1b0e420f77eddc1c176797354e0dfb798ac9cb977c2851eafc6271831358771307e1af16f980f77a7bed29e896ce8f30d49b52c67f3bd290d315056b932194c91b82dfe8afae37d91bb6752d097b7604f7bae734cf42ac49699bfe5b62d2d393ce437b22a06151e5764ae1d67")
    let backup = try TapsignerBackup.decrypt(backupKeyHex: "578efa5d6803e3c314a98a87d499ce97", data: ciphertext)
    #expect(backup.extendedPrivateKey.hasPrefix("xprv"))
    let xpub = try masterPublic(fromExtendedPrivate: backup.extendedPrivateKey, network: .mainnet)
    #expect(xpub == "xpub661MyMwAqRbcGBeMu9h1B222hQmc4XkXasbN4F3mDGTWRJ11UQ5orWv41FPVK7stXsS9UtR5DBTArBvcsHPiCE2E1PAdqq1UQiQTYmrEEaa")
}

@Test func tapsignerRejectsWrongKeyAndShortHex() {
    let ciphertext = Data(repeating: 0x11, count: 124)
    #expect(throws: TapsignerBackupError.decryptionFailed) {
        try TapsignerBackup.decrypt(backupKeyHex: "cb5bec9ddea4e85558bb54f41dcb1d2e", data: ciphertext)
    }
    #expect(throws: TapsignerBackupError.invalidKey) {
        try TapsignerBackup.decrypt(backupKeyHex: "cb5bec9ddea4e85558bb54f41dcb1d", data: ciphertext)
    }
}

@Test func tapsignerDecodesHexAndBase64QRPayloads() throws {
    let raw = try Data(hex: "d56f7b3b0c5d05ed")
    #expect(try TapsignerBackup.payload(fromQR: raw.hexString.uppercased()) == raw)
    #expect(try TapsignerBackup.payload(fromQR: raw.base64EncodedString()) == raw)
}

@Test func nguECDHHashVectors() throws {
    let other = try Data(hex: "0482fb7791e1bb6b7c9951d1fb909be4119e8071dd264716a04413308a736621889d473ebbc93ab53a230d8ef4021603918deb62506697909f3cc44c0b4a1c3de2")
    #expect(try Secp256k1.ecdhHash(privateKey: Data(hex: "3132313231323132313231323132313231323132313231323132313231323132"), otherPublicKey: other).hexString == "6d9b2a61fa586795e38d2ee8bbc3d66fb56f619ed9b0b5f12e76ad9d9827e07c")
    #expect(try Secp256k1.ecdhHash(privateKey: Data(hex: "0fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"), otherPublicKey: other).hexString == "29864c9c5b95e809b5e519a8ebf7aeebe1c4508d1e4a47e1ecefa4f69c1d8a9a")
    #expect(try Secp256k1.ecdhHash(privateKey: Data(hex: "0000000000000000000000000000000000000000000000000000000000000001"), otherPublicKey: other).hexString == "d82cb54eddb720b3b960a78d8d5618395339b82fb7f94ae51aa1e78f76550949")
}

@Test func cloneTransferStartFileAndFilenameRoundTrip() throws {
    let pub = try Secp256k1.publicKey(fromPrivateKey: Data(hex: "0000000000000000000000000000000000000000000000000000000000000001"))
    let json = try CloneTransfer.startFile(compressedPubkey: pub)
    #expect(try CloneTransfer.parseStartFile(json) == pub)
    #expect(CloneTransfer.startFilename == "ccbk-start.json")
    let standIn = CloneTransfer.cloneFilename(compressedPubkey: pub)
    #expect(standIn.hasSuffix("-ccbk.7z"))
    #expect(try CloneTransfer.parseCloneFilename(standIn) == pub)
    #expect(try CloneTransfer.parseCloneFilename(pub.hexString + "-ccbk.7z") == pub)
}

@Test func cloneSessionPasswordIsSharedSecretHex() throws {
    let alice = try Data(hex: "1111111111111111111111111111111111111111111111111111111111111111")
    let bob = try Data(hex: "2222222222222222222222222222222222222222222222222222222222222222")
    let alicePub = try Secp256k1.publicKey(fromPrivateKey: alice)
    let bobPub = try Secp256k1.publicKey(fromPrivateKey: bob)
    let fromAlice = try CloneTransfer.sessionPasswordHex(privateKey: alice, theirPubkey: bobPub)
    let fromBob = try CloneTransfer.sessionPasswordHex(privateKey: bob, theirPubkey: alicePub)
    #expect(fromAlice == fromBob)
    #expect(fromAlice.count == 64)
}

private func masterPublic(fromExtendedPrivate string: String, network: BitcoinNetwork) throws -> String {
    let body = try Base58.checkDecode(string)
    let chain = Data(body[13..<45])
    let priv = Data(body[46..<78])
    return try HDKey.master(privateKey: priv, chainCode: chain, network: network).serializePublic()
}

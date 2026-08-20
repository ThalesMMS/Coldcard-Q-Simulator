import Foundation
import Testing
@testable import ColdcardCore

@Test func aes256FIPS197Block() throws {
    let key = try Data(hex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let plain = try Data(hex: "00112233445566778899aabbccddeeff")
    let cipher = try Data(hex: "8ea2b7ca516745bfeafc49904b496089")
    #expect(AES256CTR.encryptBlock(key: key, plaintext: plain) == cipher)
    #expect(AES256CTR.decryptBlock(key: key, ciphertext: cipher) == plain)
}

@Test func aes256CTRRoundTripAndCounterZero() throws {
    let key = try Data(hex: "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
    let plain = Data("Key Teleport AES-256-CTR body".utf8)
    let cipher = AES256CTR.crypt(key: key, data: plain)
    #expect(cipher != plain)
    #expect(AES256CTR.crypt(key: key, data: cipher) == plain)
    let zeros = Data(count: 16)
    #expect(AES256CTR.crypt(key: key, data: zeros) == AES256CTR.encryptBlock(key: key, plaintext: zeros))
}

@Test func keyTeleportECDHSessionKeyIsSHA256XY() throws {
    let privateKey = Data(repeating: 0, count: 31) + Data([1])
    let pubkey = try Secp256k1.publicKey(fromPrivateKey: privateKey)
    let session = try Secp256k1.ecdhSessionKey(privateKey: privateKey, publicKey: pubkey)
    #expect(session.hexString == "09c0b2d1a486c439a87bcba6b46a7a1a23f3897cc83a94521a96da5c23bc58db")
}

@Test func keyTeleportReceiverCodeRoundTrip() throws {
    let privateKey = try Data(hex: "1111111111111111111111111111111111111111111111111111111111111111")
    let result = try KeyTeleport.generateReceiverCode(privateKey: privateKey)
    #expect(result.numericCode.count == 8)
    #expect(result.numericCode.allSatisfy { $0.isNumber })
    #expect(result.encryptedPubkey.count == 33)
    #expect(KeyTeleport.grouped(result.numericCode).split(separator: " ").count == 4)
    let restored = KeyTeleport.decryptReceiverPubkey(code: result.numericCode, payload: result.encryptedPubkey)
    let expectedPub = try Secp256k1.publicKey(fromPrivateKey: privateKey)
    #expect(restored == expectedPub)
    #expect(KeyTeleport.decryptReceiverPubkey(code: "00000000", payload: result.encryptedPubkey) == nil
            || KeyTeleport.decryptReceiverPubkey(code: "00000000", payload: result.encryptedPubkey) != restored)
}

@Test func keyTeleportPayloadRoundTripWords() throws {
    let rxPrivate = try Data(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    let txPrivate = try Data(hex: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    let rxPub = try Secp256k1.publicKey(fromPrivateKey: rxPrivate)
    let words = "talk retire wisdom poet actress hood goose case amateur zebra analyst radar"
    let mnemonic = try BIP39Mnemonic(phrase: words)
    let body = Data([UInt8(ascii: "s")]) + SecretStash.encode(entropy: mnemonic.entropy)
    let noid = try Data(hex: "0102030405")
    let payload = try KeyTeleport.encodePayload(
        senderPrivateKey: txPrivate,
        receiverPubkey: rxPub,
        noidKey: noid,
        body: body
    )
    #expect(payload.count == 33 + body.count + 4)
    let step1 = try KeyTeleport.decodeStep1(
        receiverPrivateKey: rxPrivate,
        payload: payload
    )
    let senderPub = try Secp256k1.publicKey(fromPrivateKey: txPrivate)
    #expect(step1.senderPubkey == senderPub)
    let final = try KeyTeleport.decodeStep2(sessionKey: step1.sessionKey, noidKey: noid, body: step1.body)
    #expect(final == body)
    let decoded = try SecretStash.decode(Data(final.dropFirst()))
    guard case .words(let entropy) = decoded else {
        Issue.record("expected words stash")
        return
    }
    #expect(try BIP39Mnemonic(entropy: entropy).phrase == words)
}

@Test func keyTeleportPSBTPayloadOmitsSenderPubkey() throws {
    let rxPrivate = try Data(hex: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")
    let txPrivate = try Data(hex: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd")
    let rxPub = try Secp256k1.publicKey(fromPrivateKey: rxPrivate)
    let body = Data([UInt8(ascii: "p")]) + Data("psbt-bytes".utf8)
    let noid = try Data(hex: "aabbccddee")
    let nonce: UInt32 = 0x00ab_cdef
    var prefix = Data()
    prefix.appendUInt32BE(nonce)
    let payload = try KeyTeleport.encodePayload(
        senderPrivateKey: txPrivate,
        receiverPubkey: rxPub,
        noidKey: noid,
        body: body,
        forPSBT: true,
        prefix: prefix
    )
    #expect(payload.prefix(4) == prefix)
    #expect(payload.count == 4 + body.count + 4)
    let step1 = try KeyTeleport.decodePSBTStep1(
        receiverPrivateKey: rxPrivate,
        senderPubkey: try Secp256k1.publicKey(fromPrivateKey: txPrivate),
        payload: payload
    )
    #expect(step1.nonce == nonce)
    let final = try KeyTeleport.decodeStep2(sessionKey: step1.sessionKey, noidKey: noid, body: step1.body)
    #expect(final == body)
}

@Test func keyTeleportNoidPasswordIsEightBase32Chars() throws {
    let key = try Data(hex: "0000000001")
    #expect(KeyTeleport.noidPassword(from: key) == "AAAAAAAB")
    #expect(try KeyTeleport.noidKey(fromPassword: "aaaaaaab") == key)
    #expect(try KeyTeleport.noidKey(fromPassword: "01801801").count == 5)
}

@Test func keyTeleportDerivationConstant() {
    #expect(KeyTeleport.receiverPubkeyChild == 20_250_317)
}

@Test func secretStashEncodesXPRVMarker() throws {
    let chain = Data(repeating: 2, count: 32)
    let priv = Data(repeating: 3, count: 32)
    let encoded = SecretStash.encode(chainCode: chain, privateKey: priv)
    #expect(encoded.first == 0x01)
    guard case .xprv(let decodedChain, let decodedPriv) = try SecretStash.decode(encoded) else {
        Issue.record("expected xprv")
        return
    }
    #expect(decodedChain == chain)
    #expect(decodedPriv == priv)
}

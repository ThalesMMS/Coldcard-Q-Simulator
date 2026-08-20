import Foundation
import Testing
@testable import ColdcardCore

@Test func sha256Vectors() throws {
    #expect(SHA2.sha256(Data()).hexString == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(SHA2.sha256(Data("abc".utf8)).hexString == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func sha512Vectors() {
    #expect(SHA2.sha512(Data()).hexString == "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
    #expect(SHA2.sha512(Data("abc".utf8)).hexString == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
}

@Test func ripemd160Vectors() {
    #expect(RIPEMD160.hash(Data()).hexString == "9c1185a5c5e9fc54612808977ee8f548b2258d31")
    #expect(RIPEMD160.hash(Data("abc".utf8)).hexString == "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc")
}

@Test func hmacVectors() {
    let key = Data(repeating: 0x0b, count: 20)
    #expect(HMAC.sha256(key: key, message: Data("Hi There".utf8)).hexString == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    #expect(HMAC.sha512(key: key, message: Data("Hi There".utf8)).hexString == "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde" + "daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854")
}

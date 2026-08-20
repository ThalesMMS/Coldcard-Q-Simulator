import Foundation
import Testing
@testable import ColdcardCore

@Test func sha1Vectors() {
    #expect(SHA1.hash(Data()).hexString == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    #expect(SHA1.hash(Data("abc".utf8)).hexString == "a9993e364706816aba3e25717850c26c9cd0d89d")
}

@Test func totpRFC6238SHA1() throws {
    let secret = Data("12345678901234567890".utf8)
    #expect(TOTP.code(secret: secret, unixTime: 59, digits: 8) == "94287082")
    #expect(TOTP.code(secret: secret, unixTime: 1_111_111_109, digits: 8) == "07081804")
    #expect(TOTP.code(secret: secret, unixTime: 1_111_111_111, digits: 8) == "14050471")
    #expect(TOTP.verify("287082", secret: secret, unixTime: 59))
}

@Test func spendingPolicyMagnitudeBTCAndSats() throws {
    var policy = SpendingPolicyLimits(mag: 1)
    let under = SpendingPolicyTransaction(outgoingSats: 99_999_999, lockTime: 0, nonChangeAddresses: [], hasWarnings: false)
    let over = SpendingPolicyTransaction(outgoingSats: 100_000_001, lockTime: 0, nonChangeAddresses: [], hasWarnings: false)
    #expect(try policy.evaluate(under, minBlock: 0).needsWeb2FA == false)
    #expect(throws: SpendPolicyViolation.magnitude) {
        try policy.evaluate(over, minBlock: 0)
    }

    policy.mag = 50_000
    #expect(try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 50_000, lockTime: 0, nonChangeAddresses: [], hasWarnings: false), minBlock: 0).needsWeb2FA == false)
    #expect(throws: SpendPolicyViolation.magnitude) {
        try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 50_001, lockTime: 0, nonChangeAddresses: [], hasWarnings: false), minBlock: 0)
    }
}

@Test func spendingPolicyVelocityAndWhitelist() throws {
    var policy = SpendingPolicyLimits(mag: 1, vel: 144, blockH: 800_000)
    #expect(throws: SpendPolicyViolation.noLockTime) {
        try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 1, lockTime: 0, nonChangeAddresses: [], hasWarnings: false), minBlock: 0)
    }
    #expect(throws: SpendPolicyViolation.lockTimeNotHeight) {
        try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 1, lockTime: 500_000_000, nonChangeAddresses: [], hasWarnings: false), minBlock: 0)
    }
    #expect(throws: SpendPolicyViolation.rewound(100)) {
        try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 1, lockTime: 100, nonChangeAddresses: [], hasWarnings: false), minBlock: 0)
    }
    #expect(throws: SpendPolicyViolation.velocity(800_100)) {
        try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 1, lockTime: 800_100, nonChangeAddresses: [], hasWarnings: false), minBlock: 0)
    }
    #expect(try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 1, lockTime: 800_144, nonChangeAddresses: [], hasWarnings: false), minBlock: 0).needsWeb2FA == false)

    policy.vel = nil
    policy.addresses = ["tb1qtestwhitelist000000000000000000000000000"]
    #expect(throws: SpendPolicyViolation.whitelist("tb1qother")) {
        try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 1, lockTime: 0, nonChangeAddresses: ["tb1qother"], hasWarnings: false), minBlock: 0)
    }
}

@Test func spendingPolicyWarningsAndWeb2FA() throws {
    let policy = SpendingPolicyLimits(web2fa: "MFRGGZDFMZTWQ2LK")
    #expect(throws: SpendPolicyViolation.hasWarnings) {
        try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 1, lockTime: 0, nonChangeAddresses: [], hasWarnings: true), minBlock: 0)
    }
    let ok = try policy.evaluate(SpendingPolicyTransaction(outgoingSats: 1, lockTime: 0, nonChangeAddresses: [], hasWarnings: false), minBlock: 0)
    #expect(ok.needsWeb2FA)

    #expect(SpendingPolicyLimits.renderMagnitude(1) == "1 BTC")
    #expect(SpendingPolicyLimits.renderMagnitude(1000) == "1000 SATS")
    #expect(SpendingPolicyLimits.cleanupPaymentAddress("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7") == "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7")
    #expect(SpendingPolicyLimits.cleanupPaymentAddress("not-an-address") == nil)
    #expect(BitcoinNetwork.mainnet.cccMinBlock == 960_398)
    #expect(BitcoinNetwork.testnet.cccMinBlock == 0)
}

@Test func psbtInvolvesMasterFingerprint() throws {
    let mnemonic = try BIP39Mnemonic(phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
    let root = try HDKey(seed: mnemonic.seed(passphrase: ""), network: .testnet)
    let psbt = try DemoPSBT.make(root: root)
    #expect(psbt.involvesMasterFingerprint(root.fingerprintHex))
    #expect(!psbt.involvesMasterFingerprint("00000000"))
}

import Foundation
#if SWIFT_PACKAGE
import BigInt
#endif

public enum Secp256k1Error: Error, Equatable {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidHashLength
    case signingFailed
}

public struct ECDSASignature: Equatable {
    public let r: Data
    public let s: Data
    public let der: Data
    public let recoveryID: UInt8

    public var compactCompressed: Data {
        var output = Data([27 + 4 + recoveryID])
        output.append(r)
        output.append(s)
        return output
    }
}

public enum Secp256k1 {
    public static let fieldPrime = BigUInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", radix: 16)!
    public static let curveOrder = BigUInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", radix: 16)!
    public static let generatorX = BigUInt("79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", radix: 16)!
    public static let generatorY = BigUInt("483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8", radix: 16)!

    public struct PublicPoint: Equatable, @unchecked Sendable {
        public let x: BigUInt
        public let y: BigUInt

        public init(x: BigUInt, y: BigUInt) throws {
            guard x < fieldPrime, y < fieldPrime,
                  mod(y * y, fieldPrime) == mod(x * x * x + 7, fieldPrime) else {
                throw Secp256k1Error.invalidPublicKey
            }
            self.x = x
            self.y = y
        }

        fileprivate init(uncheckedX x: BigUInt, y: BigUInt) {
            self.x = x
            self.y = y
        }
    }

    private struct JacobianPoint {
        var x: BigUInt
        var y: BigUInt
        var z: BigUInt

        static let infinity = JacobianPoint(x: 0, y: 1, z: 0)
        var isInfinity: Bool { z == 0 }
    }

    public static let generator = PublicPoint(uncheckedX: generatorX, y: generatorY)

    public static func privateKeyIsValid(_ key: Data) -> Bool {
        key.count == 32 && BigUInt(key) > 0 && BigUInt(key) < curveOrder
    }

    public static func publicKey(fromPrivateKey privateKey: Data, compressed: Bool = true) throws -> Data {
        let scalar = try privateScalar(privateKey)
        guard let point = scalarMultiply(generator, scalar: scalar) else { throw Secp256k1Error.invalidPrivateKey }
        return serialize(point, compressed: compressed)
    }

    public static func publicPoint(fromPrivateKey privateKey: Data) throws -> PublicPoint {
        let scalar = try privateScalar(privateKey)
        guard let point = scalarMultiply(generator, scalar: scalar) else { throw Secp256k1Error.invalidPrivateKey }
        return point
    }

    /// Firmware ECDH hashfp: SHA256(X || Y) of the shared point (`teleport.py` / `key-teleport.md`).
    public static func ecdhSessionKey(privateKey: Data, publicKey: Data) throws -> Data {
        let scalar = try privateScalar(privateKey)
        let point = try parsePublicKey(publicKey)
        guard let shared = scalarMultiply(point, scalar: scalar) else { throw Secp256k1Error.invalidPublicKey }
        return SHA2.sha256(shared.x.serializedPadded(to: 32) + shared.y.serializedPadded(to: 32))
    }

    public static func parsePublicKey(_ data: Data) throws -> PublicPoint {
        if data.count == 33, data[0] == 0x02 || data[0] == 0x03 {
            let x = BigUInt(data.dropFirst())
            guard x < fieldPrime else { throw Secp256k1Error.invalidPublicKey }
            let alpha = mod(x * x * x + 7, fieldPrime)
            let beta = alpha.power((fieldPrime + 1) >> 2, modulus: fieldPrime)
            let wantsOdd = data[0] == 0x03
            let y = beta.isOdd == wantsOdd ? beta : fieldPrime - beta
            guard mod(y * y, fieldPrime) == alpha else { throw Secp256k1Error.invalidPublicKey }
            return PublicPoint(uncheckedX: x, y: y)
        }
        if data.count == 65, data[0] == 0x04 {
            let x = BigUInt(data.subdata(in: 1..<33))
            let y = BigUInt(data.subdata(in: 33..<65))
            return try PublicPoint(x: x, y: y)
        }
        throw Secp256k1Error.invalidPublicKey
    }

    public static func serialize(_ point: PublicPoint, compressed: Bool = true) -> Data {
        let x = point.x.serializedPadded(to: 32)
        if compressed {
            var output = Data([point.y.isOdd ? 0x03 : 0x02])
            output.append(x)
            return output
        }
        var output = Data([0x04])
        output.append(x)
        output.append(point.y.serializedPadded(to: 32))
        return output
    }

    public static func sign(hash: Data, privateKey: Data) throws -> ECDSASignature {
        guard hash.count == 32 else { throw Secp256k1Error.invalidHashLength }
        let d = try privateScalar(privateKey)
        let z = BigUInt(hash) % curveOrder
        var nonce = RFC6979(privateKey: privateKey, hash: hash)

        for _ in 0..<128 {
            let kData = nonce.next()
            let k = BigUInt(kData)
            guard k > 0, k < curveOrder else { continue }
            guard let rPoint = scalarMultiply(generator, scalar: k) else { continue }
            let r = rPoint.x % curveOrder
            if r == 0 { continue }
            let kInverse = k.power(curveOrder - 2, modulus: curveOrder)
            var s = mod(kInverse * mod(z + mod(r * d, curveOrder), curveOrder), curveOrder)
            if s == 0 { continue }

            var recoveryID: UInt8 = (rPoint.x >= curveOrder ? 2 : 0) | (rPoint.y.isOdd ? 1 : 0)
            if s > curveOrder / 2 {
                s = curveOrder - s
                recoveryID ^= 1
            }
            let rData = r.serializedPadded(to: 32)
            let sData = s.serializedPadded(to: 32)
            return ECDSASignature(r: rData, s: sData, der: derEncode(r: rData, s: sData), recoveryID: recoveryID)
        }
        throw Secp256k1Error.signingFailed
    }

    /// Recover the compressed public key from a 65-byte compact signature (Bitcoin header + r + s).
    public static func recoverPublicKey(hash: Data, compactSignature: Data) throws -> Data {
        guard hash.count == 32, compactSignature.count == 65 else { throw Secp256k1Error.invalidHashLength }
        let header = compactSignature[0]
        guard header >= 27 else { throw Secp256k1Error.signingFailed }
        let recID = (header &- 27) & 0x03
        let r = BigUInt(compactSignature.subdata(in: 1..<33))
        let s = BigUInt(compactSignature.subdata(in: 33..<65))
        guard r > 0, r < curveOrder, s > 0, s < curveOrder else { throw Secp256k1Error.signingFailed }
        var x = r
        if recID & 2 != 0 { x += curveOrder }
        guard x < fieldPrime else { throw Secp256k1Error.invalidPublicKey }
        let prefix: UInt8 = (recID & 1) == 1 ? 0x03 : 0x02
        var encoded = Data([prefix])
        encoded.append(x.serializedPadded(to: 32))
        let rPoint = try parsePublicKey(encoded)
        let z = BigUInt(hash) % curveOrder
        let rInv = r.power(curveOrder - 2, modulus: curveOrder)
        guard let sR = scalarMultiply(rPoint, scalar: s) else { throw Secp256k1Error.signingFailed }
        let sum: PublicPoint
        if z == 0 {
            sum = sR
        } else {
            guard let zG = scalarMultiply(generator, scalar: z) else { throw Secp256k1Error.signingFailed }
            let negZG = PublicPoint(uncheckedX: zG.x, y: (fieldPrime - zG.y) % fieldPrime)
            guard let added = addAffine(sR, negZG) else { throw Secp256k1Error.signingFailed }
            sum = added
        }
        guard let q = scalarMultiply(sum, scalar: rInv) else { throw Secp256k1Error.signingFailed }
        return serialize(q, compressed: true)
    }

    public static func verify(hash: Data, derSignature: Data, publicKey: Data) -> Bool {
        guard hash.count == 32,
              let (r, s) = derDecode(derSignature),
              r > 0, r < curveOrder, s > 0, s < curveOrder,
              let q = try? parsePublicKey(publicKey) else { return false }
        let z = BigUInt(hash) % curveOrder
        let w = s.power(curveOrder - 2, modulus: curveOrder)
        let u1 = mod(z * w, curveOrder)
        let u2 = mod(r * w, curveOrder)
        guard let p1 = scalarMultiply(generator, scalar: u1),
              let p2 = scalarMultiply(q, scalar: u2),
              let point = addAffine(p1, p2) else { return false }
        return point.x % curveOrder == r
    }

    public static func addPrivateKeys(_ lhs: Data, _ rhs: Data) throws -> Data {
        let a = try privateScalar(lhs)
        let b = try privateScalar(rhs)
        let sum = mod(a + b, curveOrder)
        guard sum != 0 else { throw Secp256k1Error.invalidPrivateKey }
        return sum.serializedPadded(to: 32)
    }

    /// ngu `keypair.ecdh_multiply`: SHA-256 of the uncompressed XY of `priv * other`.
    public static func ecdhHash(privateKey: Data, otherPublicKey: Data) throws -> Data {
        let other = try parsePublicKey(otherPublicKey)
        let scalar = try privateScalar(privateKey)
        guard let point = scalarMultiply(other, scalar: scalar) else { throw Secp256k1Error.invalidPublicKey }
        var xy = point.x.serializedPadded(to: 32)
        xy.append(point.y.serializedPadded(to: 32))
        return SHA2.sha256(xy)
    }

    public static func tweakAdd(publicKey: Data, tweak: Data, compressed: Bool = true) throws -> Data {
        let q = try parsePublicKey(publicKey)
        let scalar = BigUInt(tweak)
        guard scalar < curveOrder, let tweakPoint = scalarMultiply(generator, scalar: scalar),
              let result = addAffine(q, tweakPoint) else { throw Secp256k1Error.invalidPrivateKey }
        return serialize(result, compressed: compressed)
    }

    public static func xOnlyPublicKey(fromPrivateKey privateKey: Data) throws -> Data {
        try publicPoint(fromPrivateKey: privateKey).x.serializedPadded(to: 32)
    }

    public static func taprootOutputKey(internalKey: Data, merkleRoot: Data? = nil) throws -> Data {
        guard internalKey.count == 32 else { throw Secp256k1Error.invalidPublicKey }
        var compressed = Data([0x02])
        compressed.append(internalKey)
        let internalPoint = try parsePublicKey(compressed)
        var tweakInput = internalKey
        if let merkleRoot {
            guard merkleRoot.count == 32 else { throw Secp256k1Error.invalidHashLength }
            tweakInput.append(merkleRoot)
        }
        let tweakData = BitcoinHash.taggedHash(tag: "TapTweak", message: tweakInput)
        let tweak = BigUInt(tweakData)
        guard tweak < curveOrder else { throw Secp256k1Error.invalidPrivateKey }
        if tweak == 0 { return internalKey }
        guard let tweakPoint = scalarMultiply(generator, scalar: tweak),
              let output = addAffine(internalPoint, tweakPoint) else { throw Secp256k1Error.invalidPublicKey }
        return output.x.serializedPadded(to: 32)
    }

    private static func privateScalar(_ data: Data) throws -> BigUInt {
        guard privateKeyIsValid(data) else { throw Secp256k1Error.invalidPrivateKey }
        return BigUInt(data)
    }

    private static func scalarMultiply(_ point: PublicPoint, scalar: BigUInt) -> PublicPoint? {
        guard scalar > 0 else { return nil }
        var result = JacobianPoint.infinity
        var addend = JacobianPoint(x: point.x, y: point.y, z: 1)
        var k = scalar
        while k > 0 {
            if k.isOdd { result = add(result, addend) }
            addend = double(addend)
            k >>= 1
        }
        return toAffine(result)
    }

    private static func double(_ p: JacobianPoint) -> JacobianPoint {
        if p.isInfinity || p.y == 0 { return .infinity }
        let yy = mul(p.y, p.y)
        let yyyy = mul(yy, yy)
        let xx = mul(p.x, p.x)
        let s = mul(4, mul(p.x, yy))
        let m = mul(3, xx)
        let x3 = sub(mul(m, m), mul(2, s))
        let y3 = sub(mul(m, sub(s, x3)), mul(8, yyyy))
        let z3 = mul(2, mul(p.y, p.z))
        return JacobianPoint(x: x3, y: y3, z: z3)
    }

    private static func add(_ p: JacobianPoint, _ q: JacobianPoint) -> JacobianPoint {
        if p.isInfinity { return q }
        if q.isInfinity { return p }

        let z1z1 = mul(p.z, p.z)
        let z2z2 = mul(q.z, q.z)
        let u1 = mul(p.x, z2z2)
        let u2 = mul(q.x, z1z1)
        let s1 = mul(p.y, mul(q.z, z2z2))
        let s2 = mul(q.y, mul(p.z, z1z1))
        if u1 == u2 {
            return s1 == s2 ? double(p) : .infinity
        }
        let h = sub(u2, u1)
        let i = mul(4, mul(h, h))
        let j = mul(h, i)
        let r = mul(2, sub(s2, s1))
        let v = mul(u1, i)
        let x3 = sub(sub(mul(r, r), j), mul(2, v))
        let y3 = sub(mul(r, sub(v, x3)), mul(2, mul(s1, j)))
        let zSum = addMod(p.z, q.z)
        let z3 = mul(sub(sub(mul(zSum, zSum), z1z1), z2z2), h)
        return JacobianPoint(x: x3, y: y3, z: z3)
    }

    private static func toAffine(_ p: JacobianPoint) -> PublicPoint? {
        guard !p.isInfinity else { return nil }
        let zInverse = p.z.power(fieldPrime - 2, modulus: fieldPrime)
        let z2 = mul(zInverse, zInverse)
        let x = mul(p.x, z2)
        let y = mul(p.y, mul(z2, zInverse))
        return PublicPoint(uncheckedX: x, y: y)
    }

    private static func addAffine(_ p: PublicPoint, _ q: PublicPoint) -> PublicPoint? {
        if p.x == q.x {
            if p.y != q.y || p.y == 0 { return nil }
            let lambda = mul(mul(3, mul(p.x, p.x)), modInverse(mul(2, p.y)))
            let x3 = sub(mul(lambda, lambda), mul(2, p.x))
            let y3 = sub(mul(lambda, sub(p.x, x3)), p.y)
            return PublicPoint(uncheckedX: x3, y: y3)
        }
        let lambda = mul(sub(q.y, p.y), modInverse(sub(q.x, p.x)))
        let x3 = sub(sub(mul(lambda, lambda), p.x), q.x)
        let y3 = sub(mul(lambda, sub(p.x, x3)), p.y)
        return PublicPoint(uncheckedX: x3, y: y3)
    }

    private static func modInverse(_ value: BigUInt) -> BigUInt {
        value.power(fieldPrime - 2, modulus: fieldPrime)
    }

    @inline(__always) private static func mul(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        mod(a * b, fieldPrime)
    }

    @inline(__always) private static func sub(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        if a >= b { return a - b }
        return fieldPrime - ((b - a) % fieldPrime)
    }

    @inline(__always) private static func addMod(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        mod(a + b, fieldPrime)
    }

    @inline(__always) private static func mod(_ value: BigUInt, _ modulus: BigUInt) -> BigUInt {
        value % modulus
    }

    private static func derEncode(r: Data, s: Data) -> Data {
        func integer(_ value: Data) -> Data {
            var bytes = Array(value.drop { $0 == 0 })
            if bytes.isEmpty { bytes = [0] }
            if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
            return Data([0x02, UInt8(bytes.count)] + bytes)
        }
        let rEncoded = integer(r)
        let sEncoded = integer(s)
        var output = Data([0x30, UInt8(rEncoded.count + sEncoded.count)])
        output.append(rEncoded)
        output.append(sEncoded)
        return output
    }

    private static func derDecode(_ signature: Data) -> (BigUInt, BigUInt)? {
        var reader = ByteReader(signature)
        guard (try? reader.readByte()) == 0x30,
              let total = try? reader.readByte(), Int(total) == reader.remaining,
              (try? reader.readByte()) == 0x02,
              let rLength = try? reader.readByte(), let rData = try? reader.read(Int(rLength)),
              (try? reader.readByte()) == 0x02,
              let sLength = try? reader.readByte(), let sData = try? reader.read(Int(sLength)),
              reader.isAtEnd, !rData.isEmpty, !sData.isEmpty else { return nil }
        return (BigUInt(rData), BigUInt(sData))
    }
}

private struct RFC6979 {
    private var k = Data(repeating: 0, count: 32)
    private var v = Data(repeating: 1, count: 32)

    init(privateKey: Data, hash: Data) {
        let h1 = (BigUInt(hash) % Secp256k1.curveOrder).serializedPadded(to: 32)
        var input = Data()
        input.append(v)
        input.append(0x00)
        input.append(privateKey)
        input.append(h1)
        k = HMAC.sha256(key: k, message: input)
        v = HMAC.sha256(key: k, message: v)
        input = Data()
        input.append(v)
        input.append(0x01)
        input.append(privateKey)
        input.append(h1)
        k = HMAC.sha256(key: k, message: input)
        v = HMAC.sha256(key: k, message: v)
    }

    mutating func next() -> Data {
        while true {
            v = HMAC.sha256(key: k, message: v)
            let candidate = BigUInt(v)
            if candidate > 0 && candidate < Secp256k1.curveOrder { return v }
            var input = Data()
            input.append(v)
            input.append(0x00)
            k = HMAC.sha256(key: k, message: input)
            v = HMAC.sha256(key: k, message: v)
        }
    }
}

extension BigUInt {
    fileprivate var isOdd: Bool { self & 1 == 1 }

    func serializedPadded(to count: Int) -> Data {
        let bytes = serialize()
        precondition(bytes.count <= count)
        if bytes.count == count { return bytes }
        return Data(repeating: 0, count: count - bytes.count) + bytes
    }
}

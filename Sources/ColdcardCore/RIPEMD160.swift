import Foundation

public enum RIPEMD160 {
    private static let r1: [Int] = [
        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,
        3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2,
        4,0,5,9,7,12,2,10,14,1,3,8,11,6,15,13
    ]
    private static let r2: [Int] = [
        5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,
        15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14,
        12,15,10,4,1,5,8,7,6,2,13,14,0,3,9,11
    ]
    private static let s1: [UInt32] = [
        11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,
        11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12,
        9,15,5,11,6,8,13,12,5,12,13,14,11,8,5,6
    ]
    private static let s2: [UInt32] = [
        8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,
        9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,
        8,5,12,9,12,5,14,6,8,13,6,5,15,13,11,11
    ]

    private static func f(_ round: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch round {
        case 0: return x ^ y ^ z
        case 1: return (x & y) | (~x & z)
        case 2: return (x | ~y) ^ z
        case 3: return (x & z) | (y & ~z)
        default: return x ^ (y | ~z)
        }
    }

    private static let k1: [UInt32] = [0x00000000,0x5a827999,0x6ed9eba1,0x8f1bbcdc,0xa953fd4e]
    private static let k2: [UInt32] = [0x50a28be6,0x5c4dd124,0x6d703ef3,0x7a6d76e9,0x00000000]

    public static func hash(_ data: Data) -> Data {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 0, to: 64, by: 8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }
        var h0: UInt32 = 0x67452301, h1: UInt32 = 0xefcdab89, h2: UInt32 = 0x98badcfe
        var h3: UInt32 = 0x10325476, h4: UInt32 = 0xc3d2e1f0
        for chunk in stride(from: 0, to: message.count, by: 64) {
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let j = chunk + i * 4
                x[i] = UInt32(message[j]) | (UInt32(message[j+1]) << 8) | (UInt32(message[j+2]) << 16) | (UInt32(message[j+3]) << 24)
            }
            var a1=h0,b1=h1,c1=h2,d1=h3,e1=h4
            var a2=h0,b2=h1,c2=h2,d2=h3,e2=h4
            for j in 0..<80 {
                let round = j / 16
                var t = rotateLeft(a1 &+ f(round,b1,c1,d1) &+ x[r1[j]] &+ k1[round], by: s1[j]) &+ e1
                a1=e1;e1=d1;d1=rotateLeft(c1,by:10);c1=b1;b1=t
                t = rotateLeft(a2 &+ f(4-round,b2,c2,d2) &+ x[r2[j]] &+ k2[round], by: s2[j]) &+ e2
                a2=e2;e2=d2;d2=rotateLeft(c2,by:10);c2=b2;b2=t
            }
            let t = h1 &+ c1 &+ d2
            h1 = h2 &+ d1 &+ e2
            h2 = h3 &+ e1 &+ a2
            h3 = h4 &+ a1 &+ b2
            h4 = h0 &+ b1 &+ c2
            h0 = t
        }
        var out = Data()
        for value in [h0,h1,h2,h3,h4] {
            out.append(UInt8(truncatingIfNeeded:value)); out.append(UInt8(truncatingIfNeeded:value >> 8))
            out.append(UInt8(truncatingIfNeeded:value >> 16)); out.append(UInt8(truncatingIfNeeded:value >> 24))
        }
        return out
    }
}

public enum BitcoinHash {
    public static func hash160(_ data: Data) -> Data { RIPEMD160.hash(SHA2.sha256(data)) }
    public static func taggedHash(tag: String, message: Data) -> Data {
        let tagHash = SHA2.sha256(Data(tag.utf8))
        return SHA2.sha256(tagHash + tagHash + message)
    }
}

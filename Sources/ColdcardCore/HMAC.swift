import Foundation

public enum HMAC {
    public static func sha1(key: Data, message: Data) -> Data {
        compute(key: key, message: message, blockSize: 64, hash: SHA1.hash)
    }

    public static func sha256(key: Data, message: Data) -> Data {
        compute(key: key, message: message, blockSize: 64, hash: SHA2.sha256)
    }

    public static func sha512(key: Data, message: Data) -> Data {
        compute(key: key, message: message, blockSize: 128, hash: SHA2.sha512)
    }

    private static func compute(key: Data, message: Data, blockSize: Int, hash: (Data) -> Data) -> Data {
        var normalized = key.count > blockSize ? hash(key) : key
        if normalized.count < blockSize { normalized.append(contentsOf: repeatElement(0, count: blockSize - normalized.count)) }
        let outer = Data(normalized.map { $0 ^ 0x5c })
        let inner = Data(normalized.map { $0 ^ 0x36 })
        return hash(outer + hash(inner + message))
    }
}

public enum PBKDF2 {
    public static func hmacSHA512(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        precondition(iterations > 0 && keyLength >= 0)
        let digestLength = 64
        let blocks = (keyLength + digestLength - 1) / digestLength
        var result = Data()
        result.reserveCapacity(blocks * digestLength)
        for block in 1...blocks {
            var counter = Data(); counter.appendUInt32BE(UInt32(block))
            var u = HMAC.sha512(key: password, message: salt + counter)
            var t = u
            if iterations > 1 {
                for _ in 2...iterations {
                    u = HMAC.sha512(key: password, message: u)
                    for i in 0..<digestLength { t[i] ^= u[i] }
                }
            }
            result.append(t)
        }
        return result.prefix(keyLength)
    }
}

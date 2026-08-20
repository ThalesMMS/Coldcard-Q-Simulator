import Foundation

/// AES-256-ECB block cipher, AES-256-CBC, and AES-256-CTR with a zero 128-bit counter.
/// Firmware `aes256ctr.new(key)` / `ngu.aes.CBC` / `pyaes.AESModeOfOperationCTR(key, Counter(0))`.
public enum AES256CTR {
    public static let blockSize = 16
    public static let keySize = 32

    public static func encryptBlock(key: Data, plaintext: Data) -> Data {
        precondition(key.count == keySize && plaintext.count == blockSize)
        return Data(cipher(block: [UInt8](plaintext), roundKeys: expand(key: [UInt8](key)), inverse: false))
    }

    public static func decryptBlock(key: Data, ciphertext: Data) -> Data {
        precondition(key.count == keySize && ciphertext.count == blockSize)
        return Data(cipher(block: [UInt8](ciphertext), roundKeys: expand(key: [UInt8](key)), inverse: true))
    }

    /// AES-256-CBC (firmware `ngu.aes.CBC`). `data` must be a multiple of 16 bytes.
    public static func cryptCBC(encrypt: Bool, key: Data, iv: Data, data: Data) -> Data {
        precondition(key.count == keySize && iv.count == blockSize && data.count % blockSize == 0)
        let roundKeys = expand(key: [UInt8](key))
        var prev = [UInt8](iv)
        var output = [UInt8](repeating: 0, count: data.count)
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let block = Array(bytes[offset..<(offset + blockSize)])
            let produced: [UInt8]
            if encrypt {
                var xored = [UInt8](repeating: 0, count: blockSize)
                for index in 0..<blockSize { xored[index] = block[index] ^ prev[index] }
                produced = cipher(block: xored, roundKeys: roundKeys, inverse: false)
                prev = produced
            } else {
                let plain = cipher(block: block, roundKeys: roundKeys, inverse: true)
                var xored = [UInt8](repeating: 0, count: blockSize)
                for index in 0..<blockSize { xored[index] = plain[index] ^ prev[index] }
                produced = xored
                prev = block
            }
            for index in 0..<blockSize { output[offset + index] = produced[index] }
            offset += blockSize
        }
        return Data(output)
    }

    /// AES-256-CTR, initial counter all zeros (firmware / pyaes `Counter(0)`).
    public static func crypt(key: Data, data: Data) -> Data {
        precondition(key.count == keySize)
        let roundKeys = expand(key: [UInt8](key))
        var counter = [UInt8](repeating: 0, count: blockSize)
        var output = [UInt8](repeating: 0, count: data.count)
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let stream = cipher(block: counter, roundKeys: roundKeys, inverse: false)
            let take = min(blockSize, bytes.count - offset)
            for index in 0..<take {
                output[offset + index] = bytes[offset + index] ^ stream[index]
            }
            increment(&counter)
            offset += take
        }
        return Data(output)
    }

    private static func increment(_ counter: inout [UInt8]) {
        var index = blockSize - 1
        while index >= 0 {
            counter[index] &+= 1
            if counter[index] != 0 { return }
            index -= 1
        }
    }

    private static let sbox: [UInt8] = [
        0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
        0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
        0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
        0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
        0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
        0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
        0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
        0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
        0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
        0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
        0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
        0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
        0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
        0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
        0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
        0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
    ]

    private static let invSbox: [UInt8] = [
        0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
        0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
        0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
        0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
        0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
        0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
        0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
        0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
        0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
        0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
        0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
        0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
        0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
        0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
        0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
        0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d
    ]

    private static let rcon: [UInt8] = [0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]

    private static func expand(key: [UInt8]) -> [UInt8] {
        var words = key
        words.reserveCapacity(240)
        var index = 32
        var rconIndex = 1
        while words.count < 240 {
            var temp = Array(words[(index - 4)..<index])
            if index % 32 == 0 {
                temp = [sbox[Int(temp[1])], sbox[Int(temp[2])], sbox[Int(temp[3])], sbox[Int(temp[0])]]
                temp[0] ^= rcon[rconIndex]
                rconIndex += 1
            } else if index % 32 == 16 {
                temp = temp.map { sbox[Int($0)] }
            }
            for byte in 0..<4 {
                words.append(words[index - 32 + byte] ^ temp[byte])
            }
            index += 4
        }
        return words
    }

    private static func cipher(block: [UInt8], roundKeys: [UInt8], inverse: Bool) -> [UInt8] {
        var state = block
        if inverse {
            addRoundKey(&state, roundKeys, round: 14)
            for round in stride(from: 13, through: 1, by: -1) {
                invShiftRows(&state)
                invSubBytes(&state)
                addRoundKey(&state, roundKeys, round: round)
                invMixColumns(&state)
            }
            invShiftRows(&state)
            invSubBytes(&state)
            addRoundKey(&state, roundKeys, round: 0)
        } else {
            addRoundKey(&state, roundKeys, round: 0)
            for round in 1...13 {
                subBytes(&state)
                shiftRows(&state)
                mixColumns(&state)
                addRoundKey(&state, roundKeys, round: round)
            }
            subBytes(&state)
            shiftRows(&state)
            addRoundKey(&state, roundKeys, round: 14)
        }
        return state
    }

    private static func addRoundKey(_ state: inout [UInt8], _ roundKeys: [UInt8], round: Int) {
        let offset = round * 16
        for index in 0..<16 { state[index] ^= roundKeys[offset + index] }
    }

    private static func subBytes(_ state: inout [UInt8]) {
        for index in 0..<16 { state[index] = sbox[Int(state[index])] }
    }

    private static func invSubBytes(_ state: inout [UInt8]) {
        for index in 0..<16 { state[index] = invSbox[Int(state[index])] }
    }

    private static func shiftRows(_ state: inout [UInt8]) {
        state = [
            state[0], state[5], state[10], state[15],
            state[4], state[9], state[14], state[3],
            state[8], state[13], state[2], state[7],
            state[12], state[1], state[6], state[11]
        ]
    }

    private static func invShiftRows(_ state: inout [UInt8]) {
        state = [
            state[0], state[13], state[10], state[7],
            state[4], state[1], state[14], state[11],
            state[8], state[5], state[2], state[15],
            state[12], state[9], state[6], state[3]
        ]
    }

    private static func mixColumns(_ state: inout [UInt8]) {
        for column in 0..<4 {
            let i = column * 4
            let a = state[i], b = state[i + 1], c = state[i + 2], d = state[i + 3]
            state[i]     = gmul(a, 2) ^ gmul(b, 3) ^ c ^ d
            state[i + 1] = a ^ gmul(b, 2) ^ gmul(c, 3) ^ d
            state[i + 2] = a ^ b ^ gmul(c, 2) ^ gmul(d, 3)
            state[i + 3] = gmul(a, 3) ^ b ^ c ^ gmul(d, 2)
        }
    }

    private static func invMixColumns(_ state: inout [UInt8]) {
        for column in 0..<4 {
            let i = column * 4
            let a = state[i], b = state[i + 1], c = state[i + 2], d = state[i + 3]
            state[i]     = gmul(a, 14) ^ gmul(b, 11) ^ gmul(c, 13) ^ gmul(d, 9)
            state[i + 1] = gmul(a, 9) ^ gmul(b, 14) ^ gmul(c, 11) ^ gmul(d, 13)
            state[i + 2] = gmul(a, 13) ^ gmul(b, 9) ^ gmul(c, 14) ^ gmul(d, 11)
            state[i + 3] = gmul(a, 11) ^ gmul(b, 13) ^ gmul(c, 9) ^ gmul(d, 14)
        }
    }

    private static func gmul(_ value: UInt8, _ factor: UInt8) -> UInt8 {
        var a = value
        var b = factor
        var product: UInt8 = 0
        for _ in 0..<8 {
            if b & 1 != 0 { product ^= a }
            let hi = a & 0x80
            a = a << 1
            if hi != 0 { a ^= 0x1b }
            b >>= 1
        }
        return product
    }
}

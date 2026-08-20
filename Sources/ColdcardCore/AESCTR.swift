import Foundation

public enum AESCTRError: Error, Equatable, Sendable {
    case invalidKeyLength
    case invalidNonceLength
}

/// AES-CTR with a 128-bit big-endian counter, matching cifra `cf_ctr` / TAPSIGNER backups.
public enum AESCTR {
    public static func crypt(key: Data, nonce: Data, data: Data) throws -> Data {
        guard key.count == 16 else { throw AESCTRError.invalidKeyLength }
        guard nonce.count == 16 else { throw AESCTRError.invalidNonceLength }
        var counter = [UInt8](nonce)
        let roundKeys = expandKey([UInt8](key))
        var output = [UInt8](repeating: 0, count: data.count)
        let input = [UInt8](data)
        var offset = 0
        while offset < input.count {
            let stream = encryptBlock(roundKeys, counter)
            let count = min(16, input.count - offset)
            for index in 0..<count {
                output[offset + index] = input[offset + index] ^ stream[index]
            }
            incrementBE(&counter)
            offset += count
        }
        return Data(output)
    }

    private static let sBox: [UInt8] = [
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

    private static let rcon: [UInt8] = [0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]

    private static func expandKey(_ key: [UInt8]) -> [UInt32] {
        var words = [UInt32](repeating: 0, count: 44)
        for index in 0..<4 {
            words[index] = word(key[index * 4], key[index * 4 + 1], key[index * 4 + 2], key[index * 4 + 3])
        }
        for index in 4..<44 {
            var temp = words[index - 1]
            if index % 4 == 0 {
                temp = subWord(rotateWord(temp)) ^ word(rcon[index / 4], 0, 0, 0)
            }
            words[index] = words[index - 4] ^ temp
        }
        return words
    }

    private static func encryptBlock(_ roundKeys: [UInt32], _ input: [UInt8]) -> [UInt8] {
        var state = input
        addRoundKey(&state, roundKeys, 0)
        for round in 1..<10 {
            subBytes(&state)
            shiftRows(&state)
            mixColumns(&state)
            addRoundKey(&state, roundKeys, round)
        }
        subBytes(&state)
        shiftRows(&state)
        addRoundKey(&state, roundKeys, 10)
        return state
    }

    private static func addRoundKey(_ state: inout [UInt8], _ roundKeys: [UInt32], _ round: Int) {
        for column in 0..<4 {
            let word = roundKeys[round * 4 + column]
            state[column * 4] ^= UInt8((word >> 24) & 0xff)
            state[column * 4 + 1] ^= UInt8((word >> 16) & 0xff)
            state[column * 4 + 2] ^= UInt8((word >> 8) & 0xff)
            state[column * 4 + 3] ^= UInt8(word & 0xff)
        }
    }

    private static func subBytes(_ state: inout [UInt8]) {
        for index in state.indices { state[index] = sBox[Int(state[index])] }
    }

    private static func shiftRows(_ state: inout [UInt8]) {
        let copy = state
        state[1] = copy[5]; state[5] = copy[9]; state[9] = copy[13]; state[13] = copy[1]
        state[2] = copy[10]; state[6] = copy[14]; state[10] = copy[2]; state[14] = copy[6]
        state[3] = copy[15]; state[7] = copy[3]; state[11] = copy[7]; state[15] = copy[11]
    }

    private static func mixColumns(_ state: inout [UInt8]) {
        for column in 0..<4 {
            let i = column * 4
            let a = state[i], b = state[i + 1], c = state[i + 2], d = state[i + 3]
            state[i] = xtime(a) ^ xtime(b) ^ b ^ c ^ d
            state[i + 1] = a ^ xtime(b) ^ xtime(c) ^ c ^ d
            state[i + 2] = a ^ b ^ xtime(c) ^ xtime(d) ^ d
            state[i + 3] = xtime(a) ^ a ^ b ^ c ^ xtime(d)
        }
    }

    private static func xtime(_ value: UInt8) -> UInt8 {
        let shifted = value << 1
        return (value & 0x80) != 0 ? shifted ^ 0x1b : shifted
    }

    private static func incrementBE(_ counter: inout [UInt8]) {
        for index in (0..<counter.count).reversed() {
            counter[index] &+= 1
            if counter[index] != 0 { return }
        }
    }

    private static func word(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
        (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(c) << 8) | UInt32(d)
    }

    private static func rotateWord(_ value: UInt32) -> UInt32 {
        (value << 8) | (value >> 24)
    }

    private static func subWord(_ value: UInt32) -> UInt32 {
        word(sBox[Int(value >> 24)], sBox[Int((value >> 16) & 0xff)],
             sBox[Int((value >> 8) & 0xff)], sBox[Int(value & 0xff)])
    }
}

import Foundation

// Adapted in part from Pieter Wuille's MIT-licensed Bech32/Bech32m reference.
// See ThirdParty/Bech32-LICENSE.md and Docs/PROVENANCE.md.

public enum Bech32Error: Error, Equatable, Sendable {
    case mixedCase
    case invalidCharacter
    case invalidChecksum
    case invalidHRP
    case invalidData
    case invalidWitnessVersion
    case invalidWitnessProgram
}

public enum Bech32Variant: Sendable { case bech32, bech32m }

public enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let reverse: [Character: UInt8] = Dictionary(uniqueKeysWithValues: charset.enumerated().map { ($1, UInt8($0)) })

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3]
        var chk: UInt32 = 1
        for value in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(value)
            for i in 0..<5 where ((top >> UInt32(i)) & 1) != 0 { chk ^= generators[i] }
        }
        return chk
    }

    private static func expandHRP(_ hrp: String) -> [UInt8] {
        Array(hrp.utf8.map { $0 >> 5 }) + [0] + Array(hrp.utf8.map { $0 & 31 })
    }

    private static func checksum(hrp: String, data: [UInt8], variant: Bech32Variant) -> [UInt8] {
        let constant: UInt32 = variant == .bech32 ? 1 : 0x2bc830a3
        let mod = polymod(expandHRP(hrp) + data + [UInt8](repeating: 0, count: 6)) ^ constant
        return (0..<6).map { UInt8((mod >> UInt32(5 * (5 - $0))) & 31) }
    }

    public static func encode(hrp: String, data: [UInt8], variant: Bech32Variant) throws -> String {
        guard !hrp.isEmpty, hrp.utf8.allSatisfy({ 33...126 ~= $0 }), hrp == hrp.lowercased() else { throw Bech32Error.invalidHRP }
        guard data.allSatisfy({ $0 < 32 }) else { throw Bech32Error.invalidData }
        let combined = data + checksum(hrp: hrp, data: data, variant: variant)
        let result = hrp + "1" + String(combined.map { charset[Int($0)] })
        guard result.count <= 90 else { throw Bech32Error.invalidData }
        return result
    }

    public static func decode(_ string: String) throws -> (hrp: String, data: [UInt8], variant: Bech32Variant) {
        guard string == string.lowercased() || string == string.uppercased() else { throw Bech32Error.mixedCase }
        let lower = string.lowercased()
        guard let separator = lower.lastIndex(of: "1"), separator != lower.startIndex else { throw Bech32Error.invalidData }
        let hrp = String(lower[..<separator])
        let payloadStart = lower.index(after: separator)
        let payload = lower[payloadStart...]
        guard payload.count >= 6, lower.count <= 90 else { throw Bech32Error.invalidData }
        var values: [UInt8] = []
        for char in payload {
            guard let value = reverse[char] else { throw Bech32Error.invalidCharacter }
            values.append(value)
        }
        let check = polymod(expandHRP(hrp) + values)
        let variant: Bech32Variant
        if check == 1 { variant = .bech32 }
        else if check == 0x2bc830a3 { variant = .bech32m }
        else { throw Bech32Error.invalidChecksum }
        return (hrp, Array(values.dropLast(6)), variant)
    }

    public static func convertBits(_ input: [UInt8], from: Int, to: Int, pad: Bool) throws -> [UInt8] {
        var accumulator = 0
        var bits = 0
        let maxValue = (1 << to) - 1
        let maxAccumulator = (1 << (from + to - 1)) - 1
        var output: [UInt8] = []
        for value in input {
            guard Int(value) >> from == 0 else { throw Bech32Error.invalidData }
            accumulator = ((accumulator << from) | Int(value)) & maxAccumulator
            bits += from
            while bits >= to {
                bits -= to
                output.append(UInt8((accumulator >> bits) & maxValue))
            }
        }
        if pad {
            if bits > 0 { output.append(UInt8((accumulator << (to - bits)) & maxValue)) }
        } else if bits >= from || ((accumulator << (to - bits)) & maxValue) != 0 {
            throw Bech32Error.invalidData
        }
        return output
    }

    public static func encodeSegwit(hrp: String, version: UInt8, program: Data) throws -> String {
        guard version <= 16 else { throw Bech32Error.invalidWitnessVersion }
        guard (2...40).contains(program.count), version != 0 || program.count == 20 || program.count == 32 else { throw Bech32Error.invalidWitnessProgram }
        let converted = try convertBits(Array(program), from: 8, to: 5, pad: true)
        return try encode(hrp: hrp, data: [version] + converted, variant: version == 0 ? .bech32 : .bech32m)
    }

    public static func decodeSegwit(_ address: String) throws -> (hrp: String, version: UInt8, program: Data) {
        let decoded = try decode(address)
        guard let version = decoded.data.first, version <= 16 else { throw Bech32Error.invalidWitnessVersion }
        guard (version == 0 && decoded.variant == .bech32) || (version != 0 && decoded.variant == .bech32m) else { throw Bech32Error.invalidChecksum }
        let bytes = try convertBits(Array(decoded.data.dropFirst()), from: 5, to: 8, pad: false)
        let program = Data(bytes)
        guard (2...40).contains(program.count), version != 0 || program.count == 20 || program.count == 32 else { throw Bech32Error.invalidWitnessProgram }
        return (decoded.hrp, version, program)
    }
}

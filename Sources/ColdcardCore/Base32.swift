import Foundation

public enum Base32Error: Error, Equatable, Sendable {
    case invalidCharacter(Character)
    case invalidPadding
}

/// RFC 4648 Base32 without mandatory padding, as used by BBQr.
public enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let reverse: [Character: UInt8] = Dictionary(
        uniqueKeysWithValues: alphabet.enumerated().map { ($1, UInt8($0)) }
    )

    public static func encode(_ data: Data, padded: Bool = false) -> String {
        guard !data.isEmpty else { return "" }
        var output = ""
        output.reserveCapacity((data.count * 8 + 4) / 5)
        var buffer = 0
        var bitCount = 0

        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                output.append(alphabet[(buffer >> bitCount) & 0x1f])
            }
            if bitCount == 0 { buffer = 0 }
            else { buffer &= (1 << bitCount) - 1 }
        }
        if bitCount > 0 {
            output.append(alphabet[(buffer << (5 - bitCount)) & 0x1f])
        }
        if padded {
            while !output.count.isMultiple(of: 8) { output.append("=") }
        }
        return output
    }

    public static func decode(_ string: String) throws -> Data {
        let compact = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let unpadded = compact.prefix { $0 != "=" }
        guard compact.dropFirst(unpadded.count).allSatisfy({ $0 == "=" }) else {
            throw Base32Error.invalidPadding
        }

        var output = Data()
        output.reserveCapacity(unpadded.count * 5 / 8)
        var buffer = 0
        var bitCount = 0
        for character in unpadded {
            guard let value = reverse[character] else { throw Base32Error.invalidCharacter(character) }
            buffer = (buffer << 5) | Int(value)
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                output.append(UInt8((buffer >> bitCount) & 0xff))
            }
            if bitCount == 0 { buffer = 0 }
            else { buffer &= (1 << bitCount) - 1 }
        }
        guard bitCount == 0 || buffer == 0 else { throw Base32Error.invalidPadding }
        return output
    }
}

extension Base32Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCharacter(let character): "Invalid Base32 character: \(character)."
        case .invalidPadding: "Invalid Base32 padding."
        }
    }
}

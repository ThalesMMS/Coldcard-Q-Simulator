import Foundation
#if SWIFT_PACKAGE
import BigInt
#endif

// Independent Swift expression of standardized Base58Check behavior. The
// CC BY-NC-ND testing/base58.py file found in the supplied firmware archive is
// intentionally not distributed or required by this implementation.

public enum Base58Error: Error, Equatable, Sendable {
    case invalidCharacter(Character)
    case invalidChecksum
    case payloadTooShort
}

public enum Base58 {
    public static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let lookup: [Character: Int] = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })

    public static func encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var number = BigUInt(data)
        let radix = BigUInt(58)
        var encoded: [Character] = []
        while number > 0 {
            let division = number.quotientAndRemainder(dividingBy: radix)
            encoded.append(alphabet[Int(division.remainder)])
            number = division.quotient
        }
        let leading = data.prefix { $0 == 0 }.count
        encoded.append(contentsOf: repeatElement(Character("1"), count: leading))
        return String(encoded.reversed())
    }

    public static func decode(_ string: String) throws -> Data {
        guard !string.isEmpty else { return Data() }
        var number = BigUInt(0)
        for character in string {
            guard let digit = lookup[character] else { throw Base58Error.invalidCharacter(character) }
            number = number * 58 + BigUInt(digit)
        }
        var bytes = number.serialize()
        let leading = string.prefix { $0 == "1" }.count
        if leading > 0 { bytes = Data(repeating: 0, count: leading) + bytes }
        return bytes
    }

    public static func checkEncode(version: Data, payload: Data) -> String {
        let body = version + payload
        return encode(body + SHA2.doubleSHA256(body).prefix(4))
    }

    public static func checkDecode(_ string: String) throws -> Data {
        let decoded = try decode(string)
        guard decoded.count >= 4 else { throw Base58Error.payloadTooShort }
        let body = decoded.dropLast(4)
        guard Data(decoded.suffix(4)) == SHA2.doubleSHA256(Data(body)).prefix(4) else {
            throw Base58Error.invalidChecksum
        }
        return Data(body)
    }
}

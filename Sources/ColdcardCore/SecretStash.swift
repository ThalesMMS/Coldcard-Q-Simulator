import Foundation

public enum SecretStashError: Error, Equatable, Sendable {
    case empty
    case unknownMarker(UInt8)
    case invalidLength
}

public enum SecretStashKind: Equatable, Sendable {
    case words(entropy: Data)
    case xprv(chainCode: Data, privateKey: Data)
    case masterSecret(Data)
}

/// Firmware `stash.SecretStash` 72-byte encoding (`stash.py`).
public enum SecretStash {
    public static let encodedLength = 72

    public static func encode(entropy: Data) -> Data {
        precondition([16, 24, 32].contains(entropy.count))
        var nv = Data(count: encodedLength)
        nv[0] = 0x80 | UInt8((entropy.count / 8) - 2)
        nv.replaceSubrange(1..<(1 + entropy.count), with: entropy)
        return trimTrailingZeros(nv)
    }

    public static func encode(chainCode: Data, privateKey: Data) -> Data {
        precondition(chainCode.count == 32 && privateKey.count == 32)
        var nv = Data(count: encodedLength)
        nv[0] = 0x01
        nv.replaceSubrange(1..<33, with: chainCode)
        nv.replaceSubrange(33..<65, with: privateKey)
        return trimTrailingZeros(nv)
    }

    public static func decode(_ data: Data) throws -> SecretStashKind {
        var raw = data
        if raw.count < encodedLength {
            raw.append(Data(count: encodedLength - raw.count))
        }
        guard !raw.isEmpty else { throw SecretStashError.empty }
        let marker = raw[0]
        if marker == 0x01 {
            guard raw.count >= 65 else { throw SecretStashError.invalidLength }
            return .xprv(chainCode: Data(raw[1..<33]), privateKey: Data(raw[33..<65]))
        }
        if marker & 0x80 != 0 {
            let length = Int((marker & 0x03) + 2) * 8
            guard [16, 24, 32].contains(length), raw.count > length else { throw SecretStashError.invalidLength }
            return .words(entropy: Data(raw[1..<(1 + length)]))
        }
        if marker == 0 { throw SecretStashError.empty }
        let length = Int(marker)
        guard (16...64).contains(length), raw.count > length else { throw SecretStashError.unknownMarker(marker) }
        return .masterSecret(Data(raw[1..<(1 + length)]))
    }

    public static func trimTrailingZeros(_ data: Data) -> Data {
        var raw = data
        while raw.count > 1, raw.last == 0 { raw.removeLast() }
        return raw
    }

    /// Firmware `SecretStash.summary` (`stash.py`).
    public static func summary(_ marker: UInt8) -> String {
        if marker == 0x01 { return "xprv" }
        if marker & 0x80 != 0 {
            let length = Int((marker & 0x03) + 2) * 8
            switch length {
            case 16: return "12 words"
            case 24: return "18 words"
            case 32: return "24 words"
            default: return "\(length) bytes"
            }
        }
        if marker == 0 { return "zeros" }
        return "master secret"
    }
}

extension SecretStashError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .empty: "Empty secret."
        case .unknownMarker(let marker): "Unknown secret marker \(marker)."
        case .invalidLength: "Invalid encoded secret length."
        }
    }
}

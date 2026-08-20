import Foundation

public enum ByteEncodingError: Error, Equatable, Sendable {
    case invalidHex
    case outOfBounds
    case invalidVarInt
}

public extension Data {
    init(hex: String) throws {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard cleaned.count.isMultiple(of: 2) else { throw ByteEncodingError.invalidHex }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw ByteEncodingError.invalidHex
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    func reversedData() -> Data { Data(reversed()) }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func appendUInt64BE(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    mutating func appendVarInt(_ value: UInt64) {
        switch value {
        case 0..<0xfd:
            append(UInt8(value))
        case 0xfd...0xffff:
            append(0xfd)
            appendUInt16LE(UInt16(value))
        case 0x1_0000...0xffff_ffff:
            append(0xfe)
            appendUInt32LE(UInt32(value))
        default:
            append(0xff)
            appendUInt64LE(value)
        }
    }
}

public struct ByteReader: Sendable {
    public private(set) var data: Data
    public private(set) var offset: Int = 0

    public init(_ data: Data) { self.data = data }
    public var remaining: Int { data.count - offset }
    public var isAtEnd: Bool { offset == data.count }

    public mutating func readByte() throws -> UInt8 {
        guard offset < data.count else { throw ByteEncodingError.outOfBounds }
        defer { offset += 1 }
        return data[offset]
    }

    public mutating func read(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw ByteEncodingError.outOfBounds }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    public mutating func readUInt16LE() throws -> UInt16 {
        let bytes = try read(2)
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    public mutating func readUInt32LE() throws -> UInt32 {
        let bytes = try read(4)
        return bytes.enumerated().reduce(UInt32(0)) { partial, element in
            partial | (UInt32(element.element) << UInt32(element.offset * 8))
        }
    }

    public mutating func readUInt64LE() throws -> UInt64 {
        let bytes = try read(8)
        return bytes.enumerated().reduce(UInt64(0)) { partial, element in
            partial | (UInt64(element.element) << UInt64(element.offset * 8))
        }
    }

    public mutating func readUInt32BE() throws -> UInt32 {
        let bytes = try read(4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    public mutating func readVarInt() throws -> UInt64 {
        let prefix = try readByte()
        switch prefix {
        case 0x00...0xfc: return UInt64(prefix)
        case 0xfd:
            let value = UInt64(try readUInt16LE())
            guard value >= 0xfd else { throw ByteEncodingError.invalidVarInt }
            return value
        case 0xfe:
            let value = UInt64(try readUInt32LE())
            guard value > 0xffff else { throw ByteEncodingError.invalidVarInt }
            return value
        case 0xff:
            let value = try readUInt64LE()
            guard value > 0xffff_ffff else { throw ByteEncodingError.invalidVarInt }
            return value
        default:
            fatalError("unreachable")
        }
    }

    public mutating func readVarData(max: Int = 64 * 1024 * 1024) throws -> Data {
        let length = try readVarInt()
        guard length <= UInt64(max), length <= UInt64(Int.max) else { throw ByteEncodingError.invalidVarInt }
        return try read(Int(length))
    }
}

@inline(__always) internal func rotateRight(_ value: UInt32, by: UInt32) -> UInt32 {
    (value >> by) | (value << (32 - by))
}

@inline(__always) internal func rotateRight(_ value: UInt64, by: UInt64) -> UInt64 {
    (value >> by) | (value << (64 - by))
}

@inline(__always) internal func rotateLeft(_ value: UInt32, by: UInt32) -> UInt32 {
    (value << by) | (value >> (32 - by))
}

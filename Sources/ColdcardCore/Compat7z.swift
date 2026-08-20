import Foundation

/// Firmware `compat7z.Builder` — AES-256 7z with no compression.
public enum Compat7z {
    public static let magic = Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
    /// Firmware `Builder.__init__` default (`rounds_pow=13`).
    public static let defaultRoundsPow = 13
    public static let notesMaxSize = 100_000

    public static func isFirmware7z(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    /// Firmware `encode_utf_16_le`: UTF-8 bytes interleaved with zeros (ASCII-oriented).
    public static func encodeUTF16LE(_ string: String) -> Data {
        let utf8 = Array(string.utf8)
        var out = Data(capacity: utf8.count * 2)
        for byte in utf8 {
            out.append(byte)
            out.append(0)
        }
        return out
    }

    public static func decodeUTF16LE(_ data: Data) -> String {
        var bytes = Data()
        var index = 0
        let raw = [UInt8](data)
        while index < raw.count {
            bytes.append(raw[index])
            index += 2
        }
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    public static func calculateKey(password: String, salt: Data, roundsPow: Int) -> Data {
        let passwordUTF16 = encodeUTF16LE(password)
        let rounds = 1 << roundsPow
        var message = Data(capacity: (salt.count + passwordUTF16.count + 8) * rounds)
        for index in 0..<rounds {
            message.append(salt)
            message.append(passwordUTF16)
            var counter = UInt64(index).littleEndian
            withUnsafeBytes(of: &counter) { message.append(contentsOf: $0) }
        }
        return SHA2.sha256(message)
    }

    public static func encrypt(
        plaintext: Data,
        password: String,
        innerName: String,
        salt: Data,
        iv: Data,
        roundsPow: Int = defaultRoundsPow
    ) throws -> Data {
        guard salt.count >= 16, iv.count == 16 else { throw Compat7zError.confusedFile }
        let key = calculateKey(password: password, salt: salt, roundsPow: roundsPow)
        let paddedLen = (plaintext.count + 15) & ~15
        var padded = plaintext
        if paddedLen != plaintext.count {
            padded.append(Data(repeating: 0, count: paddedLen - plaintext.count))
        }
        let body = AES256CTR.cryptCBC(encrypt: true, key: key, iv: iv, data: padded)
        let trailer = renderHeader(
            innerName: innerName,
            bodyLength: body.count,
            unpackedSize: plaintext.count,
            plaintextCRC: CRC32.hash(plaintext),
            salt: salt,
            iv: iv,
            roundsPow: roundsPow
        )
        var section = Data()
        appendLE(&section, UInt64(body.count))
        appendLE(&section, UInt64(trailer.count))
        appendLE(&section, CRC32.hash(trailer))
        var file = Data(magic)
        file.append(0)
        file.append(3)
        appendLE(&file, CRC32.hash(section))
        file.append(section)
        file.append(body)
        file.append(trailer)
        return file
    }

    public static func decrypt(
        _ data: Data,
        password: String,
        innerExtension: String = ".json",
        maxSize: Int = notesMaxSize
    ) throws -> (filename: String, plaintext: Data) {
        let parsed = try parseContainer(data, maxSize: maxSize)
        let key = calculateKey(password: password, salt: parsed.salt, roundsPow: parsed.roundsPow)
        let padded = AES256CTR.cryptCBC(encrypt: false, key: key, iv: parsed.iv, data: parsed.body)
        let plain = Data(padded.prefix(parsed.unpackedSize))
        guard CRC32.hash(plain) == parsed.plaintextCRC else { throw Compat7zError.wrongPassword }
        if !innerExtension.isEmpty {
            guard parsed.filename.lowercased().hasSuffix(innerExtension.lowercased()) else {
                throw Compat7zError.invalidBackup("not \(innerExtension)")
            }
        }
        return (parsed.filename, plain)
    }

    // MARK: - Header parse

    private struct ParsedFile {
        var body: Data
        var filename: String
        var unpackedSize: Int
        var plaintextCRC: UInt32
        var salt: Data
        var iv: Data
        var roundsPow: Int
    }

    private static func parseContainer(_ data: Data, maxSize: Int) throws -> ParsedFile {
        guard data.count >= 32 else { throw Compat7zError.unableToRead("truncated") }
        let bytes = [UInt8](data)
        guard bytes.starts(with: [UInt8](magic)), bytes[6] == 0, bytes[7] >= 3 else {
            throw Compat7zError.badMagic
        }
        let fileCRC = readUInt32(bytes, 8)
        let section = Data(bytes[12..<32])
        guard CRC32.hash(section) == fileCRC else { throw Compat7zError.secondHeaderCRC }
        let bodyLength = Int(readUInt64(bytes, 12))
        let trailerLength = Int(readUInt64(bytes, 20))
        let trailerCRC = readUInt32(bytes, 28)
        let bodyStart = 32
        let bodyEnd = bodyStart + bodyLength
        let trailerEnd = bodyEnd + trailerLength
        guard bodyEnd <= bytes.count, trailerEnd <= bytes.count else {
            throw Compat7zError.unableToRead("Truncated file?")
        }
        let body = Data(bytes[bodyStart..<bodyEnd])
        let trailer = Data(bytes[bodyEnd..<trailerEnd])
        guard CRC32.hash(trailer) == trailerCRC else { throw Compat7zError.trailingHeaderCRC }
        guard trailer.range(of: Data([0x24, 0x06, 0xF1, 0x07, 0x01])) != nil else {
            throw Compat7zError.notAES
        }
        let meta = try parseTrailer(trailer)
        guard body.count == meta.bodySize else { throw Compat7zError.confusedFile }
        guard meta.unpackedSize <= maxSize else { throw Compat7zError.tooBig }
        guard body.count <= meta.unpackedSize + 16 else { throw Compat7zError.tooBigEncoded }
        guard body.count % 16 == 0 else { throw Compat7zError.notBlocked }
        return ParsedFile(
            body: body,
            filename: meta.filename,
            unpackedSize: meta.unpackedSize,
            plaintextCRC: meta.plaintextCRC,
            salt: meta.salt,
            iv: meta.iv,
            roundsPow: meta.roundsPow
        )
    }

    private struct TrailerMeta {
        var filename: String
        var bodySize: Int
        var unpackedSize: Int
        var plaintextCRC: UInt32
        var salt: Data
        var iv: Data
        var roundsPow: Int
    }

    private static func parseTrailer(_ hdr: Data) throws -> TrailerMeta {
        var cursor = ByteCursor(hdr)
        try cursor.skipPattern([0x01, 0x04, 0x06, 0x00, 0x01, 0x09])
        let bodySize = Int(try cursor.readVar64())
        try cursor.skipPattern([0x07, 0x0B, 0x01, 0x00, 0x01, 0x24, 0x06, 0xF1, 0x07, 0x01])
        let propsLen = Int(try cursor.readVar64())
        let propsStart = cursor.offset
        let first = try cursor.readByte()
        let second = try cursor.readByte()
        let roundsPow = Int(first & 0x3F)
        guard roundsPow <= 19 else { throw Compat7zError.confusedFile }
        guard first & 0xC0 == 0xC0 else { throw Compat7zError.confusedFile }
        let saltLen = Int((second >> 4) & 0xF) + 1
        let ivLen = Int(second & 0xF) + 1
        guard saltLen >= 16, ivLen >= 16 else { throw Compat7zError.confusedFile }
        let salt = try cursor.read(saltLen)
        let iv = try cursor.read(ivLen)
        guard cursor.offset - propsStart == propsLen else { throw Compat7zError.confusedFile }
        try cursor.skipPattern([0x01, 0x00, 0x0C])
        let unpackedSize = Int(try cursor.readVar64())
        guard try cursor.readByte() == 0 else { throw Compat7zError.confusedFile }
        try cursor.skipPattern([0x08, 0x0A, 0x01])
        let expectCRC = try cursor.readUInt32()
        guard try cursor.readByte() == 0 else { throw Compat7zError.confusedFile }
        try cursor.skipPattern([0x05, 0x01, 0x11])
        let fnameLen = Int(try cursor.readVar64()) - 1
        guard try cursor.readByte() == 0 else { throw Compat7zError.confusedFile }
        let encoded = try cursor.read(fnameLen)
        var filename = decodeUTF16LE(encoded)
        if filename.hasSuffix("\0") { filename.removeLast() }
        return TrailerMeta(
            filename: filename,
            bodySize: bodySize,
            unpackedSize: unpackedSize,
            plaintextCRC: expectCRC,
            salt: salt,
            iv: iv,
            roundsPow: roundsPow
        )
    }

    private static func renderHeader(
        innerName: String,
        bodyLength: Int,
        unpackedSize: Int,
        plaintextCRC: UInt32,
        salt: Data,
        iv: Data,
        roundsPow: Int
    ) -> Data {
        var rv = Data([0x01, 0x04, 0x06, 0x00, 0x01, 0x09])
        rv.append(writeVar64(UInt64(bodyLength)))
        rv.append(0x00)
        rv.append(contentsOf: [0x07, 0x0B, 0x01, 0x00, 0x01, 0x24, 0x06, 0xF1, 0x07, 0x01])
        var first = UInt8(roundsPow & 0x3F)
        if !salt.isEmpty { first |= 0x80 }
        if !iv.isEmpty { first |= 0x40 }
        let saltLen = salt.isEmpty ? 0 : salt.count - 1
        let ivLen = iv.isEmpty ? 0 : iv.count - 1
        let second = UInt8(((saltLen & 0xF) << 4) | (ivLen & 0xF))
        let props = Data([first, second]) + salt + iv
        rv.append(writeVar64(UInt64(props.count)))
        rv.append(props)
        rv.append(contentsOf: [0x01, 0x00, 0x0C])
        rv.append(writeVar64(UInt64(unpackedSize)))
        rv.append(0x00)
        rv.append(contentsOf: [0x08, 0x0A, 0x01])
        appendLE(&rv, plaintextCRC)
        rv.append(0x00)
        rv.append(0x00)
        let encodedName = encodeUTF16LE(innerName + "\0")
        rv.append(contentsOf: [0x05, 0x01, 0x11])
        rv.append(writeVar64(UInt64(encodedName.count + 1)))
        rv.append(0x00)
        rv.append(encodedName)
        rv.append(0x00)
        rv.append(0x00)
        return rv
    }

    static func writeVar64(_ n: UInt64) -> Data {
        if n < 127 { return Data([UInt8(n)]) }
        if n < 65536 {
            var out = Data([0xC0])
            appendLE(&out, UInt16(n))
            return out
        }
        if n < (1 << 32) {
            var out = Data([0xF0])
            appendLE(&out, UInt32(truncatingIfNeeded: n))
            return out
        }
        var out = Data([0xFF])
        appendLE(&out, n)
        return out
    }
}

public enum Compat7zError: Error, Equatable, Sendable {
    case badMagic
    case secondHeaderCRC
    case trailingHeaderCRC
    case notAES
    case confusedFile
    case tooBig
    case tooBigEncoded
    case notBlocked
    case wrongPassword
    case invalidBackup(String)
    case unableToRead(String)

    /// Copy from `compat7z.py` / `backups.check_and_decrypt`.
    public var firmwareMessage: String {
        switch self {
        case .badMagic: "Bad magic bytes"
        case .secondHeaderCRC: "Second header has wrong CRC"
        case .trailingHeaderCRC: "Trailing header has wrong CRC"
        case .notAES: "Not marked as AES+SHA encrypted?"
        case .confusedFile: "Confused file?"
        case .tooBig, .tooBigEncoded: "too big"
        case .notBlocked: "not blocked"
        case .wrongPassword:
            "Unable to decrypt backup file. Incorrect password?"
        case .invalidBackup(let detail): "Invalid backup file: \(detail)"
        case .unableToRead(let detail):
            "Unable to read backup file. Has it been touched?\n\nError: \(detail)"
        }
    }
}

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
            }
            return crc
        }
    }()

    static func hash(_ data: Data, seed: UInt32 = 0) -> UInt32 {
        var crc = seed ^ 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private struct ByteCursor {
    let bytes: [UInt8]
    var offset = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func readByte() throws -> UInt8 {
        guard offset < bytes.count else { throw Compat7zError.confusedFile }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func read(_ count: Int) throws -> Data {
        guard offset + count <= bytes.count else { throw Compat7zError.confusedFile }
        let slice = bytes[offset..<(offset + count)]
        offset += count
        return Data(slice)
    }

    mutating func readUInt32() throws -> UInt32 {
        let data = try read(4)
        let raw = [UInt8](data)
        return UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24
    }

    mutating func skipPattern(_ pattern: [UInt8]) throws {
        guard let found = find(pattern) else { throw Compat7zError.confusedFile }
        offset = found + pattern.count
    }

    mutating func readVar64() throws -> UInt64 {
        let first = try readByte()
        if first < 128 { return UInt64(first) }
        if first == 0xFE || first == 0xFF {
            let raw = [UInt8](try read(8))
            return raw.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * $1.offset) }
        }
        let bits = String(first, radix: 2)
        let padded = String(repeating: "0", count: max(0, 8 - bits.count)) + bits
        guard let idx = padded.range(of: "10") else { throw Compat7zError.confusedFile }
        let pos = padded.distance(from: padded.startIndex, to: idx.lowerBound) + 1
        guard (1...6).contains(pos) else { throw Compat7zError.confusedFile }
        var tmp = [UInt8](try read(pos))
        tmp.append(contentsOf: repeatElement(0, count: 8 - pos))
        let y = tmp.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * $1.offset) }
        let x = UInt64(first & (0xEF >> pos))
        return (x << pos) + y
    }

    private func find(_ pattern: [UInt8]) -> Int? {
        guard !pattern.isEmpty, offset <= bytes.count else { return nil }
        let hay = bytes[offset...]
        return hay.firstRange(of: pattern)?.lowerBound
    }
}

private func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}

private func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset])
        | UInt32(bytes[offset + 1]) << 8
        | UInt32(bytes[offset + 2]) << 16
        | UInt32(bytes[offset + 3]) << 24
}

private func readUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for index in 0..<8 { value |= UInt64(bytes[offset + index]) << (8 * index) }
    return value
}

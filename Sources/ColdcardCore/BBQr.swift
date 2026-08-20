import Foundation
import Compression

public enum BBQrError: Error, Equatable, Sendable {
    case invalidHeader
    case unsupportedEncoding(Character)
    case invalidPartCount
    case invalidPartIndex
    case inconsistentSeries
    case invalidBody
    case tooManyParts
    case incomplete
    case invalidPart
    case decompressFailed
}

public enum BBQrEncoding: Character, Sendable {
    case hex = "H"
    case base32 = "2"
    /// Raw DEFLATE (`uzlib.decompress(..., -10)`) then Base32, firmware `bbqr.py`.
    case zlib = "Z"

    fileprivate var splitMod: Int {
        switch self {
        case .hex: 2
        case .base32, .zlib: 8
        }
    }
}

public enum BBQrFileType: Character, Sendable {
    case psbt = "P"
    case transaction = "T"
    case json = "J"
    case cbor = "C"
    case unicode = "U"
    case executable = "X"
    case binary = "B"
    case keyTeleportReceive = "R"
    case keyTeleportTransmit = "S"
    case keyTeleportPSBT = "E"

    public var label: String {
        switch self {
        case .psbt: "PSBT File"
        case .transaction: "Transaction"
        case .json: "JSON"
        case .cbor: "CBOR"
        case .unicode: "Unicode Text"
        case .executable: "Executable"
        case .binary: "Binary"
        case .keyTeleportReceive: "KT Rx"
        case .keyTeleportTransmit: "KT Tx"
        case .keyTeleportPSBT: "KT PSBT"
        }
    }

    public static func label(for fileType: Character) -> String {
        BBQrFileType(rawValue: fileType)?.label ?? "Unknown: \(fileType)"
    }
}

public struct BBQrHeader: Equatable, Sendable {
    public static let prefix = "B$"
    public static let length = 8

    public let encoding: BBQrEncoding
    public let fileType: Character
    public let partCount: Int
    public let partIndex: Int

    public init(_ text: String) throws {
        guard text.count >= Self.length, text.hasPrefix(Self.prefix) else { throw BBQrError.invalidHeader }
        let chars = Array(text.prefix(Self.length))
        guard let encoding = BBQrEncoding(rawValue: chars[2]) else { throw BBQrError.unsupportedEncoding(chars[2]) }
        guard let count = Int(String(chars[4...5]), radix: 36), count > 0 else { throw BBQrError.invalidPartCount }
        guard let index = Int(String(chars[6...7]), radix: 36), index >= 0, index < count else { throw BBQrError.invalidPartIndex }
        self.encoding = encoding
        self.fileType = chars[3]
        self.partCount = count
        self.partIndex = index
    }

    public init(encoding: BBQrEncoding, fileType: Character, partCount: Int, partIndex: Int) throws {
        guard (1...1295).contains(partCount) else { throw BBQrError.invalidPartCount }
        guard (0..<partCount).contains(partIndex) else { throw BBQrError.invalidPartIndex }
        self.encoding = encoding
        self.fileType = fileType
        self.partCount = partCount
        self.partIndex = partIndex
    }

    public var text: String {
        "B$\(encoding.rawValue)\(fileType)\(Self.base36(partCount))\(Self.base36(partIndex))"
    }

    private static func base36(_ value: Int) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String([alphabet[(value / 36) % 36], alphabet[value % 36]])
    }
}

public struct BBQrDecodedPayload: Equatable, Sendable {
    public let fileType: Character
    public let data: Data
    public let encoding: BBQrEncoding
    public let partCount: Int
}

/// Firmware `draw_bbqr_progress` snapshot (`lcd_display.py`).
public struct BBQrScanProgress: Equatable, Sendable {
    public var fileType: Character
    public var collected: Int
    public var total: Int
    public var gotParts: Set<Int>
    public var currentIndex: Int
    public var corrupt: Bool
    public var awaitingRuntPlacement: Bool

    public init(fileType: Character, collected: Int, total: Int, gotParts: Set<Int>,
                currentIndex: Int, corrupt: Bool, awaitingRuntPlacement: Bool) {
        self.fileType = fileType
        self.collected = collected
        self.total = total
        self.gotParts = gotParts
        self.currentIndex = currentIndex
        self.corrupt = corrupt
        self.awaitingRuntPlacement = awaitingRuntPlacement
    }

    public var fileLabel: String { BBQrFileType.label(for: fileType) }

    public var instructionLine: String {
        (collected < total || awaitingRuntPlacement) ? "Keep scanning more..." : "Got all parts!"
    }

    public var countLine: String { "\(fileLabel): \(collected) of \(total) parts" }

    /// Firmware skips the three-line story for a single complete part.
    public var skipsProgressUI: Bool { collected == total && collected == 1 && !corrupt }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(collected) / Double(total)
    }

    /// Firmware `draw_bbqr_progress` tick line (`-` / `X` / 1-based index).
    public var partPattern: String {
        guard (2..<LCDDisplay.charsW / 2).contains(total) else { return "" }
        var slots: [String] = []
        slots.reserveCapacity(total)
        for index in 0..<total {
            if gotParts.contains(index) {
                slots.append(String(index + 1))
            } else {
                let width = index < 9 ? 1 : 2
                if corrupt && index == currentIndex {
                    slots.append(String(repeating: "X", count: width))
                } else {
                    slots.append(String(repeating: "-", count: width))
                }
            }
        }
        let joined = slots.joined(separator: total <= 8 ? "  " : " ")
        return joined.count > LCDDisplay.charsW ? "" : joined
    }

    public var statusMessage: String {
        if skipsProgressUI { return countLine }
        let pattern = partPattern
        if pattern.isEmpty { return "\(instructionLine)\n\(countLine)" }
        return "\(pattern)\n\(instructionLine)\n\(countLine)"
    }
}

public enum BBQrCollectionResult: Equatable, Sendable {
    case progress(BBQrScanProgress)
    case complete(BBQrDecodedPayload)
}

public enum BBQr {
    /// Firmware `CHARS_PER_VERSION` for Q LCD height (`bbqr.py`).
    private static let firmwareCapacities = [(15, 758), (25, 1853), (40, 4296)]
    /// Firmware `dis.fullscreen('Decompressing...')` during `Z` finalize.
    public static let decompressingTitle = "Decompressing..."

    /// Splits a payload into the alphanumeric BBQr framing used by Coldcard Q.
    /// Pass `maximumCharactersPerQR` to override the firmware 15/25/40 targeting
    /// (tests and constrained LCD previews).
    public static func encode(_ data: Data, fileType: BBQrFileType,
                              encoding: BBQrEncoding = .base32,
                              maximumCharactersPerQR: Int? = nil) throws -> [String] {
        let payload: Data
        let wireEncoding: BBQrEncoding
        switch encoding {
        case .zlib:
            payload = try RawDeflate.deflate(data)
            wireEncoding = .zlib
        case .hex, .base32:
            payload = data
            wireEncoding = encoding
        }

        let bytesPerPart: Int
        let partCount: Int
        if let cap = maximumCharactersPerQR {
            guard cap > BBQrHeader.length + 8 else { throw BBQrError.invalidBody }
            let bodyCapacity = cap - BBQrHeader.length
            switch wireEncoding {
            case .hex:
                bytesPerPart = max(1, bodyCapacity / 2)
            case .base32, .zlib:
                bytesPerPart = max(1, (bodyCapacity / 8) * 5)
            }
            partCount = max(1, (payload.count + bytesPerPart - 1) / bytesPerPart)
        } else {
            let plan = try firmwareSplit(payloadCount: payload.count, encoding: wireEncoding)
            bytesPerPart = plan.bytesPerPart
            partCount = plan.partCount
        }
        guard partCount <= 1295 else { throw BBQrError.tooManyParts }

        var parts: [String] = []
        parts.reserveCapacity(partCount)
        for index in 0..<partCount {
            let start = min(payload.count, index * bytesPerPart)
            let end = min(payload.count, start + bytesPerPart)
            let chunk = payload.subdata(in: start..<end)
            let body: String
            switch wireEncoding {
            case .hex: body = chunk.hexString.uppercased()
            case .base32, .zlib: body = Base32.encode(chunk)
            }
            let header = try BBQrHeader(encoding: wireEncoding, fileType: fileType.rawValue,
                                        partCount: partCount, partIndex: index)
            parts.append(header.text + body)
        }
        return parts
    }

    public static func decode(_ parts: [String]) throws -> BBQrDecodedPayload {
        var collector = BBQrCollector()
        for part in parts {
            switch try collector.add(part) {
            case .complete(let payload): return payload
            case .progress(let progress) where progress.corrupt: throw BBQrError.invalidPart
            case .progress: continue
            }
        }
        throw BBQrError.incomplete
    }

    /// Firmware `num_qr_needed` + `calc_num_qr` (`bbqr.py`).
    private static func firmwareSplit(payloadCount: Int, encoding: BBQrEncoding) throws -> (partCount: Int, bytesPerPart: Int) {
        let splitMod = encoding.splitMod
        let charLen: Int
        switch encoding {
        case .hex:
            charLen = payloadCount * 2
        case .base32, .zlib:
            let remain = payloadCount % 5
            let padChars = [0: 0, 1: 2, 2: 4, 3: 5, 4: 7][remain] ?? 0
            charLen = (payloadCount / 5) * 8 + padChars
        }

        var chosenParts = 1
        var chosenCharPart = charLen
        for (index, entry) in firmwareCapacities.enumerated() {
            let (version, capacity) = entry
            let (need, level) = calcNumQR(charCapacity: capacity, charLen: charLen, splitMod: splitMod)
            if need == 1 {
                chosenParts = 1
                chosenCharPart = charLen
                break
            }
            if version == 15 && need == 2 { continue }
            if version < 40 && need <= 12 {
                chosenParts = need
                chosenCharPart = level
                break
            }
            if index == firmwareCapacities.count - 1 {
                chosenParts = need
                chosenCharPart = level
            }
        }

        let bytesPerPart: Int
        if chosenParts > 1 {
            switch encoding {
            case .hex: bytesPerPart = chosenCharPart / 2
            case .base32, .zlib: bytesPerPart = chosenCharPart * 5 / 8
            }
        } else {
            bytesPerPart = payloadCount
        }
        return (max(1, chosenParts), max(1, bytesPerPart))
    }

    private static func calcNumQR(charCapacity: Int, charLen: Int, splitMod: Int) -> (Int, Int) {
        let cap = charCapacity - 8
        if charLen <= cap { return (1, charLen) }
        let cap2 = cap - (cap % splitMod)
        var need = Int(ceil(Double(charLen) / Double(max(1, cap2))))
        let actual = ((need - 1) * cap2) + cap
        if charLen > actual { need += 1 }
        var level = Int(ceil(Double(charLen) / Double(need)))
        if level % splitMod != 0 { level += splitMod - (level % splitMod) }
        return (need, level)
    }
}

public struct BBQrCollector: Sendable {
    private var expectedEncoding: BBQrEncoding?
    private var expectedFileType: Character?
    private var expectedPartCount: Int?
    private var parts: Set<Int> = []
    private var runt: (index: Int, data: Data)?
    private var blksize: Int?
    private var buffer: Data?
    private var finalSize: Int?

    public init() {}

    public var collectedCount: Int { parts.count }
    public var totalCount: Int? { expectedPartCount }

    public mutating func reset() {
        expectedEncoding = nil
        expectedFileType = nil
        expectedPartCount = nil
        parts.removeAll(keepingCapacity: true)
        runt = nil
        blksize = nil
        buffer = nil
        finalSize = nil
    }

    public mutating func add(_ text: String) throws -> BBQrCollectionResult {
        let header = try BBQrHeader(text)
        if let encoding = expectedEncoding,
           encoding != header.encoding || expectedFileType != header.fileType || expectedPartCount != header.partCount {
            reset()
        }
        if expectedEncoding == nil {
            expectedEncoding = header.encoding
            expectedFileType = header.fileType
            expectedPartCount = header.partCount
        }

        if parts.contains(header.partIndex) {
            return .progress(makeProgress(header: header, corrupt: false))
        }

        let decoded: Data
        do {
            decoded = try decodeBody(text, header: header)
        } catch {
            return .progress(makeProgress(header: header, corrupt: true))
        }

        let isTrailingRuntFirst = header.partIndex != 0
            && header.partIndex == header.partCount - 1
            && parts.isEmpty
        if isTrailingRuntFirst {
            runt = (header.partIndex, decoded)
            parts.insert(header.partIndex)
        } else {
            if blksize == nil { blksize = decoded.count }
            do {
                try savePacket(header: header, which: header.partIndex, data: decoded)
            } catch {
                let progress = makeProgress(header: header, corrupt: true)
                reset()
                return .progress(progress)
            }
            parts.insert(header.partIndex)
        }

        if let held = runt, blksize != nil {
            do {
                try savePacket(header: header, which: held.index, data: held.data)
            } catch {
                let progress = makeProgress(header: header, corrupt: true)
                reset()
                return .progress(progress)
            }
            runt = nil
        }

        if parts.count == header.partCount && runt == nil {
            return try finalize(header: header)
        }
        return .progress(makeProgress(header: header, corrupt: false))
    }

    private func makeProgress(header: BBQrHeader, corrupt: Bool) -> BBQrScanProgress {
        BBQrScanProgress(
            fileType: header.fileType,
            collected: parts.count,
            total: header.partCount,
            gotParts: parts,
            currentIndex: header.partIndex,
            corrupt: corrupt,
            awaitingRuntPlacement: runt != nil
        )
    }

    private func decodeBody(_ text: String, header: BBQrHeader) throws -> Data {
        let bodyStart = text.index(text.startIndex, offsetBy: BBQrHeader.length)
        let body = String(text[bodyStart...])
        guard !body.contains("B$") else { throw BBQrError.invalidBody }
        switch header.encoding {
        case .hex: return try Data(hex: body)
        case .base32, .zlib: return try Base32.decode(body)
        }
    }

    private mutating func savePacket(header: BBQrHeader, which: Int, data: Data) throws {
        guard let blksize, blksize > 0 else { throw BBQrError.invalidPart }
        if data.count > blksize || (which != header.partCount - 1 && data.count != blksize) {
            throw BBQrError.invalidPart
        }
        if buffer == nil {
            buffer = Data(count: blksize * header.partCount)
        }
        let offset = which * blksize
        guard let buffer, offset + data.count <= buffer.count else { throw BBQrError.invalidPart }
        self.buffer?.replaceSubrange(offset..<(offset + data.count), with: data)
        if which == header.partCount - 1 {
            finalSize = blksize * (header.partCount - 1) + data.count
        }
    }

    private mutating func finalize(header: BBQrHeader) throws -> BBQrCollectionResult {
        guard let buffer else { throw BBQrError.incomplete }
        let size = finalSize ?? buffer.count
        var data = Data(buffer.prefix(size))
        if header.encoding == .zlib {
            do { data = try RawDeflate.inflate(data) }
            catch { throw BBQrError.decompressFailed }
        }
        let payload = BBQrDecodedPayload(
            fileType: header.fileType,
            data: data,
            encoding: header.encoding,
            partCount: header.partCount
        )
        reset()
        return .complete(payload)
    }
}

/// Raw DEFLATE matching firmware `uzlib` wbits=-10 (no zlib wrapper).
enum RawDeflate {
    static func deflate(_ input: Data) throws -> Data {
        try transcode(input, encode: true)
    }

    static func inflate(_ input: Data) throws -> Data {
        try transcode(input, encode: false)
    }

    private static func transcode(_ input: Data, encode: Bool) throws -> Data {
        if input.isEmpty { return Data() }
        var destSize = encode ? max(input.count + 64, 128) : max(input.count * 8, 256)
        for _ in 0..<8 {
            var dest = Data(count: destSize)
            let written = dest.withUnsafeMutableBytes { destBuf -> Int in
                input.withUnsafeBytes { srcBuf in
                    guard let destPtr = destBuf.bindMemory(to: UInt8.self).baseAddress,
                          let srcPtr = srcBuf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    if encode {
                        return compression_encode_buffer(destPtr, destSize, srcPtr, input.count, nil, COMPRESSION_ZLIB)
                    }
                    return compression_decode_buffer(destPtr, destSize, srcPtr, input.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0 {
                dest.count = written
                return dest
            }
            destSize *= 2
        }
        throw BBQrError.decompressFailed
    }
}

extension BBQrError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidHeader: "Invalid BBQr header."
        case .unsupportedEncoding(let encoding): "Unsupported BBQr encoding: \(encoding)."
        case .invalidPartCount: "Invalid BBQr part count."
        case .invalidPartIndex: "Invalid BBQr part index."
        case .inconsistentSeries: "This part belongs to a different BBQr series."
        case .invalidBody: "Invalid BBQr part content."
        case .tooManyParts: "The payload exceeds the 1,295-part BBQr limit."
        case .incomplete: "The BBQr series is incomplete."
        case .invalidPart: "Invalid BBQr part (runt or size mismatch)."
        case .decompressFailed: "Zlib fail"
        }
    }
}

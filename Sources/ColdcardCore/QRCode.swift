import Foundation

/// QR Version 4 (33×33) encoder matching firmware `uqr.make(..., min_version=4, max_version=4)`
/// (`external/mpy-qr`, Nayuki qrcodegen, ECL LOW with `boost_ecl`).
public enum QRCodeError: Error, Equatable, Sendable {
    case dataOverflow
    case unsupportedCharacters
}

public struct QRModuleGrid: Equatable, Sendable {
    public let size: Int
    /// Row-major; `true` is a dark module.
    private let modules: [Bool]

    public init(size: Int, modules: [Bool]) {
        self.size = size
        self.modules = modules
    }

    public func module(x: Int, y: Int) -> Bool {
        modules[y * size + x]
    }

    /// Firmware `paper.py` UTF-8 block QR: two U+2588 per dark module, two spaces per light.
    public func paperWalletASCII() -> String {
        (0..<size).map { y in
            let row = (0..<size).map { x in module(x: x, y: y) ? "\u{2588}\u{2588}" : "  " }.joined()
            return "        " + row
        }.joined(separator: "\n")
    }

    /// Firmware `insert_qr_hex`: 33 hex pairs of `00` (dark) / `FF` (light) per row, each row × 8.
    public func paperWalletPDFHex() -> Data {
        var output = Data()
        for y in 0..<size {
            var line = Data()
            for x in 0..<size {
                line.append(contentsOf: module(x: x, y: y) ? [0x30, 0x30] : [0x46, 0x46])
            }
            line.append(0x0A)
            for _ in 0..<8 { output.append(line) }
        }
        return output
    }
}

public enum QRCode {
    public enum Mode: Sendable {
        case byte
        case alphanumeric
    }

    public enum Ecc: Int, Sendable, CaseIterable {
        case low = 0
        case medium = 1
        case quartile = 2
        case high = 3
    }

    public static let version4Size = 33

    /// Firmware paper-wallet QR: version 4, ECL LOW with boost, auto mask.
    public static func version4(_ text: String, mode: Mode) throws -> QRModuleGrid {
        try encodeVersion4(Array(text.utf8), mode: mode, boostEcl: true)
    }

    public static func encodeVersion4(_ data: [UInt8], mode: Mode, boostEcl: Bool) throws -> QRModuleGrid {
        var ecl = Ecc.low
        var bits = try encodeBits(data, mode: mode)
        if boostEcl {
            for candidate: Ecc in [.medium, .quartile, .high] where bits.count <= dataCodewordCount(candidate) * 8 {
                ecl = candidate
            }
        }
        let dataWords = dataCodewordCount(ecl)
        let capacity = dataWords * 8
        guard bits.count <= capacity else { throw QRCodeError.dataOverflow }
        bits.append(contentsOf: Array(repeating: false, count: min(4, capacity - bits.count)))
        while bits.count % 8 != 0 { bits.append(false) }
        var pad = true
        while bits.count / 8 < dataWords {
            appendByte(pad ? 0xEC : 0x11, to: &bits)
            pad.toggle()
        }
        let codewords = addECC(bitsToBytes(bits), ecl: ecl)
        let function = functionModuleMask()
        var modules = Array(repeating: false, count: version4Size * version4Size)
        drawFunctionPatterns(&modules)
        drawCodewords(&modules, function: function, codewords: codewords)
        var bestModules = modules
        var bestPenalty = Int.max
        for mask in 0..<8 {
            var candidate = modules
            applyMask(&candidate, function: function, mask: mask)
            drawFormatBits(&candidate, ecl: ecl, mask: mask)
            let penalty = penaltyScore(candidate)
            if penalty < bestPenalty {
                bestPenalty = penalty
                bestModules = candidate
            }
        }
        return QRModuleGrid(size: version4Size, modules: bestModules)
    }

    // MARK: - Capacity (ISO/IEC 18004 version 4)

    private static func dataCodewordCount(_ ecl: Ecc) -> Int {
        switch ecl {
        case .low: 80
        case .medium: 64
        case .quartile: 48
        case .high: 36
        }
    }

    private static func eccPerBlock(_ ecl: Ecc) -> Int {
        switch ecl {
        case .low: 20
        case .medium: 18
        case .quartile: 26
        case .high: 16
        }
    }

    private static func blockCount(_ ecl: Ecc) -> Int {
        switch ecl {
        case .low: 1
        case .medium: 2
        case .quartile: 2
        case .high: 4
        }
    }

    private static let alphanumericCharset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")

    private static func encodeBits(_ data: [UInt8], mode: Mode) throws -> [Bool] {
        var bits: [Bool] = []
        switch mode {
        case .byte:
            appendBits(0b0100, count: 4, to: &bits)
            appendBits(data.count, count: 8, to: &bits)
            for byte in data { appendBits(Int(byte), count: 8, to: &bits) }
        case .alphanumeric:
            appendBits(0b0010, count: 4, to: &bits)
            appendBits(data.count, count: 9, to: &bits)
            let text = String(decoding: Data(data), as: UTF8.self)
            let values: [Int] = try text.map { character in
                guard let index = alphanumericCharset.firstIndex(of: character) else {
                    throw QRCodeError.unsupportedCharacters
                }
                return index
            }
            var index = 0
            while index + 1 < values.count {
                appendBits(values[index] * 45 + values[index + 1], count: 11, to: &bits)
                index += 2
            }
            if index < values.count {
                appendBits(values[index], count: 6, to: &bits)
            }
        }
        return bits
    }

    private static func appendBits(_ value: Int, count: Int, to bits: inout [Bool]) {
        for shift in stride(from: count - 1, through: 0, by: -1) {
            bits.append(((value >> shift) & 1) != 0)
        }
    }

    private static func appendByte(_ value: UInt8, to bits: inout [Bool]) {
        appendBits(Int(value), count: 8, to: &bits)
    }

    private static func bitsToBytes(_ bits: [Bool]) -> [UInt8] {
        stride(from: 0, to: bits.count, by: 8).map { start in
            var byte: UInt8 = 0
            for offset in 0..<8 where bits[start + offset] {
                byte |= 1 << (7 - offset)
            }
            return byte
        }
    }

    private static func addECC(_ data: [UInt8], ecl: Ecc) -> [UInt8] {
        let blocks = blockCount(ecl)
        let eccLen = eccPerBlock(ecl)
        let raw = 100
        let shortBlocks = blocks - raw % blocks
        let shortLen = raw / blocks
        let divisor = reedSolomonDivisor(degree: eccLen)
        var dataBlocks: [[UInt8]] = []
        var eccBlocks: [[UInt8]] = []
        var offset = 0
        for i in 0..<blocks {
            let dataLen = shortLen - eccLen + (i < shortBlocks ? 0 : 1)
            let block = Array(data[offset..<(offset + dataLen)])
            offset += dataLen
            dataBlocks.append(block)
            eccBlocks.append(reedSolomonRemainder(block, divisor: divisor))
        }
        var result: [UInt8] = []
        let maxData = dataBlocks.map(\.count).max() ?? 0
        for i in 0..<maxData {
            for block in dataBlocks where i < block.count { result.append(block[i]) }
        }
        for i in 0..<eccLen {
            for block in eccBlocks { result.append(block[i]) }
        }
        return result
    }

    private static func reedSolomonDivisor(degree: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root: UInt8 = 1
        for _ in 0..<degree {
            for j in 0..<degree {
                result[j] = gfMul(result[j], root)
                if j + 1 < degree { result[j] ^= result[j + 1] }
            }
            root = gfMul(root, 2)
        }
        return result
    }

    private static func reedSolomonRemainder(_ data: [UInt8], divisor: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: divisor.count)
        for byte in data {
            let factor = byte ^ result[0]
            result.removeFirst()
            result.append(0)
            for i in 0..<divisor.count {
                result[i] ^= gfMul(divisor[i], factor)
            }
        }
        return result
    }

    private static func gfMul(_ x: UInt8, _ y: UInt8) -> UInt8 {
        var a = UInt16(x), b = UInt16(y), p: UInt16 = 0
        while b > 0 {
            if b & 1 != 0 { p ^= a }
            b >>= 1
            a <<= 1
            if a & 0x100 != 0 { a ^= 0x11D }
        }
        return UInt8(p)
    }

    // MARK: - Geometry

    private static func index(_ x: Int, _ y: Int) -> Int { y * version4Size + x }

    /// True on every function-pattern cell (finders, separators, timing, alignment, format).
    private static func functionModuleMask() -> [Bool] {
        var mask = Array(repeating: false, count: version4Size * version4Size)
        func mark(_ x: Int, _ y: Int) {
            guard (0..<version4Size).contains(x), (0..<version4Size).contains(y) else { return }
            mask[index(x, y)] = true
        }
        for i in 0..<version4Size { mark(6, i); mark(i, 6) }
        for y in 0..<9 {
            for x in 0..<9 { mark(x, y) }
        }
        for y in 0..<9 {
            for x in (version4Size - 8)..<version4Size { mark(x, y) }
        }
        for y in (version4Size - 8)..<version4Size {
            for x in 0..<9 { mark(x, y) }
        }
        for dy in -2...2 {
            for dx in -2...2 { mark(18 + dx, 18 + dy) }
        }
        return mask
    }

    private static func drawFunctionPatterns(_ modules: inout [Bool]) {
        for i in 0..<version4Size {
            modules[index(6, i)] = i % 2 == 0
            modules[index(i, 6)] = i % 2 == 0
        }
        drawFinder(&modules, x: 0, y: 0)
        drawFinder(&modules, x: version4Size - 7, y: 0)
        drawFinder(&modules, x: 0, y: version4Size - 7)
        drawAlignment(&modules, x: 18, y: 18)
        modules[index(8, version4Size - 8)] = true
    }

    private static func drawFinder(_ modules: inout [Bool], x: Int, y: Int) {
        for dy in -1...7 {
            for dx in -1...7 {
                let xx = x + dx, yy = y + dy
                guard (0..<version4Size).contains(xx), (0..<version4Size).contains(yy) else { continue }
                let dark = (dx >= 0 && dx <= 6 && (dy == 0 || dy == 6))
                    || (dy >= 0 && dy <= 6 && (dx == 0 || dx == 6))
                    || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4)
                modules[index(xx, yy)] = dark
            }
        }
    }

    private static func drawAlignment(_ modules: inout [Bool], x: Int, y: Int) {
        for dy in -2...2 {
            for dx in -2...2 {
                modules[index(x + dx, y + dy)] = max(abs(dx), abs(dy)) != 1
            }
        }
    }

    /// Nayuki `drawFormatBits` coordinates (`qrcodegen.c`).
    private static func drawFormatBits(_ modules: inout [Bool], ecl: Ecc, mask: Int) {
        let data = ecl.formatBits << 3 | mask
        var rem = data
        for _ in 0..<10 { rem = (rem << 1) ^ ((rem >> 9) * 0x537) }
        let bits = (data << 10 | rem) ^ 0x5412
        func bit(_ i: Int) -> Bool { ((bits >> i) & 1) != 0 }
        for i in 0...5 { modules[index(8, i)] = bit(i) }
        modules[index(8, 7)] = bit(6)
        modules[index(8, 8)] = bit(7)
        modules[index(7, 8)] = bit(8)
        for i in 9..<15 { modules[index(14 - i, 8)] = bit(i) }
        for i in 0..<8 { modules[index(version4Size - 1 - i, 8)] = bit(i) }
        for i in 8..<15 { modules[index(8, version4Size - 15 + i)] = bit(i) }
        modules[index(8, version4Size - 8)] = true
    }

    private static func drawCodewords(_ modules: inout [Bool], function: [Bool], codewords: [UInt8]) {
        var bit = 0
        var right = version4Size - 1
        while right >= 1 {
            if right == 6 { right = 5 }
            for vert in 0..<version4Size {
                for j in 0..<2 {
                    let x = right - j
                    let upward = ((right + 1) & 2) == 0
                    let y = upward ? version4Size - 1 - vert : vert
                    if !function[index(x, y)], bit < codewords.count * 8 {
                        let byte = codewords[bit / 8]
                        modules[index(x, y)] = ((byte >> (7 - bit % 8)) & 1) != 0
                        bit += 1
                    }
                }
            }
            right -= 2
        }
    }

    private static func applyMask(_ modules: inout [Bool], function: [Bool], mask: Int) {
        for y in 0..<version4Size {
            for x in 0..<version4Size where !function[index(x, y)] {
                let invert: Bool
                switch mask {
                case 0: invert = (x + y) % 2 == 0
                case 1: invert = y % 2 == 0
                case 2: invert = x % 3 == 0
                case 3: invert = (x + y) % 3 == 0
                case 4: invert = (y / 2 + x / 3) % 2 == 0
                case 5: invert = (x * y) % 2 + (x * y) % 3 == 0
                case 6: invert = ((x * y) % 2 + (x * y) % 3) % 2 == 0
                default: invert = ((x + y) % 2 + (x * y) % 3) % 2 == 0
                }
                if invert { modules[index(x, y)].toggle() }
            }
        }
    }

    private static func penaltyScore(_ modules: [Bool]) -> Int {
        var result = 0
        for y in 0..<version4Size {
            var runColor = false
            var run = 0
            var bits = 0
            for x in 0..<version4Size {
                if x == 0 || modules[index(x, y)] != runColor {
                    runColor = modules[index(x, y)]
                    run = 1
                } else {
                    run += 1
                    if run == 5 { result += 3 }
                    else if run > 5 { result += 1 }
                }
                bits = ((bits << 1) & 0x7FF) | (modules[index(x, y)] ? 1 : 0)
                if x >= 10, bits == 0x05D || bits == 0x5D0 { result += 40 }
            }
        }
        for x in 0..<version4Size {
            var runColor = false
            var run = 0
            var bits = 0
            for y in 0..<version4Size {
                if y == 0 || modules[index(x, y)] != runColor {
                    runColor = modules[index(x, y)]
                    run = 1
                } else {
                    run += 1
                    if run == 5 { result += 3 }
                    else if run > 5 { result += 1 }
                }
                bits = ((bits << 1) & 0x7FF) | (modules[index(x, y)] ? 1 : 0)
                if y >= 10, bits == 0x05D || bits == 0x5D0 { result += 40 }
            }
        }
        for y in 0..<(version4Size - 1) {
            for x in 0..<(version4Size - 1) {
                let color = modules[index(x, y)]
                if color == modules[index(x + 1, y)],
                   color == modules[index(x, y + 1)],
                   color == modules[index(x + 1, y + 1)] {
                    result += 3
                }
            }
        }
        var dark = 0
        for module in modules where module { dark += 1 }
        let total = version4Size * version4Size
        let k = (abs(dark * 20 - total * 10) + total - 1) / total - 1
        result += k * 10
        return result
    }
}

private extension QRCode.Ecc {
    var formatBits: Int {
        switch self {
        case .low: 1
        case .medium: 0
        case .quartile: 3
        case .high: 2
        }
    }
}

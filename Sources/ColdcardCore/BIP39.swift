import Foundation

// Implements the MIT-licensed BIP-39 specification and published vectors.
// See ThirdParty/BIP39-NOTICE.md and Docs/PROVENANCE.md.

public enum BIP39Error: Error, Equatable, Sendable {
    case invalidEntropyLength
    case invalidWordCount
    case unknownWord(String)
    case invalidChecksum
    case invalidSeedQR
}

public struct BIP39Mnemonic: Equatable, Sendable, Codable {
    public let words: [String]

    public init(words: [String]) throws {
        let normalized = words.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        guard [12, 15, 18, 21, 24].contains(normalized.count) else { throw BIP39Error.invalidWordCount }
        _ = try Self.entropy(from: normalized)
        self.words = normalized
    }

    public init(phrase: String) throws {
        try self.init(words: phrase.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    }

    public init(entropy: Data) throws {
        guard [16, 20, 24, 28, 32].contains(entropy.count) else { throw BIP39Error.invalidEntropyLength }
        let checksumLength = entropy.count * 8 / 32
        let checksum = SHA2.sha256(entropy)
        var bits = Self.bits(of: entropy)
        bits.append(contentsOf: Self.bits(of: checksum).prefix(checksumLength))
        var result: [String] = []
        result.reserveCapacity(bits.count / 11)
        for start in stride(from: 0, to: bits.count, by: 11) {
            var index = 0
            for bit in bits[start..<(start + 11)] { index = (index << 1) | Int(bit) }
            result.append(BIP39EnglishWords.all[index])
        }
        self.words = result
    }

    public var phrase: String { words.joined(separator: " ") }
    public var entropy: Data { try! Self.entropy(from: words) }

    public func seed(passphrase: String = "") -> Data {
        let normalizedMnemonic = phrase.decomposedStringWithCompatibilityMapping
        let normalizedPassphrase = passphrase.decomposedStringWithCompatibilityMapping
        return PBKDF2.hmacSHA512(
            password: Data(normalizedMnemonic.utf8),
            salt: Data(("mnemonic" + normalizedPassphrase).utf8),
            iterations: 2048,
            keyLength: 64
        )
    }

    public var seedQR: String {
        words.map { word in
            let index = BIP39EnglishWords.all.firstIndex(of: word)!
            return String(format: "%04d", index)
        }.joined()
    }

    public static func fromSeedQR(_ value: String) throws -> BIP39Mnemonic {
        let digits = value.filter(\.isNumber)
        guard [48, 60, 72, 84, 96].contains(digits.count), digits.count.isMultiple(of: 4) else { throw BIP39Error.invalidSeedQR }
        var words: [String] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let end = digits.index(index, offsetBy: 4)
            guard let number = Int(digits[index..<end]), number < 2048 else { throw BIP39Error.invalidSeedQR }
            words.append(BIP39EnglishWords.all[number])
            index = end
        }
        return try BIP39Mnemonic(words: words)
    }

    public static func generate(wordCount: Int = 24, using randomBytes: (Int) throws -> Data) throws -> BIP39Mnemonic {
        let entropyBytes: Int
        switch wordCount {
        case 12: entropyBytes = 16
        case 15: entropyBytes = 20
        case 18: entropyBytes = 24
        case 21: entropyBytes = 28
        case 24: entropyBytes = 32
        default: throw BIP39Error.invalidWordCount
        }
        let entropy = try randomBytes(entropyBytes)
        guard entropy.count == entropyBytes else { throw BIP39Error.invalidEntropyLength }
        return try BIP39Mnemonic(entropy: entropy)
    }

    private static let wordMap: [String: Int] = Dictionary(uniqueKeysWithValues: BIP39EnglishWords.all.enumerated().map { ($1, $0) })

    private static func entropy(from words: [String]) throws -> Data {
        guard [12, 15, 18, 21, 24].contains(words.count) else { throw BIP39Error.invalidWordCount }
        var bits: [UInt8] = []
        bits.reserveCapacity(words.count * 11)
        for word in words {
            guard let value = wordMap[word] else { throw BIP39Error.unknownWord(word) }
            for shift in stride(from: 10, through: 0, by: -1) { bits.append(UInt8((value >> shift) & 1)) }
        }
        let entropyBitCount = bits.count * 32 / 33
        let checksumLength = bits.count - entropyBitCount
        var entropy = Data(repeating: 0, count: entropyBitCount / 8)
        for i in 0..<entropyBitCount where bits[i] == 1 { entropy[i / 8] |= UInt8(1 << (7 - i % 8)) }
        let expected = Self.bits(of: SHA2.sha256(entropy)).prefix(checksumLength)
        guard Array(bits.suffix(checksumLength)) == Array(expected) else { throw BIP39Error.invalidChecksum }
        return entropy
    }

    private static func bits(of data: Data) -> [UInt8] {
        data.flatMap { byte in (0..<8).map { UInt8((byte >> (7 - $0)) & 1) } }
    }

    /// Q `bip39.next_char`: next letters, and the unique completed word if any.
    public static func predict(prefix: String) -> (nextCharacters: String, completedWord: String?) {
        let needle = prefix.lowercased()
        guard !needle.isEmpty else { return ("", nil) }
        let matches = BIP39EnglishWords.all.filter { $0.hasPrefix(needle) }
        if matches.isEmpty { return ("", nil) }
        if matches.count == 1 { return ("", matches[0]) }
        var next = Set<Character>()
        for word in matches where word.count > needle.count {
            next.insert(word[word.index(word.startIndex, offsetBy: needle.count)])
        }
        let exact = matches.contains(needle) ? needle : nil
        return (String(next.sorted()), exact)
    }

    /// Firmware `a2b_words_guess`: possible BIP-39 checksum words given the preceding words.
    public static func checksumCandidates(precedingWords: [String]) -> [String] {
        BIP39EnglishWords.all.filter { candidate in
            (try? BIP39Mnemonic(words: precedingWords + [candidate])) != nil
        }
    }
}

import Foundation

/// Firmware `seed.py` / `ux_q1.seed_word_entry` new-wallet and word-entry UX.
public enum SeedEntropyKind: Equatable, Sendable {
    case mash
    case coin
    case diceMix
}

public enum SeedWordEntryKind: Equatable, Sendable {
    case importMaster
    case importEphemeral
    case backupPassword
    case xorPart(index: Int)
    case cccKeyC
    case cccChallenge
    case ssspFirstLast
}

public enum SeedBiasAction: Equatable, Sendable {
    case returnToMethodMenu
    case abort
}

public enum SeedCreation {
    public static let mashPrompt = "Press random keys"
    public static let mashDone = "Keep mashing or ENTER when done"
    public static let diceMixPrompt = "Enter each roll: 1-6"
    public static let diceMixDone = "Keep rolling or ENTER when done"
    public static let coinPrompt = "1 = Heads, 0 = Tails"
    public static let coinDone = "Keep flipping or ENTER when done"

    public static let mashTitle = "Mash Keys"
    public static let diceMixStoryTitle = "Dice Rolls"
    public static let coinTitle = "Coin Flips"
    public static let diceOnlyWarningTitle = "WARNING"
    public static let diceOnlyScreenTitle = ""

    public static let minMash = 65
    public static let minDiceMix = 50
    public static let minCoin = 128
    public static let maxWordLength = 8

    public static let generatingPauseTitle = "Generating..."
    public static let generatingPauseSeconds = 3.0
    public static let waitPauseTitle = "Wait..."
    public static let waitPauseSeconds = 1.0

    public static let confirmTitle = "Are you SURE ?!?"
    public static let skipQuizHint = "Press (6) to skip word quiz. "
    public static let quizPrompt = "Which word is right?"
    public static let quizGiveUp = "CANCEL to give up, ENTER to see all the words again."
    public static let wrongAnswerKeepsSameChoices = true
    public static let seedQRCaption = "SeedQR"
    public static let passphraseInEffect = "BIP-39 Passphrase in effect"
    public static let extendedPrivateKeyTitle = "Extended Private Key"
    public static let importedOrigin = "Imported"
    public static let wordEntryAbort = "Everything you've entered will be lost."
    public static let unableToDecodeSecret = "Unable to decode as secret"
    public static let biasStoryTitle = ""
    public static let mixBiasAction = SeedBiasAction.returnToMethodMenu
    public static let diceOnlyBiasAction = SeedBiasAction.abort

    public static let badDiceMessage =
        "Distribution of dice rolls is not random. Some numbers occurred more than 30% of the time."
    public static let badCoinMessage =
        "Distribution of coin flips is not random. Heads or tails occurred more than 65% of the time."

    public static func storyTitle(mixWithTRNG: Bool) -> String {
        mixWithTRNG ? diceMixStoryTitle : diceOnlyWarningTitle
    }

    public static func entropyLine2(kind: SeedEntropyKind, count: Int) -> String {
        switch kind {
        case .mash: return "\(count) / \(minMash) mashes"
        case .coin: return "\(count) / \(minCoin) flips"
        case .diceMix: return "\(count) / \(minDiceMix) rolls"
        }
    }

    public static func entropyLine3(kind: SeedEntropyKind, count: Int) -> String {
        switch kind {
        case .mash: return count >= minMash ? mashDone : mashPrompt
        case .coin: return count >= minCoin ? coinDone : coinPrompt
        case .diceMix: return count >= minDiceMix ? diceMixDone : diceMixPrompt
        }
    }

    public static func canFinishMash(count: Int) -> Bool { count >= minMash }
    public static func canFinishCoin(count: Int) -> Bool { count >= minCoin }
    public static func canFinishDiceMix(count: Int) -> Bool { count >= minDiceMix }

    public static func belowThresholdMessage(kind: SeedEntropyKind, count: Int) -> String? {
        switch kind {
        case .mash where !canFinishMash(count: count),
             .coin where !canFinishCoin(count: count),
             .diceMix where !canFinishDiceMix(count: count):
            return nil
        default:
            return nil
        }
    }

    public static func showsRunningHash(mixWithTRNG: Bool) -> Bool { !mixWithTRNG }

    /// Firmware `add_dice_rolls` `any((v / count) > 0.30)` — no minimum roll count.
    public static func diceRollsAreBiased(_ rolls: String) -> Bool {
        guard !rolls.isEmpty else { return false }
        let total = Double(rolls.count)
        for face in "123456" {
            let share = Double(rolls.filter { $0 == face }.count) / total
            if share > 0.30 { return true }
        }
        return false
    }

    public static func coinFlipsAreBiased(_ flips: String) -> Bool {
        guard !flips.isEmpty else { return false }
        let heads = flips.filter { $0 == "1" }.count
        let tails = flips.count - heads
        return Double(max(heads, tails)) / Double(flips.count) > 0.65
    }

    public static func notEnoughDiceApplies(mixWithTRNG: Bool, enforce: Bool) -> Bool {
        !mixWithTRNG && enforce
    }

    /// Firmware `add_dice_rolls`: CANCEL with fewer than 10 rolls exits; 10+ is ignored.
    public static func diceOnlyCancelExits(count: Int) -> Bool { count < 10 }

    public static func diceOnlyNotEnough(count: Int, bits: Int, words: Int, needed: Int) -> String {
        """
        Not enough dice rolls!!!

        You only provided \(count) dice rolls, and each roll adds only 2.585 bits of entropy. For \(bits)-bit security, which is considered the minimum for \(words) word seeds, you need at least \(needed) rolls.

        Press ENTER to add more dice rolls. CANCEL to exit
        """
    }

    /// `sha256(b'')` then `md.update` of each roll character (`add_dice_rolls`).
    public static func diceRunningHashHex(rolls: String) -> String {
        SHA2.sha256(Data(rolls.utf8)).hexString
    }

    public static func diceRunningHashLines(hex: String) -> (top: String, bottom: String) {
        (String(hex.prefix(32)) + "-", String(hex.dropFirst(32)))
    }

    public static func ephemeralOrigin(diceOnly: Bool) -> String {
        diceOnly ? "Dice" : "Generated Words"
    }

    public static func quizBody(choices: [String]) -> String {
        let lines = choices.prefix(3).enumerated().map { " \($0.offset + 1): \($0.element)" }
        return lines.joined(separator: "\n") + "\n\n\(quizPrompt)\n\n\(quizGiveUp)"
    }

    public static func viewSeedWords(passphraseActive: Bool, xprv: String, words: [String])
        -> (title: String, body: String) {
        if passphraseActive {
            return (extendedPrivateKeyTitle, "\(passphraseInEffect)\n\n\(xprv)")
        }
        return ("Seed words (\(words.count)):", SeedXOR.renderPartWords(words))
    }

    public static func wordEntryTitle(_ kind: SeedWordEntryKind) -> String {
        switch kind {
        case .importMaster, .cccChallenge: return "Enter Seed Words"
        case .importEphemeral: return "Ephemeral Seed Words"
        case .backupPassword: return "Enter Password:"
        case .xorPart(let index):
            let letter = Character(UnicodeScalar(65 + index)!)
            return "Part \(letter) Words"
        case .cccKeyC: return "Key C Seed Words"
        case .ssspFirstLast: return "First and Last Seed Words"
        }
    }

    public static func hasChecksum(_ kind: SeedWordEntryKind) -> Bool {
        switch kind {
        case .backupPassword, .ssspFirstLast: return false
        default: return true
        }
    }

    public static func donePrompt(hasChecksum: Bool) -> String {
        hasChecksum ? "Valid words! Press ENTER." : "Press ENTER if all done."
    }

    /// Firmware `seed_word_entry`: empty prefix is not a proactive hint; `err_msg` is reactive.
    public static func inventedProactiveHint(filledCount: Int, prefix: String, complete: Bool) -> String {
        if complete { return donePrompt(hasChecksum: true) }
        return ""
    }

    public static func bottomLine(complete: Bool, hasChecksum: Bool, error: String?) -> String {
        if complete { return donePrompt(hasChecksum: hasChecksum) }
        return error ?? ""
    }

    public static func finalWordError(prefix: String, candidates: [String]) -> String? {
        guard !prefix.isEmpty else { return nil }
        if candidates.contains(where: { $0 == prefix || $0.hasPrefix(prefix) }) { return nil }
        if candidates.count == 8 {
            let letters = String(Set(candidates.compactMap(\.first)).sorted())
            return "Final word starts with: " + letters
        }
        return "Final word cannot start with: " + prefix
    }

    public static func columnCount(wordCount: Int) -> Int { wordCount <= 12 ? 2 : 3 }

    public static func rows(wordCount: Int) -> Int {
        let columns = columnCount(wordCount: wordCount)
        return max(1, wordCount / max(columns, 1))
    }

    public static func gridIndex(row: Int, column: Int, wordCount: Int) -> Int {
        row + column * rows(wordCount: wordCount)
    }

    /// Firmware `ux_draw_words`.
    public static func drawCell(index: Int, word: String, count: Int) -> String {
        let n = index + 1
        if count == 12 {
            return String(format: "%2d: %@", n, word as NSString)
        }
        let nPerCol = max(1, count / max(columnCount(wordCount: count), 1))
        if n <= nPerCol {
            return String(format: "%d:%@", n, word as NSString)
        }
        return String(format: "%2d:%@", n, word as NSString)
    }

    public static func clampPrefix(_ value: String) -> String {
        String(value.filter(\.isLetter).prefix(maxWordLength))
    }

    public static func cursor(prefixLength: Int) -> PINCursor {
        if prefixLength >= maxWordLength {
            return PINCursor(index: maxWordLength - 1, style: .outline)
        }
        return PINCursor(index: prefixLength, style: .solid)
    }

    public static func confirmAbortWordEntry(filledCount: Int) -> Bool { filledCount >= 2 }

    public static func mustBeSeedWords(not kind: String) -> String {
        "Must be seed words, not \(kind)"
    }

    public static func wrongSeedLength(expected: Int, actual: Int) -> String {
        "Must be seed of length \(expected), not \(actual)"
    }

    public static func wordsFromQRText(_ text: String) -> [String]? {
        let taste = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !taste.isEmpty, taste.allSatisfy(\.isNumber) {
            let digits = taste.filter(\.isNumber)
            guard [48, 60, 72, 84, 96].contains(digits.count), digits.count.isMultiple(of: 4) else { return nil }
            var words: [String] = []
            var index = digits.startIndex
            while index < digits.endIndex {
                let end = digits.index(index, offsetBy: 4)
                guard let number = Int(digits[index..<end]), number < 2048 else { return nil }
                words.append(BIP39EnglishWords.all[number])
                index = end
            }
            return words
        }
        let tokens = taste.split(whereSeparator: \.isWhitespace).map(String.init)
        guard [12, 18, 24].contains(tokens.count) else { return nil }
        var words: [String] = []
        for token in tokens {
            if BIP39EnglishWords.all.contains(token) {
                words.append(token)
            } else if (3...8).contains(token.count),
                      let match = BIP39EnglishWords.all.first(where: { $0.hasPrefix(token) && (token.count >= 4 || $0 == token) }) {
                words.append(match)
            } else {
                return nil
            }
        }
        return words
    }

    public static let expectedSecretsNotPSBT = "Expected secrets not PSBT/TXN"

    public static func importedChecksumWords(_ words: [String]) -> [String] {
        words.last.map { [$0] } ?? []
    }

    public static func nextKeyHint(matches: [String], prefix: String) -> String? {
        guard matches.count > 1 else { return nil }
        let next = String(Set(matches.compactMap { word -> Character? in
            guard word.count > prefix.count else { return nil }
            return word[word.index(word.startIndex, offsetBy: prefix.count)]
        }).sorted())
        guard !next.isEmpty else { return nil }
        return "Next key: " + next
    }
}

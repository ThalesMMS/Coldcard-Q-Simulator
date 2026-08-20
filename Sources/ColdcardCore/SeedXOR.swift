import Foundation

/// Firmware `xor_seed.py` / `utils.xor`: bitwise XOR of equal-length seed entropy.
public enum SeedXORError: Error, Equatable {
    case partCount
    case lengthMismatch
    case zeroResult
}

public enum SeedXOR {
    /// Deterministic split (`sha256d("Batshitoshi " + secret + "%d of %d parts")`).
    public static func split(_ entropy: Data, parts: Int, randomParts: [Data]? = nil) throws -> [Data] {
        guard (2...4).contains(parts), [16, 24, 32].contains(entropy.count) else { throw SeedXORError.partCount }
        var masks: [Data] = []
        for index in 0..<(parts - 1) {
            if let randomParts {
                guard randomParts.indices.contains(index), randomParts[index].count == entropy.count else {
                    throw SeedXORError.lengthMismatch
                }
                masks.append(Data(SHA2.doubleSHA256(randomParts[index]).prefix(entropy.count)))
            } else {
                var material = Data("Batshitoshi ".utf8)
                material.append(entropy)
                material.append(Data("\(index) of \(parts) parts".utf8))
                masks.append(Data(SHA2.doubleSHA256(material).prefix(entropy.count)))
            }
        }
        masks.append(xor([entropy] + masks))
        guard xor(masks) == entropy else { throw SeedXORError.lengthMismatch }
        return masks
    }

    public static func combine(_ parts: [Data]) throws -> Data {
        guard parts.count >= 2 else { throw SeedXORError.partCount }
        let length = parts[0].count
        guard parts.allSatisfy({ $0.count == length }) else { throw SeedXORError.lengthMismatch }
        let result = xor(parts)
        return result
    }

    public static func xor(_ values: Data...) -> Data { xor(Array(values)) }

    public static func xor(_ values: [Data]) -> Data {
        guard let first = values.first else { return Data() }
        var result = [UInt8](first)
        for extra in values.dropFirst() {
            for index in result.indices { result[index] ^= extra[index] }
        }
        return Data(result)
    }

    /// Firmware `ux_q1.ux_render_words` used by `xor_seed.show_n_parts`.
    public static func renderPartWords(_ words: [String]) -> String {
        let count = words.count
        if count == 12 {
            return (0..<6).map { row in
                String(
                    format: "%2d: %@   %2d: %@",
                    row + 1, leftAligned(words[row], width: 8),
                    row + 7, words[row + 6]
                )
            }.joined(separator: "\n")
        }
        guard count == 18 || count == 24 else {
            return words.enumerated().map { String(format: "%2d: %@", $0.offset + 1, $0.element) }
                .joined(separator: "\n")
        }
        let lines = count == 18 ? 6 : 8
        var rendered: [String] = []
        rendered.reserveCapacity(lines)
        for row in 0..<lines {
            let line = String(
                format: "%d:%@ %2d:%@ %2d:%@",
                row + 1, leftAligned(words[row], width: 8),
                row + lines + 1, leftAligned(words[row + lines], width: 8),
                row + (lines * 2) + 1, words[row + (lines * 2)]
            )
            rendered.append(line)
        }
        return rendered.joined(separator: "\n")
    }

    /// Python `'%-Ns'` for ASCII seed words.
    public static func leftAligned(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return text + String(repeating: " ", count: width - text.count)
    }
}

/// Firmware `xor_seed.py` story copy (Q: `OK` is ENTER).
public enum SeedXORStories {
    public static let ok = "ENTER"

    public static let splitIntro = """
    This feature splits your BIP-39 seed phrase into multiple parts. Each part looks and functions as a normal BIP-39 wallet.

    We recommend spliting into just two parts, but permit up to four.

    If ANY ONE of the parts is lost, then ALL FUNDS are lost and the original seed phrase cannot be reconstructed.

    Finding a single part does not help an attacker construct the original seed.

    Press 2, 3 or 4 to select number of parts to split into. 
    """

    public static func splitIntoParts(_ count: Int, ok: String = Self.ok) -> String {
        """
        On the following screen you will be shown \(count) lists of words. The new words, when reconstructed, will re-create the seed already in use on this Coldcard.

        The new parts are generated deterministically from your seed, so if you repeat this process later, the same words will be shown.

        If you would prefer a random split using the TRNG, press (2). Otherwise, press \(ok) to continue.
        """
    }

    public static func splitIntoTitle(_ count: Int) -> String {
        "Split Into \(count) Parts"
    }

    public static func recordParts(wordLists: [[String]], checksumWord: String) -> String {
        let seedLen = wordLists.first?.count ?? 0
        var msg = "\(wordLists.count) lists of \(seedLen)-words each:"
        for (index, words) in wordLists.enumerated() {
            msg += "\n\nPart \(Character(UnicodeScalar(65 + index)!)):\n"
            msg += SeedXOR.renderPartWords(words)
        }
        msg += "\n\nThe correctly reconstructed seed phrase will have this final word, which we recommend recording:\n\n"
        msg += "\(seedLen): \(checksumWord)\n\n"
        msg += "Please check and double check your notes. There will be a test! "
        return msg
    }

    public static let quizPassed = "Quiz Passed!\n\nYou have confirmed the details of the new split."
    public static let stopAndForget = "Stop and forget those words?"
    /// Firmware `ux_dramatic_pause('Generating...', 2)` before the split.
    public static let generatingPause = "Generating..."
    /// Firmware `show_n_parts` `title="Record these:"`.
    public static let recordPartsTitle = "Record these:"

    public static func quizTitle(partIndex: Int, wordNumber: Int) -> String {
        let letter = Character(UnicodeScalar(65 + partIndex)!)
        return "Word \(letter)\(wordNumber) is?"
    }

    public static func restoreIntro(ok: String = Self.ok) -> String {
        """
        To import a seed split using XOR, you must import all the parts. It does not matter the order (A/B/C or C/A/B) and the Coldcard cannot determine when you have all the parts. You may stop at any time and you will have a valid wallet. Combined seed parts have to be equal length.

        Press \(ok) for 24 words XOR, press (1) for 12 words XOR, or press (2) for 18 words XOR.
        """
    }

    public static func restoreExistingSeed(canIncludeCurrent: Bool, ok: String = Self.ok) -> String {
        var msg = "Since you have a seed already on this Coldcard, the reconstructed XOR seed will be temporary and not saved. Wipe the seed first if you want to commit the new value into the secure element."
        if canIncludeCurrent {
            msg += "\n\nPress (1) to include this Coldcard's seed words into the XOR seed set, or \(ok) to continue without."
        }
        return msg
    }

    public static func restoreVault(matchingCount: Int, ok: String = Self.ok) -> String {
        "Seed Vault is enabled. \(matchingCount) stored seeds have suitable type and length.\n\nPress (2) to add from Seed Vault and then (1) to select seeds, press \(ok) to continue normally."
    }

    public static func restoreProgress(
        partsEntered: Int,
        wordCount: Int,
        checksumWord: String?,
        zeroWarning: Bool
    ) -> String {
        var msg = "You've entered \(partsEntered) parts so far.\n\n"
        if partsEntered >= 2, let checksumWord {
            msg += "If you stop now, the \(wordCount)th word of the XOR-combined seed phrase will be:\n\n"
            msg += "\(wordCount): \(checksumWord)\n\n"
        }
        if zeroWarning {
            msg += "ZERO WARNING\nProvided seed works out to all zeros right now. You may have doubled a part or made some other mistake.\n\n"
        }
        msg += "Press (1) to enter next list of words."
        if partsEntered >= 2 {
            msg += " Or (2) if done with all words."
        }
        return msg
    }

    public static func ephemeralOrigin(parts: Int, checksumWord: String) -> String {
        "SeedXOR(\(parts) parts, check: \"\(checksumWord)\")"
    }

    public static func vaultPickLabel(vaultIndex: Int, fingerprint: String) -> String {
        let xfp = fingerprint.filter(\.isHexDigit)
        return String(format: "%2d: [%@]", vaultIndex, xfp)
    }
}

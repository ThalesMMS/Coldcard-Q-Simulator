import Foundation
import Testing
@testable import ColdcardCore

@Test func mixDiceStoryTitleIsDiceRollsNotWarning() {
    #expect(SeedCreation.diceMixStoryTitle == "Dice Rolls")
    #expect(SeedCreation.diceOnlyWarningTitle == "WARNING")
    #expect(SeedCreation.storyTitle(mixWithTRNG: true) == "Dice Rolls")
    #expect(SeedCreation.storyTitle(mixWithTRNG: false) == "WARNING")
}

@Test func mashCollectPromptIsPressRandomKeys() {
    #expect(SeedCreation.mashPrompt == "Press random keys")
    #expect(!SeedCreation.mashPrompt.contains("Timing is the entropy"))
    #expect(SeedCreation.entropyLine3(kind: .mash, count: 0) == "Press random keys")
    #expect(SeedCreation.entropyLine3(kind: .mash, count: 65) == "Keep mashing or ENTER when done")
}

@Test func mixEntropyLinesHaveNoRunningHash() {
    #expect(SeedCreation.entropyLine2(kind: .diceMix, count: 7) == "7 / 50 rolls")
    #expect(SeedCreation.entropyLine3(kind: .diceMix, count: 7) == "Enter each roll: 1-6")
    #expect(SeedCreation.entropyLine3(kind: .diceMix, count: 50) == "Keep rolling or ENTER when done")
    #expect(SeedCreation.entropyLine2(kind: .coin, count: 3) == "3 / 128 flips")
    #expect(SeedCreation.showsRunningHash(mixWithTRNG: true) == false)
}

@Test func enterBelowThresholdIsIgnored() {
    #expect(!SeedCreation.canFinishMash(count: 64))
    #expect(SeedCreation.canFinishMash(count: 65))
    #expect(!SeedCreation.canFinishCoin(count: 127))
    #expect(SeedCreation.canFinishCoin(count: 128))
    #expect(!SeedCreation.canFinishDiceMix(count: 49))
    #expect(SeedCreation.canFinishDiceMix(count: 50))
    #expect(SeedCreation.belowThresholdMessage(kind: .mash, count: 10) == nil)
    #expect(SeedCreation.belowThresholdMessage(kind: .coin, count: 10) == nil)
    #expect(SeedCreation.belowThresholdMessage(kind: .diceMix, count: 10) == nil)
}

@Test func biasCheckIsNotGatedOnTenRolls() {
    #expect(SeedCreation.diceRollsAreBiased("1"))
    #expect(SeedCreation.diceRollsAreBiased("111111111"))
    #expect(!SeedCreation.diceRollsAreBiased(""))
    #expect(!SeedCreation.diceRollsAreBiased(String(repeating: "123456", count: 17)))
    #expect(SeedCreation.diceRollsAreBiased(String(repeating: "1", count: 99)))
}

@Test func mixBiasReturnsToMethodMenuKeepingBaseSeed() {
    #expect(SeedCreation.mixBiasAction == .returnToMethodMenu)
    #expect(SeedCreation.diceOnlyBiasAction == .abort)
    #expect(SeedCreation.badDiceMessage == "Distribution of dice rolls is not random. Some numbers occurred more than 30% of the time.")
    #expect(SeedCreation.badCoinMessage == "Distribution of coin flips is not random. Heads or tails occurred more than 65% of the time.")
    #expect(SeedCreation.biasStoryTitle.isEmpty)
}

@Test func entropyPausesMatchFirmware() {
    #expect(SeedCreation.generatingPauseTitle == "Generating...")
    #expect(SeedCreation.generatingPauseSeconds == 3)
    #expect(SeedCreation.waitPauseTitle == "Wait...")
    #expect(SeedCreation.waitPauseSeconds == 1)
}

@Test func notEnoughDiceCopyBelongsOnlyToDiceOnlyPath() {
    #expect(SeedCreation.notEnoughDiceApplies(mixWithTRNG: false, enforce: true))
    #expect(!SeedCreation.notEnoughDiceApplies(mixWithTRNG: true, enforce: true))
    let body = SeedCreation.diceOnlyNotEnough(count: 12, bits: 128, words: 12, needed: 50)
    #expect(body.hasPrefix("Not enough dice rolls!!!"))
    #expect(SeedCreation.diceOnlyCancelExits(count: 9))
    #expect(!SeedCreation.diceOnlyCancelExits(count: 10))
}

@Test func diceOnlyHashStartsFromEmptyAndSplitsAt32() {
    let empty = SeedCreation.diceRunningHashHex(rolls: "")
    #expect(empty == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    let lines = SeedCreation.diceRunningHashLines(hex: empty)
    #expect(lines.top == "e3b0c44298fc1c149afbf4c8996fb924-")
    #expect(lines.bottom == "27ae41e4649b934ca495991b7852b855")
    #expect(SeedCreation.diceOnlyScreenTitle.isEmpty)
    #expect(SeedCreation.showsRunningHash(mixWithTRNG: false))
}

@Test func ephemeralOriginStringsMatchSeedPy() {
    #expect(SeedCreation.ephemeralOrigin(diceOnly: true) == "Dice")
    #expect(SeedCreation.ephemeralOrigin(diceOnly: false) == "Generated Words")
    #expect(SeedCreation.importedOrigin == "Imported")
}

@Test func skipQuizIsStoryHintNotAButton() {
    #expect(SeedCreation.skipQuizHint == "Press (6) to skip word quiz. ")
    #expect(!SeedCreation.skipQuizHint.contains("SKIP QUIZ"))
}

@Test func confirmationsUseDefaultSureTitle() {
    #expect(SeedCreation.confirmTitle == "Are you SURE ?!?")
}

@Test func quizLayoutIsChoicesThenPromptThenGiveUp() {
    let body = SeedCreation.quizBody(choices: ["ability", "abandon", "zoo"])
    #expect(body.hasPrefix(" 1: ability\n 2: abandon\n 3: zoo"))
    #expect(body.contains("\n\nWhich word is right?\n\n"))
    #expect(body.contains("CANCEL to give up, ENTER to see all the words again."))
    #expect(SeedCreation.wrongAnswerKeepsSameChoices)
}

@Test func viewSeedWordsWithPassphraseShowsXprv() throws {
    let mnemonic = try BIP39Mnemonic(entropy: Data(repeating: 0, count: 16))
    let key = try HDKey(seed: mnemonic.seed(passphrase: "test"), network: .testnet)
    let xprv = try key.serializePrivate()
    let shown = SeedCreation.viewSeedWords(passphraseActive: true, xprv: xprv, words: mnemonic.words)
    #expect(shown.title == "Extended Private Key")
    #expect(shown.body.hasPrefix("BIP-39 Passphrase in effect\n\n"))
    #expect(shown.body.contains(xprv))
    #expect(!shown.body.contains("Seed words"))
    #expect(!shown.body.contains("test"))
}

@Test func seedQRCaptionIsExact() {
    #expect(SeedCreation.seedQRCaption == "SeedQR")
}

@Test func wordEntryTitlesMatchContext() {
    #expect(SeedCreation.wordEntryTitle(.importMaster) == "Enter Seed Words")
    #expect(SeedCreation.wordEntryTitle(.importEphemeral) == "Ephemeral Seed Words")
    #expect(SeedCreation.wordEntryTitle(.xorPart(index: 0)) == "Part A Words")
    #expect(SeedCreation.wordEntryTitle(.xorPart(index: 1)) == "Part B Words")
    #expect(SeedCreation.wordEntryTitle(.backupPassword) == "Enter Password:")
    #expect(!SeedCreation.hasChecksum(.backupPassword))
    #expect(SeedCreation.hasChecksum(.importMaster))
}

@Test func wordEntryDonePromptsAndFinalWordErrors() {
    #expect(SeedCreation.donePrompt(hasChecksum: true) == "Valid words! Press ENTER.")
    #expect(SeedCreation.donePrompt(hasChecksum: false) == "Press ENTER if all done.")
    let eight = ["ability", "able", "about", "above", "absent", "absorb", "abstract", "absurd"]
    #expect(SeedCreation.finalWordError(prefix: "z", candidates: eight) == "Final word starts with: a")
    #expect(SeedCreation.finalWordError(prefix: "z", candidates: ["about"]) == "Final word cannot start with: z")
    #expect(SeedCreation.finalWordError(prefix: "ab", candidates: eight) == nil)
    #expect(SeedCreation.inventedProactiveHint(filledCount: 0, prefix: "", complete: false) == "")
    #expect(SeedCreation.nextKeyHint(matches: ["ability", "able", "about"], prefix: "") == "Next key: a")
}

@Test func wordGridIsColumnMajorThreeColumnsFor18And24() {
    #expect(SeedCreation.columnCount(wordCount: 18) == 3)
    #expect(SeedCreation.columnCount(wordCount: 24) == 3)
    #expect(SeedCreation.columnCount(wordCount: 12) == 2)
    #expect(SeedCreation.gridIndex(row: 0, column: 1, wordCount: 24) == 8)
    #expect(SeedCreation.drawCell(index: 0, word: "abandon", count: 24) == "1:abandon")
    #expect(SeedCreation.drawCell(index: 8, word: "ability", count: 24) == " 9:ability")
    #expect(SeedCreation.drawCell(index: 0, word: "abandon", count: 12) == " 1: abandon")
}

@Test func wordEntryCapsAtEightWithOutlineCursor() {
    #expect(SeedCreation.maxWordLength == 8)
    #expect(SeedCreation.clampPrefix("abcdefghijk") == "abcdefgh")
    #expect(SeedCreation.cursor(prefixLength: 3).style == .solid)
    #expect(SeedCreation.cursor(prefixLength: 8).style == .outline)
}

@Test func wordEntryQRRejectsNonWordsAndRestoresChecksum() {
    #expect(SeedCreation.mustBeSeedWords(not: "xprv") == "Must be seed words, not xprv")
    #expect(SeedCreation.unableToDecodeSecret == "Unable to decode as secret")
    #expect(SeedCreation.wrongSeedLength(expected: 12, actual: 24) == "Must be seed of length 12, not 24")
    let imported = ["abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                    "abandon", "abandon", "abandon", "abandon", "abandon", "about"]
    #expect(SeedCreation.importedChecksumWords(imported) == ["about"])
}

@Test func cancelWithTwoWordsConfirmsAbort() {
    #expect(SeedCreation.confirmAbortWordEntry(filledCount: 2))
    #expect(!SeedCreation.confirmAbortWordEntry(filledCount: 1))
    #expect(SeedCreation.wordEntryAbort == "Everything you've entered will be lost.")
}

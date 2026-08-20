import Testing
@testable import ColdcardCore

@Test func pinCancelOnEmptyPrefixStaysOnPIN() {
    #expect(LoginUX.pinCancelAction(currentPart: "", hasPrefix: false) == .stay)
}

@Test func pinCancelOnEmptySuffixResetsToPrefix() {
    #expect(LoginUX.pinCancelAction(currentPart: "", hasPrefix: true) == .resetToPrefix)
}

@Test func pinCancelWithDigitsClearsCurrentPart() {
    #expect(LoginUX.pinCancelAction(currentPart: "12", hasPrefix: false) == .clearCurrentPart)
    #expect(LoginUX.pinCancelAction(currentPart: "99", hasPrefix: true) == .clearCurrentPart)
}

@Test func killKeyMatchesCaseInsensitivelyAndIgnoresEmpty() {
    #expect(LoginUX.matchesKillKey("a", killKey: "A"))
    #expect(LoginUX.matchesKillKey("Z", killKey: "Z"))
    #expect(LoginUX.matchesKillKey("/", killKey: "/"))
    #expect(!LoginUX.matchesKillKey("A", killKey: ""))
    #expect(!LoginUX.matchesKillKey("B", killKey: "A"))
}

@Test func scrambledDigitUsesMapLikeLoginPy() {
    let map: [Character: Character] = ["1": "7", "2": "0", "0": "4"]
    #expect(LoginUX.scrambledDigit("1", map: map) == "7")
    #expect(LoginUX.scrambledDigit("2", map: map) == "0")
    #expect(LoginUX.scrambledDigit("9", map: map) == "9")
}

@Test func pinCursorIsOutlineOnSixthDigitOnly() {
    #expect(PINEntryChrome.cursor(digitCount: 6) == PINCursor(index: 5, style: .outline))
}

@Test func pinCursorIsSolidBeforeSixthDigit() {
    #expect(PINEntryChrome.cursor(digitCount: 0) == PINCursor(index: 0, style: .solid))
    #expect(PINEntryChrome.cursor(digitCount: 1) == PINCursor(index: 1, style: .solid))
    #expect(PINEntryChrome.cursor(digitCount: 5) == PINCursor(index: 5, style: .solid))
}

@Test func pinScrambleMapMatchesUxShowPinTwoLineLayout() {
    // `shuffle_keys`: randomize[i] is the glyph for physical key i (`login.py`).
    var map: [Character: Character] = [:]
    for (physical, shown) in zip(Array("0123456789"), Array("9876543210")) {
        map[physical] = shown
    }
    let rows = PINEntryChrome.scrambleMap(from: map)
    #expect(rows.invertedDigits == "  8  7  6  5  4  3  2  1  0  9  ")
    #expect(rows.keyLegend == "↳ 1  2  3  4  5  6  7  8  9  0")
    #expect(rows.invertedDigits.count == 32)
    #expect(rows.topRow.count == LCDDisplay.charsW)
    #expect(rows.bottomRow.count == LCDDisplay.charsW)
    #expect(rows.topRow == "   8  7  6  5  4  3  2  1  0  9   ")
    #expect(rows.bottomRow == " ↳ 1  2  3  4  5  6  7  8  9  0   ")
    #expect(rows.originX == 1)
    #expect(rows.invertColumns == 1..<33)
}

@Test func pinScrambleIdentityMapUses123To0Order() {
    let rows = PINEntryChrome.scrambleMap(from: [:])
    #expect(rows.invertedDigits == "  1  2  3  4  5  6  7  8  9  0  ")
    #expect(rows.keyLegend == "↳ 1  2  3  4  5  6  7  8  9  0")
}

@Test func killKeyChooserMatchesChoosersPyQList() {
    let letters = (0..<26).map { String(Character(UnicodeScalar(65 + $0)!)) }
    #expect(LoginUX.killKeyChoices == ["Disable"] + letters + ["'", ",", ".", "/"])
}

@Test func scrambleChooserMatchesChoosersPy() {
    #expect(LoginUX.scrambleChooserChoices == ["Normal", "Scramble Keys"])
}

@Test func killKeyAppliesDuringNicknameAndEveryPINKey() {
    #expect(LoginUX.killKeyApplies(in: .nicknameSplash))
    #expect(LoginUX.killKeyApplies(in: .pinEntry))
    #expect(LoginUX.killKeyApplies(in: .loginCountdown))
    #expect(!LoginUX.killKeyApplies(in: .pinSetting))
    #expect(!LoginUX.killKeyApplies(in: .other))
}

@Test func suffixDeleteOnEmptyPartReturnsToPrefixDigits() {
    let suffix = PINEntryState(prefix: "123", current: "")
    #expect(LoginUX.applyDelete(suffix) == PINEntryState(prefix: nil, current: "123"))
}

@Test func suffixDeleteRemovesLastDigitOfCurrentPart() {
    let suffix = PINEntryState(prefix: "12", current: "99")
    #expect(LoginUX.applyDelete(suffix) == PINEntryState(prefix: "12", current: "9"))
}

@Test func pinClearBlanksOnlyTheCurrentPart() {
    let suffix = PINEntryState(prefix: "12", current: "99")
    #expect(LoginUX.applyClear(suffix) == PINEntryState(prefix: "12", current: ""))
}

@Test func qDoesNotReshuffleAfterPrefix() {
    #expect(LoginUX.shouldShuffleKeypad(randomize: true, startingInteract: true, acceptedPrefix: false, isQwerty: true))
    #expect(!LoginUX.shouldShuffleKeypad(randomize: true, startingInteract: false, acceptedPrefix: true, isQwerty: true))
    #expect(LoginUX.shouldShuffleKeypad(randomize: true, startingInteract: false, acceptedPrefix: true, isQwerty: false))
    #expect(!LoginUX.shouldShuffleKeypad(randomize: false, startingInteract: true, acceptedPrefix: false, isQwerty: true))
}

@Test func loginCountdownCopyAndDelayMatchUxQ1() {
    #expect(LoginUX.countdownTitle == "Login countdown in effect.")
    #expect(LoginUX.countdownMustWait == "Must wait:")
    #expect(LoginUX.countdownDelayText(seconds: 5) == " 0m  5s")
    #expect(LoginUX.countdownDelayText(seconds: 300) == " 5m  0s")
    #expect(LoginUX.countdownDelayText(seconds: 3600) == " 1h  0m  0s")
    #expect(LoginUX.countdownDelayText(seconds: 12 * 3600) == "12h  0m  0s")
    #expect(LoginUX.countdownDelayText(seconds: 12 * 3600 + 1) == "12.0 hours")
}

@Test func confirmPINValueIsFooterNotTitle() {
    #expect(LoginUX.confirmPINFooter == "Confirm PIN value")
    #expect(LoginUX.pinEntryTitle(isConfirmation: true, subtitle: nil, editingPrefix: true) == LoginUX.pinPrefixPrompt)
    #expect(LoginUX.pinEntryTitle(isConfirmation: true, subtitle: nil, editingPrefix: false) == LoginUX.pinSuffixPrompt)
    #expect(LoginUX.pinEntryTitle(isConfirmation: true, subtitle: "New Main PIN", editingPrefix: true) == "New Main PIN")
}

@Test func brickStoryUsesNumFailsNotAConstantThirteen() {
    let body = LoginUX.brickStory(numFails: 4)
    #expect(LoginUX.brickTitle == "I Am Brick!")
    #expect(LoginUX.brickEscapeKey == "6")
    #expect(body.contains("After 4 failed PIN attempts"))
    #expect(!body.contains("After 13 failed PIN attempts"))
    #expect(body.contains(LoginUX.brickCalculatorLine))
    #expect(!body.localizedCaseInsensitiveContains("wipe"))
}

@Test func brickAnyKeyExceptSixEntersCalculator() {
    #expect(!LoginUX.brickKeyEntersCalculator("6"))
    #expect(LoginUX.brickKeyEntersCalculator("5"))
    #expect(LoginUX.brickKeyEntersCalculator("\r"))
    #expect(LoginUX.brickKeyEntersCalculator("a"))
}

@Test func choosePINStoryKeepsFirmwareHardLineBreak() {
    #expect(LoginUX.choosePINStory.contains("Your new PIN protects access to \nthis Coldcard device"))
}

@Test func nicknamePromptMatchesActionsPy() {
    #expect(LoginUX.nicknamePrompt == "Enter Nickname")
}

@Test func calculatorLoginShowsNicknameBeforePIN() {
    #expect(LoginUX.bootShowsNickname(beforeCalculatorLogin: true, nickname: "Office"))
    #expect(!LoginUX.bootShowsNickname(beforeCalculatorLogin: true, nickname: ""))
    #expect(LoginUX.bootShowsNickname(beforeCalculatorLogin: false, nickname: "Office"))
}

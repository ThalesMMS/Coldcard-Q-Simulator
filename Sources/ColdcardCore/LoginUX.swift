import Foundation

/// Firmware `shared/login.py` PIN cancel, scramble, and kill-key matching (Q).
public enum LoginPINCancelAction: Equatable, Sendable {
    /// Empty prefix CANCEL: `interact()` returns None and `try_login` loops.
    case stay
    /// Empty suffix CANCEL: `reset()` back to the prefix prompt.
    case resetToPrefix
    /// CANCEL with digits: clear the current part (Q has a Backspace key).
    case clearCurrentPart
}

/// Current PIN part plus optional accepted prefix (`login.py` `self.pin` / `self.pin_prefix`).
public struct PINEntryState: Equatable, Sendable {
    public var prefix: String?
    public var current: String

    public init(prefix: String?, current: String) {
        self.prefix = prefix
        self.current = current
    }
}

/// Screens where Q `kbtn` is live (`login.py` `interact`, `actions.show_nickname`).
public enum LoginKillContext: Equatable, Sendable {
    case nicknameSplash
    case pinEntry
    case loginCountdown
    case pinSetting
    case other
}

public enum LoginUX {
    /// Q `choosers.kill_key_chooser`: `['Disable'] + A…Z + ["'", ",", ".", "/"]`.
    public static let killKeyChoices: [String] = {
        let letters = (0..<26).map { String(Character(UnicodeScalar(65 + $0)!)) }
        return ["Disable"] + letters + ["'", ",", ".", "/"]
    }()

    /// Q `choosers.scramble_keypad_chooser`.
    public static let scrambleChooserChoices = ["Normal", "Scramble Keys"]

    public static let pinPrefixPrompt = "Enter first part of PIN"
    public static let pinSuffixPrompt = "Enter second part of PIN"
    /// `ux_q1.ux_show_pin` footer when `is_confirmation`, not the invert title.
    public static let confirmPINFooter = "Confirm PIN value"
    public static let nicknamePrompt = "Enter Nickname"
    public static let countdownTitle = "Login countdown in effect."
    public static let countdownMustWait = "Must wait:"
    public static let brickTitle = "I Am Brick!"
    public static let brickEscapeKey = "6"
    public static let brickCalculatorLine = "Calculator mode starts now."

    /// Firmware `actions.initial_pin_setup` Choose PIN story (hard break after `to `).
    public static let choosePINStory = """
    Pick the main wallet's PIN code now. Be more clever, but an example:

    123-4567

    It has two parts: prefix (123-) and suffix (-4567). Each part must be between 2 to 6 digits long. Total length can be as long as 12 digits.

    The prefix part determines the anti-phishing words you will see each time you login.

    Your new PIN protects access to 
    this Coldcard device and is not a factor in the wallet's seed words or private keys.

    THERE IS ABSOLUTELY NO WAY TO RECOVER A FORGOTTEN PIN! Write it down.
    """

    /// Q `KEY_CANCEL` while entering a PIN part (`login.py` `LoginUX.interact`).
    public static func pinCancelAction(currentPart: String, hasPrefix: Bool) -> LoginPINCancelAction {
        if currentPart.isEmpty {
            return hasPrefix ? .resetToPrefix : .stay
        }
        return .clearCurrentPart
    }

    /// Q `KEY_DELETE` / `KEY_LEFT`: empty suffix returns to editing the prefix digits.
    public static func applyDelete(_ state: PINEntryState) -> PINEntryState {
        var next = state
        if !next.current.isEmpty {
            next.current.removeLast()
            return next
        }
        if let prefix = next.prefix {
            next.current = prefix
            next.prefix = nil
        }
        return next
    }

    /// Q `KEY_CLEAR`: blank the current PIN part only.
    public static func applyClear(_ state: PINEntryState) -> PINEntryState {
        var next = state
        next.current = ""
        return next
    }

    /// Q compares `ch.upper()` to stored `kbtn` (`login.py`, `actions.show_nickname`).
    public static func matchesKillKey(_ value: String, killKey: String) -> Bool {
        guard !killKey.isEmpty else { return false }
        return value.uppercased() == killKey.uppercased()
    }

    /// Kill key at nickname splash and every PIN-entry character; not while setting a PIN.
    public static func killKeyApplies(in context: LoginKillContext) -> Bool {
        switch context {
        case .nicknameSplash, .pinEntry, .loginCountdown: true
        case .pinSetting, .other: false
        }
    }

    /// Stored `kbtn` is empty when the chooser is Disable.
    public static func storedKillKey(choice: String) -> String {
        choice == "Disable" ? "" : choice
    }

    /// Physical digit key remapped through the shuffled keypad (`login.py` `self.randomize[int(ch)]`).
    public static func scrambledDigit(_ raw: Character, map: [Character: Character]) -> Character {
        map[raw] ?? raw
    }

    /// Q shuffles once per `interact()`; Mk4 also shuffles after the prefix is accepted.
    public static func shouldShuffleKeypad(
        randomize: Bool, startingInteract: Bool, acceptedPrefix: Bool, isQwerty: Bool
    ) -> Bool {
        guard randomize else { return false }
        if startingInteract { return true }
        if acceptedPrefix { return !isQwerty }
        return false
    }

    /// Confirm PIN is a footer (`ux_q1.py`); the title stays the part prompt or subtitle.
    public static func pinEntryTitle(isConfirmation: Bool, subtitle: String?, editingPrefix: Bool) -> String {
        _ = isConfirmation
        if let subtitle, !subtitle.isEmpty { return subtitle }
        return editingPrefix ? pinPrefixPrompt : pinSuffixPrompt
    }

    /// `ux_q1.ux_login_countdown`: `pretty_delay` when `sec > 12*3600`, else `pretty_short_delay`.
    public static func countdownDelayText(seconds: Int) -> String {
        if seconds > 12 * 3600 {
            return prettyDelay(seconds)
        }
        return prettyShortDelay(seconds)
    }

    /// `login.py` `we_are_ewaste`: `num_fails` in the story, not a constant 13.
    public static func brickStory(numFails: Int) -> String {
        """
        After \(numFails) failed PIN attempts this Coldcard is locked forever. By design, there is no way to reset or recover the secure element, and its contents are now forever inaccessible.

        \(brickCalculatorLine)
        """
    }

    /// `ux_show_story(..., escape='6')`: any other key enters the calculator REPL.
    public static func brickKeyEntersCalculator(_ key: String) -> Bool {
        key != brickEscapeKey
    }

    /// `start_login_sequence` shows nickname before calculator login / PIN.
    public static func bootShowsNickname(beforeCalculatorLogin: Bool, nickname: String) -> Bool {
        _ = beforeCalculatorLogin
        return !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func prettyDelay(_ n: Int) -> String {
        if n < 120 { return "\(n) seconds" }
        let minutes = Double(n) / 60
        if minutes < 60 { return "\(Int(minutes)) minutes" }
        let hours = minutes / 60
        if hours < 48 { return String(format: "%.1f hours", hours) }
        return String(format: "about %.1f days", hours / 24)
    }

    private static func prettyShortDelay(_ sec: Int) -> String {
        if sec >= 3600 {
            return String(format: "%2dh %2dm %2ds", sec / 3600, (sec / 60) % 60, sec % 60)
        }
        return String(format: "%2dm %2ds", (sec / 60) % 60, sec % 60)
    }
}

/// Q `ux_show_pin` cursor: `CURSOR_OUTLINE` on the 6th digit, `CURSOR_SOLID` otherwise.
public struct PINCursor: Equatable, Sendable {
    public var index: Int
    public var style: Style

    public enum Style: Equatable, Sendable {
        case solid
        case outline
    }

    public init(index: Int, style: Style) {
        self.index = index
        self.style = style
    }
}

/// Two-line scramble map from `ux_q1.ux_show_pin` (`randomize`, 34 columns, origin x=1).
public struct PINScrambleMap: Equatable, Sendable {
    /// `'  ' + '  '.join(randomize[1:]) + '  ' + randomize[0] + '  '` (invert=1).
    public var invertedDigits: String
    /// `'↳ 1  2  3  4  5  6  7  8  9  0'`.
    public var keyLegend: String
    /// 34-column row 0 with the inverted payload at column 1.
    public var topRow: String
    /// 34-column row 1 with the legend at column 1.
    public var bottomRow: String
    public var originX: Int
    public var invertColumns: Range<Int>
}

/// Firmware `shared/ux_q1.py` `ux_show_pin` LCD chrome (cursor + scramble map).
public enum PINEntryChrome {
    public static let maxPartLen = 6

    /// `len(pin) == 6` → outline on `cur_x-1`; else solid at `cur_x`.
    public static func cursor(digitCount: Int) -> PINCursor {
        let count = min(max(0, digitCount), maxPartLen)
        if count == maxPartLen {
            return PINCursor(index: maxPartLen - 1, style: .outline)
        }
        return PINCursor(index: count, style: .solid)
    }

    /// Physical keys `1…9 0` under shuffled digits; two-space join; pad to `CHARS_W`.
    public static func scrambleMap(from map: [Character: Character]) -> PINScrambleMap {
        let physical = Array("1234567890")
        let shown = physical.map { String(LoginUX.scrambledDigit($0, map: map)) }
        let invertedDigits = "  " + shown.joined(separator: "  ") + "  "
        let keyLegend = "↳ 1  2  3  4  5  6  7  8  9  0"
        let originX = 1
        return PINScrambleMap(
            invertedDigits: invertedDigits,
            keyLegend: keyLegend,
            topRow: padRow(invertedDigits, originX: originX),
            bottomRow: padRow(keyLegend, originX: originX),
            originX: originX,
            invertColumns: originX..<(originX + invertedDigits.count)
        )
    }

    private static func padRow(_ content: String, originX: Int) -> String {
        var cells = Array(repeating: Character(" "), count: LCDDisplay.charsW)
        for (offset, ch) in content.enumerated() {
            let column = originX + offset
            guard column >= 0, column < LCDDisplay.charsW else { continue }
            cells[column] = ch
        }
        return String(cells)
    }
}

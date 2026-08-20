import Foundation

/// Firmware `shared/calc.py` login calculator (Q REPL).
public enum CalculatorLogin {
    /// `ux_input_text(..., max_len=34-3)`.
    public static let maxInputLength = 31
    /// `NUM_LINES = 7`.
    public static let windowLines = 7
    public static let helpText = "Commands: sha256, sha512, ripemd, rand, cls, help"

    /// Initial `lines` in `login_repl` (`calc.py`).
    public static let exampleLines = [
        "",
        "Example Commands:",
        ">> 23 + 55 / 22",
        ">> 1.020 * 45.88",
        ">> sha256('some message')",
        ">> cls    # clear screen",
        ">> help",
    ]

    /// `re_pin` plus `len(ln) <= 13`.
    public static func normalizedPIN(_ line: String) -> String? {
        guard line.count <= 13, let match = line.wholeMatch(of: /^(\d\d+)[-_ ](\d\d+)$/) else {
            return nil
        }
        return "\(match.output.1)-\(match.output.2)"
    }

    /// `re_prefix` plus `len(ln) <= 7`. Space is not a prefix separator.
    public static func prefixDigits(_ line: String) -> String? {
        guard line.count <= 7, let match = line.wholeMatch(of: /^(\d\d+)[-_]$/) else {
            return nil
        }
        return String(match.output.1)
    }

    /// `'%-7d          # %d tries remain'`.
    public static func triesRemainLine(value: Int, remaining: Int) -> String {
        String(format: "%-7d          # %d tries remain", value, remaining)
    }

    public static func prefixTuple(_ word1: String, _ word2: String) -> String {
        "('\(word1)', '\(word2)')"
    }

    public static func wrapAnswer(_ text: String) -> [String] {
        LCDDisplay.wordWrap(text, width: LCDDisplay.charsW)
    }

    public static func trimWindow(_ lines: [String]) -> [String] {
        if lines.count <= windowLines { return lines }
        return Array(lines.suffix(windowLines))
    }
}

public enum CalculatorSessionResult: Equatable, Sendable {
    case login(pin: String)
    case updated
}

/// One `login_repl` loop body, minus the LCD busy bar.
public struct CalculatorSession: Equatable, Sendable {
    public var lines: [String]
    public var attemptsLeft: Int
    public var allowPINLogin: Bool
    public var allowPrefixWords: Bool

    public init(
        lines: [String] = CalculatorLogin.exampleLines,
        attemptsLeft: Int = 13,
        allowPINLogin: Bool = false,
        allowPrefixWords: Bool = false
    ) {
        self.lines = lines
        self.attemptsLeft = attemptsLeft
        self.allowPINLogin = allowPINLogin
        self.allowPrefixWords = allowPrefixWords
    }

    @discardableResult
    public mutating func submit(
        _ line: String,
        pinOK: ((String) -> Bool)? = nil,
        prefixWords: ((String) -> (String, String)?)? = nil,
        randomBytes: ((Int) throws -> Data)? = nil
    ) -> CalculatorSessionResult {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= CalculatorLogin.maxInputLength else { return .updated }
        lines.append(">> \(trimmed)")
        let random = randomBytes ?? { Data(count: $0) }
        do {
            if trimmed == "help" || trimmed == "cls" || trimmed == "rand" {
                switch trimmed {
                case "cls":
                    lines = []
                case "help":
                    appendAnswer(CalculatorLogin.helpText)
                default:
                    appendAnswer(try random(32).hexString)
                }
            } else if allowPINLogin, attemptsLeft > 0, let pin = CalculatorLogin.normalizedPIN(trimmed) {
                if pinOK?(pin) == true {
                    lines = CalculatorLogin.trimWindow(lines)
                    return .login(pin: pin)
                }
                attemptsLeft -= 1
                if attemptsLeft == 0 { allowPINLogin = false }
                do {
                    let value = try ExpressionEvaluator.integerEval(trimmed)
                    appendAnswer(CalculatorLogin.triesRemainLine(value: value, remaining: attemptsLeft))
                } catch {
                    appendAnswer(String(describing: error))
                }
            } else if allowPrefixWords, let prefix = CalculatorLogin.prefixDigits(trimmed) {
                if let words = prefixWords?(prefix) {
                    appendAnswer(CalculatorLogin.prefixTuple(words.0, words.1))
                }
            } else {
                var evaluator = ExpressionEvaluator(trimmed)
                switch try evaluator.evaluateCommand(randomBytes: random) {
                case .clear:
                    lines = []
                case .silent:
                    break
                case .text(let text):
                    appendAnswer(text)
                case .number(let value):
                    appendAnswer(ExpressionEvaluator.pythonRepr(value, isFloat: evaluator.usedTrueDivision))
                }
            }
        } catch {
            appendAnswer(String(describing: error))
        }
        lines = CalculatorLogin.trimWindow(lines)
        return .updated
    }

    private mutating func appendAnswer(_ answer: String) {
        lines.append(contentsOf: CalculatorLogin.wrapAnswer(answer))
    }
}

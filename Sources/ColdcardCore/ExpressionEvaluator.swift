import Foundation

public enum ExpressionError: Error, CustomStringConvertible {
    case invalidExpression, divisionByZero, nameError(String)

    public var description: String {
        switch self {
        case .invalidExpression: "invalid syntax"
        case .divisionByZero: "division by zero"
        case .nameError(let name): "name '\(name)' is not defined"
        }
    }
}

public enum CalculatorOutput: Equatable, Sendable {
    case number(Double)
    case text(String)
    case clear
    case silent
}

/// Restricted evaluator for firmware `shared/calc.py` (`eval` plus toy builtins).
public struct ExpressionEvaluator {
    public static let helpText = CalculatorLogin.helpText

    private static let blacklist = [
        "import", "__", "exec", "locals", "globals", "eval", "input",
        "getattr", "setattr", "delattr", "open", "execfile", "compile"
    ]

    private var characters: [Character]
    private var index = 0
    public private(set) var usedTrueDivision = false
    private var randomBytes: (Int) throws -> Data = { Data(count: $0) }

    public init(_ expression: String) {
        characters = Array(expression)
    }

    /// Python `repr` for calculator answers (`calc.py` uses `repr` unless the value is `str`).
    public static func pythonRepr(_ value: Double, isFloat: Bool) -> String {
        if !isFloat {
            if value.isFinite, value == value.rounded() {
                return String(format: "%.0f", value)
            }
        }
        if value.isNaN { return "nan" }
        if value.isInfinite { return value > 0 ? "inf" : "-inf" }
        if value == 0 { return value.sign == .minus ? "-0.0" : "0.0" }
        if value.isFinite, value == value.rounded(), abs(value) < 1e16 {
            return String(format: "%.1f", value)
        }
        var text = String(value)
        if !text.contains("."), !text.lowercased().contains("e") {
            text += ".0"
        }
        return text
    }

    public static func integerEval(_ expression: String) throws -> Int {
        var evaluator = ExpressionEvaluator(expression)
        switch try evaluator.evaluateCommand() {
        case .text(let text):
            if let value = Int(text) { return value }
            if let value = Double(text), value == value.rounded() {
                return Int(value)
            }
            throw ExpressionError.invalidExpression
        case .number(let value):
            guard value.isFinite, value == value.rounded() else { throw ExpressionError.invalidExpression }
            return Int(value)
        default:
            throw ExpressionError.invalidExpression
        }
    }

    public mutating func evaluate() throws -> Double {
        try rejectBlacklist()
        let value = try parseOr()
        try finishExpression()
        guard case .number(let number) = value, number.value.isFinite else {
            throw ExpressionError.invalidExpression
        }
        return number.value
    }

    /// Firmware `utils.word_wrap` used by `calc.py` for answers and exceptions (width 34).
    public static func wrap(_ text: String, width: Int = 34) -> [String] {
        if text.isEmpty { return [""] }
        var lines: [String] = []
        var remaining = text
        while remaining.count > width {
            let chunk = String(remaining.prefix(width))
            if let space = chunk.lastIndex(of: " "), space > remaining.startIndex {
                lines.append(String(remaining[..<space]))
                remaining = String(remaining[remaining.index(after: space)...])
            } else {
                lines.append(chunk)
                remaining.removeFirst(width)
            }
        }
        lines.append(remaining)
        return lines
    }

    /// Firmware REPL: bare `help`/`cls`/`rand`, hashes, and a Python-like expression.
    public mutating func evaluateCommand(
        randomBytes: @escaping (Int) throws -> Data = { Data(count: $0) }
    ) throws -> CalculatorOutput {
        self.randomBytes = randomBytes
        if isBlacklisted { return .silent }
        skipWhitespace()
        let start = index
        if let name = readIdentifier(), ["help", "cls", "rand"].contains(name) {
            skipWhitespace()
            skipComment()
            if index == characters.count {
                switch name {
                case "cls": return .clear
                case "help": return .text(Self.helpText)
                default: return .text(try randomHex(32))
                }
            }
        }
        index = start
        let value = try parseOr()
        try finishExpression()
        switch value {
        case .number(let number):
            guard number.value.isFinite else { throw ExpressionError.invalidExpression }
            usedTrueDivision = number.isFloat
            return .text(Self.pythonRepr(number.value, isFloat: number.isFloat))
        case .text(let text): return .text(text)
        case .none: return .clear
        }
    }

    private struct Numeric: Equatable {
        var value: Double
        var isFloat: Bool

        static func int(_ value: Double) -> Numeric { Numeric(value: value, isFloat: false) }
        static func float(_ value: Double) -> Numeric { Numeric(value: value, isFloat: true) }
    }

    private enum Value: Equatable {
        case number(Numeric)
        case text(String)
        case none

        static func int(_ value: Double) -> Value { .number(.int(value)) }
        static func float(_ value: Double) -> Value { .number(.float(value)) }
    }

    private var isBlacklisted: Bool {
        let line = String(characters)
        return Self.blacklist.contains { line.contains($0) }
    }

    private mutating func rejectBlacklist() throws {
        if isBlacklisted { throw ExpressionError.invalidExpression }
    }

    // MARK: - Grammar (Python-like, no statements)

    private mutating func parseOr() throws -> Value {
        var value = try parseAnd()
        while matchKeyword("or") {
            let rhs = try parseAnd()
            value = isTruthy(value) ? value : rhs
        }
        return value
    }

    private mutating func parseAnd() throws -> Value {
        var value = try parseNot()
        while matchKeyword("and") {
            let rhs = try parseNot()
            value = isTruthy(value) ? rhs : value
        }
        return value
    }

    private mutating func parseNot() throws -> Value {
        if matchKeyword("not") {
            return .int(isTruthy(try parseNot()) ? 0 : 1)
        }
        return try parseComparison()
    }

    private mutating func parseComparison() throws -> Value {
        var previous = try parseBitwiseOr()
        var ok = true
        var saw = false
        while let op = matchComparison() {
            saw = true
            let rhs = try parseBitwiseOr()
            if ok { ok = try compare(previous, op, rhs) }
            previous = rhs
        }
        return saw ? .int(ok ? 1 : 0) : previous
    }

    private mutating func parseBitwiseOr() throws -> Value {
        var value = try parseXor()
        while matchOperator("|", avoid: "|") {
            let lhs = try intValue(value)
            let rhs = try intValue(try parseXor())
            value = .int(Double(lhs | rhs))
        }
        return value
    }

    /// Python: `^` is bitwise XOR (below +/−).
    private mutating func parseXor() throws -> Value {
        var value = try parseBitwiseAnd()
        while matchOperator("^") {
            let lhs = try intValue(value)
            let rhs = try intValue(try parseBitwiseAnd())
            value = .int(Double(lhs ^ rhs))
        }
        return value
    }

    private mutating func parseBitwiseAnd() throws -> Value {
        var value = try parseShift()
        while matchOperator("&") {
            let lhs = try intValue(value)
            let rhs = try intValue(try parseShift())
            value = .int(Double(lhs & rhs))
        }
        return value
    }

    private mutating func parseShift() throws -> Value {
        var value = try parseAdd()
        while true {
            if matchOperator("<<") {
                let shift = try intValue(try parseAdd())
                guard shift >= 0, shift < 63 else { throw ExpressionError.invalidExpression }
                value = .int(Double(try intValue(value) << shift))
            } else if matchOperator(">>") {
                let shift = try intValue(try parseAdd())
                guard shift >= 0, shift < 63 else { throw ExpressionError.invalidExpression }
                value = .int(Double(try intValue(value) >> shift))
            } else {
                break
            }
        }
        return value
    }

    private mutating func parseAdd() throws -> Value {
        var value = try parseTerm()
        while true {
            if matchOperator("+") {
                let rhs = try parseTerm()
                value = try add(value, rhs)
            } else if matchOperator("-") {
                let lhs = try numeric(value)
                let rhs = try numeric(try parseTerm())
                value = .number(Numeric(
                    value: lhs.value - rhs.value,
                    isFloat: lhs.isFloat || rhs.isFloat
                ))
            } else {
                break
            }
        }
        return value
    }

    private mutating func parseTerm() throws -> Value {
        var value = try parseUnary()
        while true {
            if matchOperator("//") {
                let lhs = try numeric(value)
                let rhs = try numeric(try parseUnary())
                let result = try floorDivide(lhs.value, rhs.value)
                value = .number(Numeric(value: result, isFloat: lhs.isFloat || rhs.isFloat))
            } else if matchOperator("*", avoid: "*") {
                let lhs = try numeric(value)
                let rhs = try numeric(try parseUnary())
                value = .number(Numeric(
                    value: lhs.value * rhs.value,
                    isFloat: lhs.isFloat || rhs.isFloat
                ))
            } else if matchOperator("/") {
                let rhs = try numeric(try parseUnary())
                if rhs.value == 0 { throw ExpressionError.divisionByZero }
                usedTrueDivision = true
                let lhs = try numeric(value)
                value = .float(lhs.value / rhs.value)
            } else if matchOperator("%") {
                let lhs = try numeric(value)
                let rhs = try numeric(try parseUnary())
                value = .number(Numeric(
                    value: try modulo(lhs.value, rhs.value),
                    isFloat: lhs.isFloat || rhs.isFloat
                ))
            } else {
                break
            }
        }
        return value
    }

    private mutating func parseUnary() throws -> Value {
        if matchOperator("+") { return try parseUnary() }
        if matchOperator("-") {
            let inner = try numeric(try parseUnary())
            return .number(Numeric(value: -inner.value, isFloat: inner.isFloat))
        }
        if matchOperator("~") {
            return .int(Double(~(try intValue(try parseUnary()))))
        }
        return try parsePower()
    }

    /// Python `**` binds tighter than a unary on its left (`-2**2 == -4`).
    private mutating func parsePower() throws -> Value {
        let base = try parsePrimary()
        if matchOperator("**") {
            let exponent = try numeric(try parseUnary())
            let lhs = try numeric(base)
            let powered = Foundation.pow(lhs.value, exponent.value)
            let isFloat = lhs.isFloat || exponent.isFloat || exponent.value < 0
            return .number(Numeric(value: powered, isFloat: isFloat))
        }
        return base
    }

    private mutating func parsePrimary() throws -> Value {
        skipWhitespace()
        if matchOperator("(") {
            let value = try parseOr()
            guard matchOperator(")") else { throw ExpressionError.invalidExpression }
            return value
        }
        if let quote = peek(), quote == "'" || quote == "\"" {
            return .text(try parseString())
        }
        if let name = readIdentifier() {
            skipWhitespace()
            if peek() == "(" { return try parseCall(name) }
            switch name {
            case "True": return .int(1)
            case "False": return .int(0)
            default: throw ExpressionError.nameError(name)
            }
        }
        return .number(try parseNumber())
    }

    private mutating func parseCall(_ name: String) throws -> Value {
        guard matchOperator("(") else { throw ExpressionError.invalidExpression }
        var args: [Value] = []
        skipWhitespace()
        if peek() != ")" {
            while true {
                args.append(try parseOr())
                skipWhitespace()
                if peek() == "," {
                    index += 1
                    skipWhitespace()
                    if peek() == ")" { break }
                } else {
                    break
                }
            }
        }
        guard matchOperator(")") else { throw ExpressionError.invalidExpression }
        return try apply(name, args)
    }

    private func apply(_ name: String, _ args: [Value]) throws -> Value {
        switch name {
        case "sha256":
            return .text(SHA2.sha256(try bytesArg(args)).hexString)
        case "sha512":
            return .text(SHA2.sha512(try bytesArg(args)).hexString)
        case "ripemd":
            return .text(RIPEMD160.hash(try bytesArg(args)).hexString)
        case "rand":
            let count: Int
            if args.isEmpty {
                count = 32
            } else if args.count == 1 {
                count = Int(try intValue(args[0]))
            } else {
                throw ExpressionError.invalidExpression
            }
            guard count >= 0 else { throw ExpressionError.invalidExpression }
            return .text(try randomHex(count))
        case "cls":
            guard args.isEmpty else { throw ExpressionError.invalidExpression }
            return .none
        case "help":
            guard args.isEmpty else { throw ExpressionError.invalidExpression }
            return .text(Self.helpText)
        case "abs":
            guard args.count == 1 else { throw ExpressionError.invalidExpression }
            let inner = try numeric(args[0])
            return .number(Numeric(value: abs(inner.value), isFloat: inner.isFloat))
        case "int":
            let truncated = try oneNumber(args).rounded(.towardZero)
            return .int(Double(try intValue(.int(truncated))))
        case "float":
            if args.count == 1, case .text(let text) = args[0], let value = Double(text) {
                return .float(value)
            }
            return .float(try oneNumber(args))
        case "round":
            return .float(try oneNumber(args).rounded())
        case "pow":
            guard args.count == 2 else { throw ExpressionError.invalidExpression }
            let lhs = try numeric(args[0])
            let rhs = try numeric(args[1])
            return .number(Numeric(
                value: Foundation.pow(lhs.value, rhs.value),
                isFloat: lhs.isFloat || rhs.isFloat || rhs.value < 0
            ))
        case "min":
            guard !args.isEmpty else { throw ExpressionError.invalidExpression }
            let values = try args.map { try numeric($0) }
            let isFloat = values.contains(where: \.isFloat)
            return .number(Numeric(value: values.map(\.value).min()!, isFloat: isFloat))
        case "max":
            guard !args.isEmpty else { throw ExpressionError.invalidExpression }
            let values = try args.map { try numeric($0) }
            let isFloat = values.contains(where: \.isFloat)
            return .number(Numeric(value: values.map(\.value).max()!, isFloat: isFloat))
        case "len":
            guard args.count == 1, case .text(let text) = args[0] else { throw ExpressionError.invalidExpression }
            return .int(Double(text.count))
        case "hex":
            return .text(try pythonHex(try oneInteger(args)))
        case "bin":
            return .text(try pythonBin(try oneInteger(args)))
        case "oct":
            return .text(try pythonOct(try oneInteger(args)))
        default:
            throw ExpressionError.invalidExpression
        }
    }

    // MARK: - Literals

    private mutating func parseString() throws -> String {
        guard let quote = peek(), quote == "'" || quote == "\"" else { throw ExpressionError.invalidExpression }
        index += 1
        var text = ""
        while let char = rawPeek() {
            index += 1
            if char == quote { return text }
            if char == "\\" {
                guard let escaped = rawPeek() else { throw ExpressionError.invalidExpression }
                index += 1
                switch escaped {
                case "\\", "'", "\"": text.append(escaped)
                case "n": text.append("\n")
                default: throw ExpressionError.invalidExpression
                }
            } else {
                text.append(char)
            }
        }
        throw ExpressionError.invalidExpression
    }

    private mutating func parseNumber() throws -> Numeric {
        skipWhitespace()
        if peek() == "0", index + 1 < characters.count {
            switch characters[index + 1] {
            case "x", "X": return .int(Double(try parsePrefixedInteger(radix: 16, prefixLength: 2)))
            case "b", "B": return .int(Double(try parsePrefixedInteger(radix: 2, prefixLength: 2)))
            case "o", "O": return .int(Double(try parsePrefixedInteger(radix: 8, prefixLength: 2)))
            default: break
            }
        }
        var sawDot = false
        var sawDigit = false
        var sawExp = false
        var raw = ""
        if peek() == "." {
            sawDot = true
            raw.append(".")
            index += 1
        }
        while true {
            if let char = rawPeek(), char.isNumber {
                sawDigit = true
                raw.append(char)
                index += 1
                continue
            }
            if rawPeek() == "_", index + 1 < characters.count, characters[index + 1].isNumber {
                index += 1
                continue
            }
            break
        }
        if !sawDot, rawPeek() == "." {
            sawDot = true
            raw.append(".")
            index += 1
            while true {
                if let char = rawPeek(), char.isNumber {
                    sawDigit = true
                    raw.append(char)
                    index += 1
                    continue
                }
                if rawPeek() == "_", index + 1 < characters.count, characters[index + 1].isNumber {
                    index += 1
                    continue
                }
                break
            }
        }
        if let exp = rawPeek(), exp == "e" || exp == "E" {
            let expIndex = index
            var expRaw = String(exp)
            index += 1
            if let sign = rawPeek(), sign == "+" || sign == "-" {
                expRaw.append(sign)
                index += 1
            }
            let expDigits = index
            while let char = rawPeek(), char.isNumber {
                expRaw.append(char)
                index += 1
            }
            if index == expDigits {
                index = expIndex
            } else {
                sawExp = true
                raw.append(contentsOf: expRaw)
            }
        }
        guard sawDigit, let value = Double(raw) else {
            throw ExpressionError.invalidExpression
        }
        return Numeric(value: value, isFloat: sawDot || sawExp)
    }

    private mutating func parsePrefixedInteger(radix: Int, prefixLength: Int) throws -> Int64 {
        index += prefixLength
        if rawPeek() == "_" { index += 1 }
        let start = index
        var raw = ""
        while let char = rawPeek() {
            if Int(String(char), radix: radix) != nil {
                raw.append(char)
                index += 1
            } else if char == "_", index + 1 < characters.count,
                      Int(String(characters[index + 1]), radix: radix) != nil {
                index += 1
            } else {
                break
            }
        }
        guard start != index, let value = Int64(raw, radix: radix) else {
            throw ExpressionError.invalidExpression
        }
        return value
    }

    // MARK: - Helpers

    private func bytesArg(_ args: [Value]) throws -> Data {
        guard args.count == 1, case .text(let text) = args[0] else { throw ExpressionError.invalidExpression }
        return Data(text.utf8)
    }

    private func oneNumber(_ args: [Value]) throws -> Double {
        guard args.count == 1 else { throw ExpressionError.invalidExpression }
        return try numeric(args[0]).value
    }

    private func oneInteger(_ args: [Value]) throws -> Int64 {
        guard args.count == 1 else { throw ExpressionError.invalidExpression }
        return try intValue(args[0])
    }

    private func numeric(_ value: Value) throws -> Numeric {
        guard case .number(let number) = value, number.value.isFinite else {
            throw ExpressionError.invalidExpression
        }
        return number
    }

    private func number(_ value: Value) throws -> Double {
        try numeric(value).value
    }

    private func intValue(_ value: Value) throws -> Int64 {
        let number = try numeric(value)
        guard !number.isFloat else { throw ExpressionError.invalidExpression }
        guard number.value == number.value.rounded() else { throw ExpressionError.invalidExpression }
        let converted = number.value.rounded(.towardZero)
        guard converted >= Double(Int64.min), converted <= Double(Int64.max) else {
            throw ExpressionError.invalidExpression
        }
        return Int64(converted)
    }

    private func add(_ lhs: Value, _ rhs: Value) throws -> Value {
        switch (lhs, rhs) {
        case (.number(let a), .number(let b)):
            return .number(Numeric(value: a.value + b.value, isFloat: a.isFloat || b.isFloat))
        case (.text(let a), .text(let b)): return .text(a + b)
        default: throw ExpressionError.invalidExpression
        }
    }

    private func floorDivide(_ lhs: Double, _ rhs: Double) throws -> Double {
        if rhs == 0 { throw ExpressionError.divisionByZero }
        return Foundation.floor(lhs / rhs)
    }

    private func modulo(_ lhs: Double, _ rhs: Double) throws -> Double {
        if rhs == 0 { throw ExpressionError.divisionByZero }
        return lhs - rhs * Foundation.floor(lhs / rhs)
    }

    private func compare(_ lhs: Value, _ op: String, _ rhs: Value) throws -> Bool {
        switch (lhs, rhs) {
        case (.number(let a), .number(let b)):
            switch op {
            case "<": return a.value < b.value
            case ">": return a.value > b.value
            case "<=": return a.value <= b.value
            case ">=": return a.value >= b.value
            case "==": return a.value == b.value
            case "!=": return a.value != b.value
            default: throw ExpressionError.invalidExpression
            }
        case (.text(let a), .text(let b)):
            switch op {
            case "<": return a < b
            case ">": return a > b
            case "<=": return a <= b
            case ">=": return a >= b
            case "==": return a == b
            case "!=": return a != b
            default: throw ExpressionError.invalidExpression
            }
        default:
            throw ExpressionError.invalidExpression
        }
    }

    private func isTruthy(_ value: Value) -> Bool {
        switch value {
        case .number(let number): return number.value != 0 && !number.value.isNaN
        case .text(let text): return !text.isEmpty
        case .none: return false
        }
    }

    private func pythonHex(_ value: Int64) throws -> String {
        if value < 0 {
            guard value > Int64.min else { throw ExpressionError.invalidExpression }
            return "-" + (try pythonHex(-value))
        }
        return "0x" + String(value, radix: 16)
    }

    private func pythonBin(_ value: Int64) throws -> String {
        if value < 0 {
            guard value > Int64.min else { throw ExpressionError.invalidExpression }
            return "-" + (try pythonBin(-value))
        }
        return "0b" + String(value, radix: 2)
    }

    private func pythonOct(_ value: Int64) throws -> String {
        if value < 0 {
            guard value > Int64.min else { throw ExpressionError.invalidExpression }
            return "-" + (try pythonOct(-value))
        }
        return "0o" + String(value, radix: 8)
    }

    private func randomHex(_ count: Int) throws -> String {
        try randomBytes(count).hexString
    }

    private mutating func matchComparison() -> String? {
        if matchOperator("==") { return "==" }
        if matchOperator("!=") { return "!=" }
        if matchOperator("<=") { return "<=" }
        if matchOperator(">=") { return ">=" }
        if matchOperator("<", avoid: "<") { return "<" }
        if matchOperator(">", avoid: ">") { return ">" }
        return nil
    }

    private mutating func finishExpression() throws {
        skipWhitespace()
        skipComment()
        guard index == characters.count else { throw ExpressionError.invalidExpression }
    }

    private mutating func skipComment() {
        if rawPeek() == "#" { index = characters.count }
    }

    private mutating func matchKeyword(_ word: String) -> Bool {
        skipWhitespace()
        let start = index
        guard let name = readIdentifier(), name == word else {
            index = start
            return false
        }
        return true
    }

    private mutating func matchOperator(_ op: String, avoid: Character? = nil) -> Bool {
        skipWhitespace()
        guard index + op.count <= characters.count else { return false }
        let end = index + op.count
        guard String(characters[index..<end]) == op else { return false }
        if let avoid, end < characters.count, characters[end] == avoid { return false }
        index = end
        return true
    }

    private mutating func readIdentifier() -> String? {
        skipWhitespace()
        guard let first = rawPeek(), first.isLetter || first == "_" else { return nil }
        let start = index
        index += 1
        while let char = rawPeek(), char.isLetter || char.isNumber || char == "_" { index += 1 }
        return String(characters[start..<index])
    }

    private mutating func skipWhitespace() {
        while let char = rawPeek(), char.isWhitespace { index += 1 }
    }

    private mutating func peek() -> Character? {
        skipWhitespace()
        return rawPeek()
    }

    private func rawPeek() -> Character? { index < characters.count ? characters[index] : nil }
}

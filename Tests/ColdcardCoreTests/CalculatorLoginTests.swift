import Foundation
import Testing
@testable import ColdcardCore

private func display(_ expression: String, random: Data = Data()) throws -> String {
    var evaluator = ExpressionEvaluator(expression)
    switch try evaluator.evaluateCommand(randomBytes: { count in
        if random.count >= count { return Data(random.prefix(count)) }
        return Data(count: count)
    }) {
    case .clear: return "<clear>"
    case .silent: return "<silent>"
    case .text(let text): return text
    case .number(let value):
        return ExpressionEvaluator.pythonRepr(value, isFloat: evaluator.usedTrueDivision)
    }
}

@Test func caretIsBitwiseXORNotPower() throws {
    #expect(try display("2^3") == "1")
    #expect(try display("5^3") == "6")
    #expect(try display("2**3") == "8")
}

@Test func trueDivisionReprsAsPythonFloat() throws {
    #expect(try display("10/5") == "2.0")
    #expect(try display("45*22/55") == "18.0")
}

@Test func remainingPythonEvalSurface() throws {
    #expect(try display("len('ab')") == "2")
    #expect(try display("'xy' + 'z'") == "xyz")
    #expect(try display("0x10") == "16")
    #expect(try display("10 % 3") == "1")
    #expect(try display("7 // 2") == "3")
    #expect(try display("12-12") == "0")
    #expect(try display("12_12") == "1212")
    let nested = try display("sha256(rand(4))", random: Data(count: 4))
    #expect(nested == "7e071fd9b023ed8f18458a73613a0834f6220bd5cc50357ba3493c6040a9ea8c")
}

@Test func sha256OfFirmwareExampleMessage() throws {
    #expect(try display("sha256('some message')")
            == "c47757abe4020b9168d0776f6c91617f9290e790ac2f6ce2bd6787c74ad88199")
}

@Test func randLengthIsUnclamped() throws {
    var evaluator = ExpressionEvaluator("rand(300)")
    let output = try evaluator.evaluateCommand(randomBytes: { Data(count: $0) })
    guard case .text(let hex) = output else {
        Issue.record("rand(300) should return hex text")
        return
    }
    #expect(hex.count == 600)
}

@Test func calculatorExampleLinesMatchFirmware() {
    #expect(CalculatorLogin.exampleLines == [
        "",
        "Example Commands:",
        ">> 23 + 55 / 22",
        ">> 1.020 * 45.88",
        ">> sha256('some message')",
        ">> cls    # clear screen",
        ">> help",
    ])
    #expect(CalculatorLogin.exampleLines.count == CalculatorLogin.windowLines)
    #expect(CalculatorLogin.maxInputLength == 31)
    #expect(CalculatorLogin.helpText == "Commands: sha256, sha512, ripemd, rand, cls, help")
}

@Test func clsClearsExamplesInsteadOfRerenderingThem() {
    var session = CalculatorSession()
    #expect(session.lines == CalculatorLogin.exampleLines)
    session.submit("23 + 55 / 22")
    #expect(session.lines.contains(">> 23 + 55 / 22"))
    #expect(!session.lines.contains("Example Commands:") || session.lines.count == 7)
    session.submit("cls")
    #expect(session.lines.isEmpty)
    session.submit("1+1")
    #expect(session.lines == [">> 1+1", "2"])
    #expect(!session.lines.contains("Example Commands:"))
}

@Test func pinRegexIsSingleSeparatorAndAllowsLongParts() {
    #expect(CalculatorLogin.normalizedPIN("12-12") == "12-12")
    #expect(CalculatorLogin.normalizedPIN("12_12") == "12-12")
    #expect(CalculatorLogin.normalizedPIN("12 12") == "12-12")
    #expect(CalculatorLogin.normalizedPIN("1234567-12") == "1234567-12")
    #expect(CalculatorLogin.normalizedPIN("123456-123456") == "123456-123456")
    #expect(CalculatorLogin.normalizedPIN("00-123456") == "00-123456")
    #expect(CalculatorLogin.normalizedPIN("12--12") == nil)
    #expect(CalculatorLogin.normalizedPIN("12  12") == nil)
    #expect(CalculatorLogin.normalizedPIN("12-12-12") == nil)
    #expect(CalculatorLogin.normalizedPIN("1-12") == nil)
    #expect(CalculatorLogin.normalizedPIN("12-1") == nil)
    #expect(CalculatorLogin.prefixDigits("12-") == "12")
    #expect(CalculatorLogin.prefixDigits("12_") == "12")
    #expect(CalculatorLogin.prefixDigits("12 ") == nil)
    #expect(CalculatorLogin.prefixDigits("123456-") == "123456")
}

@Test func postBrickPINLineEvaluatesInsteadOfLoggingIn() {
    var session = CalculatorSession(attemptsLeft: 0, allowPINLogin: false, allowPrefixWords: true)
    let result = session.submit("12-12")
    #expect(result == .updated)
    #expect(session.lines.contains(">> 12-12"))
    #expect(session.lines.contains("0"))
}

@Test func lastFailedPINStaysInREPLWithZeroTries() {
    var session = CalculatorSession(attemptsLeft: 1, allowPINLogin: true, allowPrefixWords: true)
    let result = session.submit("99-11", pinOK: { _ in false })
    #expect(result == .updated)
    #expect(session.attemptsLeft == 0)
    #expect(session.lines.contains(CalculatorLogin.triesRemainLine(value: 88, remaining: 0)))
    let after = session.submit("12-12")
    #expect(after == .updated)
    #expect(session.lines.contains("0"))
}

@Test func failedPINUsesPythonEvalOfTheTypedLine() {
    #expect(CalculatorLogin.triesRemainLine(value: 0, remaining: 11)
            == "0                # 11 tries remain")
    var session = CalculatorSession(attemptsLeft: 12, allowPINLogin: true)
    session.submit("12_12", pinOK: { _ in false })
    #expect(session.lines.contains(CalculatorLogin.triesRemainLine(value: 1212, remaining: 11)))
}

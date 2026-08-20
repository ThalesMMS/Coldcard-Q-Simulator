import Testing
@testable import ColdcardCore

@Test func hardwareKeyboardMapsPrintableColdcardKeys() {
    for asciiValue in UInt8(33)...UInt8(126) {
        let value = String(UnicodeScalar(asciiValue))
        #expect(HardwareKeyboardMapper.map(.characters(value)) == .character(value))
    }
    #expect(HardwareKeyboardMapper.map(.characters(" ")) == .space)
}

@Test func hardwareKeyboardMapsControlKeys() {
    #expect(HardwareKeyboardMapper.map(.upArrow) == .up)
    #expect(HardwareKeyboardMapper.map(.downArrow) == .down)
    #expect(HardwareKeyboardMapper.map(.leftArrow) == .left)
    #expect(HardwareKeyboardMapper.map(.rightArrow) == .right)
    #expect(HardwareKeyboardMapper.map(.returnKey) == .enter)
    #expect(HardwareKeyboardMapper.map(.escape) == .cancel)
    #expect(HardwareKeyboardMapper.map(.delete) == .backspace)
    #expect(HardwareKeyboardMapper.map(.tab) == .tab)
    #expect(HardwareKeyboardMapper.map(.shift) == .shift)
    #expect(HardwareKeyboardMapper.map(.symbol) == .symbol)
    #expect(HardwareKeyboardMapper.map(.home) == .home)
    #expect(HardwareKeyboardMapper.map(.end) == .end)
    #expect(HardwareKeyboardMapper.map(.pageUp) == .pageUp)
    #expect(HardwareKeyboardMapper.map(.pageDown) == .pageDown)
    #expect(HardwareKeyboardMapper.map(.lamp) == .lamp)
}

@Test func hardwareKeyboardIgnoresUnsupportedInput() {
    #expect(HardwareKeyboardMapper.map(.characters("")) == nil)
    #expect(HardwareKeyboardMapper.map(.characters("ab")) == nil)
    #expect(HardwareKeyboardMapper.map(.characters("\n")) == nil)
    #expect(HardwareKeyboardMapper.map(.characters("á")) == nil)
}

@Test func hardwareKeyboardSymbolLayerMatchesQDecoder() {
    #expect(HardwareKeyboardMapper.symbolLayer("q") == "-")
    #expect(HardwareKeyboardMapper.symbolLayer("w") == "_")
    #expect(HardwareKeyboardMapper.symbolLayer("e") == "`")
    #expect(HardwareKeyboardMapper.symbolLayer("u") == "[")
    #expect(HardwareKeyboardMapper.symbolLayer("i") == "]")
    #expect(HardwareKeyboardMapper.symbolLayer("o") == "{")
    #expect(HardwareKeyboardMapper.symbolLayer("p") == "}")
    #expect(HardwareKeyboardMapper.symbolLayer("1") == "!")
    #expect(HardwareKeyboardMapper.symbolLayer("a") == "+")
    #expect(HardwareKeyboardMapper.symbolLayer("r") == nil)
    #expect(HardwareKeyboardMapper.symbolFunctionKey("z") == 1)
    #expect(HardwareKeyboardMapper.symbolFunctionKey("x") == 2)
    #expect(HardwareKeyboardMapper.symbolFunctionKey("c") == 3)
    #expect(HardwareKeyboardMapper.symbolFunctionKey("v") == 4)
    #expect(HardwareKeyboardMapper.symbolFunctionKey("b") == 5)
    #expect(HardwareKeyboardMapper.symbolFunctionKey("n") == 6)
    #expect(HardwareKeyboardMapper.symbolFunctionKey("m") == nil)
}

@Test func hardwareKeyboardSymbolDPadMatchesQDecoder() {
    #expect(HardwareKeyboardMapper.symbolOverlay(.left) == .home)
    #expect(HardwareKeyboardMapper.symbolOverlay(.up) == .pageUp)
    #expect(HardwareKeyboardMapper.symbolOverlay(.down) == .pageDown)
    #expect(HardwareKeyboardMapper.symbolOverlay(.right) == .end)
    #expect(HardwareKeyboardMapper.symbolOverlay(.enter) == .enter)
    #expect(HardwareKeyboardMapper.symbolOverlay(.cancel) == .cancel)
}

@Test func hardwareKeyboardShiftDeleteIsClear() {
    #expect(HardwareKeyboardMapper.shiftOverlay(.backspace) == .clear)
    #expect(HardwareKeyboardMapper.shiftOverlay(.enter) == .enter)
}

@Test func firmwareStoryPagingMatchesQHeight() {
    #expect(FirmwareStoryPaging.height == 10)
    #expect(FirmwareStoryPaging.menuPageSize == 9)
    #expect(FirmwareStoryPaging.apply(top: 0, lineCount: 40, command: .home) == 0)
    #expect(FirmwareStoryPaging.apply(top: 12, lineCount: 40, command: .pageUp) == 2)
    #expect(FirmwareStoryPaging.apply(top: 0, lineCount: 40, command: .pageDown) == 10)
    #expect(FirmwareStoryPaging.apply(top: 36, lineCount: 40, command: .pageDown) == 38)
    #expect(FirmwareStoryPaging.apply(top: 0, lineCount: 40, command: .end) == 35)
}

@Test func firmwareStoryDigitsMatchUXPy() {
    #expect(FirmwareStoryPaging.digitCommand("0") == .home)
    #expect(FirmwareStoryPaging.digitCommand("7") == .pageUp)
    #expect(FirmwareStoryPaging.digitCommand("9") == .pageDown)
    #expect(FirmwareStoryPaging.digitCommand("1") == nil)
    #expect(FirmwareStoryPaging.digitCommand("8") == nil)
}

@Test func heldModifiersMatchQDecoders() {
    #expect(HardwareKeyboardMapper.applyHeldModifiers(.left, symbol: true, shift: false, caps: false) == .home)
    #expect(HardwareKeyboardMapper.applyHeldModifiers(.up, symbol: true, shift: false, caps: false) == .pageUp)
    #expect(HardwareKeyboardMapper.applyHeldModifiers(.down, symbol: true, shift: false, caps: false) == .pageDown)
    #expect(HardwareKeyboardMapper.applyHeldModifiers(.right, symbol: true, shift: false, caps: false) == .end)
    #expect(HardwareKeyboardMapper.applyHeldModifiers(.backspace, symbol: false, shift: true, caps: false) == .clear)
    #expect(HardwareKeyboardMapper.applyHeldModifiers(.backspace, symbol: true, shift: true, caps: false) == .backspace)
    #expect(HardwareKeyboardMapper.applyHeldModifiers(.left, symbol: true, shift: false, caps: true) == .left)
    #expect(HardwareKeyboardMapper.applyHeldModifiers(.character("q"), symbol: true, shift: false, caps: false) == .character("q"))
}

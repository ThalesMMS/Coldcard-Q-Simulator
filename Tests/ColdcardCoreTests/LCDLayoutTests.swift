import Testing
@testable import ColdcardCore

@Test func lcdGridMatchesQFirmware() {
    #expect(LCDDisplay.charsW == 34)
    #expect(LCDDisplay.charsH == 10)
    #expect(LCDDisplay.cellW == 9)
    #expect(LCDDisplay.cellH == 22)
    #expect(LCDDisplay.storyWrapWidth == 33)
    #expect(LCDDisplay.storyHeight == 10)
    #expect(LCDDisplay.menuPerPage == 9)
    #expect(LCDDisplay.menuVisibleRows == 10)
}

@Test func wordWrapMatchesFirmwareVectors() {
    #expect(LCDDisplay.wordWrap(String(repeating: "a", count: 17) + ". ccc", width: 17) == [
        String(repeating: "a", count: 17) + ".", "ccc"
    ])
    #expect(LCDDisplay.wordWrap(String(repeating: "a", count: 17) + ".", width: 17) == [
        String(repeating: "a", count: 17) + "."
    ])
    #expect(LCDDisplay.wordWrap(String(repeating: "-", count: 17) + ". ccc", width: 17) == [
        String(repeating: "-", count: 17) + ".", "ccc"
    ])
    #expect(LCDDisplay.wordWrap(String(repeating: "A", count: 34), width: 33) == [
        String(repeating: "A", count: 33), "A"
    ])
    #expect(LCDDisplay.wordWrap(String(repeating: "A", count: 33) + ". ccc", width: 33) == [
        String(repeating: "A", count: 33) + ".", "ccc"
    ])
    #expect(LCDDisplay.wordWrap("Coldcard is ready to sign spending transactions!", width: 33) == [
        "Coldcard is ready to sign", "spending transactions!"
    ])
    #expect(LCDDisplay.wordWrap("Coldcard is ready to sign spending transactions!", width: 17) == [
        "Coldcard is ready", "to sign spending", "transactions!"
    ])
    #expect(LCDDisplay.wordWrap(String(repeating: "B", count: 16) + " AAAA", width: 17) == [
        String(repeating: "B", count: 16), "AAAA"
    ])
    #expect(LCDDisplay.wordWrap(String(repeating: "B", count: 16) + "  AAAA", width: 17) == [
        String(repeating: "B", count: 16) + " ", "AAAA"
    ])
    #expect(LCDDisplay.wordWrap(String(repeating: "B", count: 17) + " AAAA", width: 17) == [
        String(repeating: "B", count: 17), "AAAA"
    ])
    #expect(LCDDisplay.wordWrap(String(repeating: "B", count: 17) + "  AAAA", width: 17) == [
        String(repeating: "B", count: 17), " AAAA"
    ])
    #expect(LCDDisplay.wordWrap("(recommended), or by typing numbers.", width: 17) == [
        "(recommended), or", "by typing numbers."
    ])
    #expect(LCDDisplay.wordWrap("difficult to recover your funds.", width: 17) == [
        "difficult to", "recover your", "funds."
    ])
    #expect(LCDDisplay.wordWrap("USB Serial Number:", width: 17) == ["USB Serial Number:"])
    #expect(LCDDisplay.wordWrap("USB Serial Number;", width: 17) == ["USB Serial Number;"])
    #expect(LCDDisplay.wordWrap("USB Serial Number/", width: 17) == ["USB Serial", "Number/"])
}

@Test func storyComposeWrapsPagesAndDrawsEOT() {
    let lines = LCDStory.compose(title: "WARNING", body: String(repeating: "word ", count: 40))
    #expect(lines.first?.isTitle == true)
    #expect(lines.dropFirst().first?.text == "")
    #expect(lines.last?.isEOT == true)
    #expect(lines.allSatisfy { $0.cellWidth <= LCDDisplay.charsW })

    var top = 0
    top = LCDStory.move(top: top, lineCount: lines.count, nav: .pageDown)
    #expect(top == min(lines.count - 2, LCDDisplay.storyHeight))
    top = LCDStory.move(top: top, lineCount: lines.count, nav: .home)
    #expect(top == 0)
    top = LCDStory.move(top: top, lineCount: lines.count, nav: .end)
    #expect(top == max(0, lines.count - LCDDisplay.storyHeight / 2))

    let visible = LCDStory.visible(lines: lines, top: 0)
    #expect(visible.count <= LCDDisplay.storyHeight)
    #expect(LCDStory.eotBar.count == LCDDisplay.charsW)
    #expect(LCDStory.eotBar.allSatisfy { $0 == "┅" })
}

@Test func storyVisibleWindowIsTenRowsNotTheWholeBody() {
    let body = (0..<40).map { "line \($0)" }.joined(separator: "\n")
    let lines = LCDStory.compose(title: nil, body: body)
    #expect(lines.count > LCDDisplay.storyHeight)
    let page = LCDStory.visible(lines: lines, top: 0)
    #expect(page.count == LCDDisplay.storyHeight)
    #expect(page.allSatisfy { !$0.isEOT })
    #expect(page.first?.text == "line 0")
}

@Test func storyTitleHoldsQRAndNFCHints() {
    let lines = LCDStory.compose(title: "Data Export", body: "Hello", hintQR: true, hintNFC: true)
    guard case .title(_, let hints) = lines[0] else {
        Issue.record("expected title line")
        return
    }
    #expect(hints == [.qr, .nfc])
}

@Test func storyAddressLinesWrapAndStayMarked() {
    let addr = "tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    let body = LCDDisplay.showSingleAddress(addr)
    let lines = LCDStory.compose(title: nil, body: body)
    let addresses = lines.compactMap { line -> String? in
        if case .address(let value) = line { return value }
        return nil
    }
    #expect(addresses == [
        String(addr.prefix(LCDDisplay.addressWrapWidth)),
        String(addr.dropFirst(LCDDisplay.addressWrapWidth))
    ])
    #expect(LCDDisplay.drawnAddress(addresses[0]).hasPrefix(" "))
    #expect(LCDDisplay.storyPlaintext(body) == LCDDisplay.spacedAddress(addr))
}

@Test func menuInvertBarIsLabelWidthAndWindowIsTenRows() {
    #expect(LCDDisplay.menuInvertCellCount(label: "Ready To Sign") == 15)
    var pager = LCDMenuPager(count: 20, wrap: false)
    #expect(pager.visibleIndices == 0..<10)
    #expect(pager.selectedRow == 0)
    #expect(pager.showsScrollBar)

    for _ in 0..<8 { pager.down() }
    #expect(pager.cursor == 8)
    #expect(pager.ypos == 1)
    #expect(pager.visibleIndices.count == 10)

    pager.gotoIndex(19)
    #expect(pager.cursor == 19)
    #expect(pager.ypos == 17)
    #expect(pager.selectedRow == 19 - pager.ypos)

    pager.home()
    #expect(pager.cursor == 0)
    #expect(pager.ypos == 0)

    var wrapping = LCDMenuPager(count: 12, wrap: true)
    wrapping.gotoIndex(11)
    wrapping.down()
    #expect(wrapping.cursor == 0)
    #expect(wrapping.ypos == 0)
}

@Test func scrollBarMatchesFirmwareGeometry() {
    let first = LCDScrollBar.geometry(offset: 0, count: 20, perPage: 9, activeHeight: 220)
    #expect(first.thumbHeight >= 4)
    #expect(first.thumbOffset == 0)

    let last = LCDScrollBar.geometry(offset: 11, count: 20, perPage: 9, activeHeight: 220)
    #expect(last.thumbOffset + last.thumbHeight == 220)
}

@Test func statusXFPIsLowercaseAndPowerChoosesBatteryOrPlug() {
    #expect(LCDStatus.xfpGlyphs("A1B2C3D4") == "a1b2c3d4")
    #expect(LCDStatus.showsXFP("a1b2c3d4"))
    #expect(!LCDStatus.showsXFP(nil))
    #expect(!LCDStatus.showsXFP(""))

    #expect(LCDStatus.powerIcon(level: -1, isCharging: false, isUnknown: true) == .plugged)
    #expect(LCDStatus.powerIcon(level: 1, isCharging: true, isUnknown: false) == .plugged)
    #expect(LCDStatus.powerIcon(level: 0.1, isCharging: false, isUnknown: false) == .battery(0))
    #expect(LCDStatus.powerIcon(level: 0.3, isCharging: false, isUnknown: false) == .battery(1))
    #expect(LCDStatus.powerIcon(level: 0.55, isCharging: false, isUnknown: false) == .battery(2))
    #expect(LCDStatus.powerIcon(level: 0.9, isCharging: false, isUnknown: false) == .battery(3))
    #expect(LCDStatus.bip39IconOn(passphrase: "x"))
    #expect(!LCDStatus.tmpIconOn(hasEphemeralSeed: false))
    #expect(LCDStatus.tmpIconOn(hasEphemeralSeed: true))
    #expect(!LCDStatus.bip39IconOn(passphrase: ""))
}

@Test func busyBarHasStripesAndDramaticPauseFill() {
    #expect(LCDBusyBar.phaseCount == 16)
    let phase0 = (0..<320).map { LCDBusyBar.isForeground(x: $0, phase: 0) }
    let phase1 = (0..<320).map { LCDBusyBar.isForeground(x: $0, phase: 1) }
    #expect(phase0.contains(true) && phase0.contains(false))
    #expect(phase0 != phase1)
    #expect(LCDBusyBar.fillWidth(progress: 0, total: 320) == 0)
    #expect(LCDBusyBar.fillWidth(progress: 1, total: 320) == 320)
    #expect(LCDBusyBar.fillWidth(progress: 0.5, total: 320) == 160)
}

import Testing
@testable import ColdcardCore

@Test func addressSummaryExportPromptMatchesFirmwareWithoutVDOrNFC() {
    let prompt = ExportPromptBuilder.prompt(
        whatItIs: "address summary file",
        dualSDSlots: true,
        virtualDiskEnabled: false,
        nfcEnabled: false,
        qrEnabled: true,
        qwerty: true,
        forcePrompt: true
    )
    #expect(prompt == "Press (1) to save address summary file to SD Card, (B) for lower slot, QR to show QR code.")
}

@Test func addressSummaryExportPromptIncludesVirtDiskWhenEnabled() {
    let prompt = ExportPromptBuilder.prompt(
        whatItIs: "address summary file",
        dualSDSlots: true,
        virtualDiskEnabled: true,
        nfcEnabled: false,
        qrEnabled: true,
        qwerty: true,
        forcePrompt: true
    )
    #expect(prompt == "Press (1) to save address summary file to SD Card, (B) for lower slot, press (2) to save to Virtual Disk, QR to show QR code.")
}

@Test func addressSummaryExportPromptIncludesNFCAndChangeKey() {
    let prompt = ExportPromptBuilder.prompt(
        whatItIs: "address summary file",
        dualSDSlots: true,
        virtualDiskEnabled: true,
        nfcEnabled: true,
        qrEnabled: true,
        qwerty: true,
        key0: "to show change addresses",
        forcePrompt: true
    )
    #expect(prompt == "Press (1) to save address summary file to SD Card, (B) for lower slot, press (2) to save to Virtual Disk, press NFC to share via NFC, QR to show QR code, (0) to show change addresses.")
}

@Test func signedMessageExportPromptMatchesFirmwareQ() {
    let prompt = ExportPromptBuilder.prompt(
        whatItIs: "Signed Msg",
        dualSDSlots: true,
        virtualDiskEnabled: false,
        nfcEnabled: false,
        qrEnabled: true,
        qwerty: true
    )
    #expect(prompt == "Press (1) to save Signed Msg to SD Card, (B) for lower slot, QR to show QR code.")
}

@Test func signedMessageExportPromptIncludesVirtDiskAndNFC() {
    let prompt = ExportPromptBuilder.prompt(
        whatItIs: "Signed Msg",
        dualSDSlots: true,
        virtualDiskEnabled: true,
        nfcEnabled: true,
        qrEnabled: true,
        qwerty: true
    )
    #expect(prompt == "Press (1) to save Signed Msg to SD Card, (B) for lower slot, press (2) to save to Virtual Disk, press NFC to share via NFC, QR to show QR code.")
}

@Test func addressSummaryExportPromptOmitsQRWhenDisallowed() {
    let prompt = ExportPromptBuilder.prompt(
        whatItIs: "address summary file",
        dualSDSlots: true,
        virtualDiskEnabled: false,
        nfcEnabled: false,
        qrEnabled: false,
        qwerty: true,
        forcePrompt: true
    )
    #expect(prompt == "Press (1) to save address summary file to SD Card, (B) for lower slot.")
}

@Test func addressListStoryPagesAndDoesNotWrapWhenLongerThanTenLines() {
    var body = "Addresses 0⋯9:\n\n"
    for index in 0..<10 {
        body += "m/84h/1h/0h/0/\(index) =>\n\(String(repeating: "tb1q", count: 12))\n\n"
    }
    body += ExportPromptBuilder.prompt(
        whatItIs: "address summary file",
        dualSDSlots: true,
        virtualDiskEnabled: false,
        nfcEnabled: false,
        qrEnabled: true,
        qwerty: true,
        forcePrompt: true
    )!
    body += "\n\nPress RIGHT to see next group, LEFT to go back. X to quit."

    let lines = LCDStory.compose(title: nil, body: body)
    #expect(lines.count > 10)

    var top = 0
    top = FirmwareStoryPaging.apply(top: top, lineCount: lines.count, command: .pageDown)
    #expect(top == FirmwareStoryPaging.height)
    #expect(top != 0)

    var last = top
    for _ in 0..<20 {
        last = FirmwareStoryPaging.apply(top: last, lineCount: lines.count, command: .pageDown)
    }
    #expect(last == max(0, lines.count - 2))
    #expect(FirmwareStoryPaging.apply(top: last, lineCount: lines.count, command: .pageDown) == last)
    #expect(FirmwareStoryPaging.apply(top: 0, lineCount: lines.count, command: .pageUp) == 0)

    let page = LCDStory.visible(lines: lines, top: last)
    #expect(page.count <= LCDDisplay.storyHeight)
    #expect(page.contains(where: \.isEOT) || last > 0)
}

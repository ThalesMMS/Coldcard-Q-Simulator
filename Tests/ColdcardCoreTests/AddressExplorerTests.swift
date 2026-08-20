import Testing
@testable import ColdcardCore

@Test func addressExplorerPagesLikeFirmwareQArrowsAndHome() {
    let max = AddressExplorer.maxIndex
    #expect(AddressExplorer.move(start: 0, deltaPages: 1) == 10)
    #expect(AddressExplorer.move(start: 0, deltaPages: -1) == 0)
    #expect(AddressExplorer.move(start: 5, deltaPages: -1) == 0)
    #expect(AddressExplorer.move(start: 10, deltaPages: -1) == 0)

    var start: UInt32 = 0
    for _ in 0..<3 { start = AddressExplorer.move(start: start, deltaPages: 1) }
    for _ in 0..<2 { start = AddressExplorer.move(start: start, deltaPages: -1) }
    start = AddressExplorer.move(start: start, deltaPages: 1)
    #expect(start == 20)

    start = 0
    for _ in 0..<10 { start = AddressExplorer.move(start: start, deltaPages: 1) }
    #expect(start == 100)

    #expect(AddressExplorer.move(start: max, deltaPages: 1) == max)
    start = max
    for _ in 0..<3 { start = AddressExplorer.move(start: start, deltaPages: -1) }
    #expect(start == 2_147_483_617)

    start = 100_003
    for _ in 0..<6 { start = AddressExplorer.move(start: start, deltaPages: 1) }
    #expect(start == 100_063)

    #expect(AddressExplorer.move(start: 2_147_483_638, deltaPages: 1) == 2_147_483_638)
    #expect(AddressExplorer.move(start: 2_147_483_637, deltaPages: 1) == max)
    #expect(AddressExplorer.move(start: 2_147_483_636, deltaPages: 1) == 2_147_483_646)

    #expect(AddressExplorer.homeStart() == 0)
    #expect(AddressExplorer.homeStart(from: 100) == 0)
}

@Test func addressExplorerVisibleCountClampsAtMaxIndex() {
    let max = AddressExplorer.maxIndex
    #expect(AddressExplorer.visibleCount(start: 0) == 10)
    #expect(AddressExplorer.visibleCount(start: max) == 1)
    #expect(AddressExplorer.visibleCount(start: 2_147_483_638) == 10)
    #expect(AddressExplorer.visibleCount(start: 2_147_483_646) == 2)
    #expect(AddressExplorer.header(start: 0, count: 10) == "Addresses 0⋯9:")
    #expect(AddressExplorer.header(start: max, count: 10) == "Addresses \(max)⋯\(max):")
    #expect(AddressExplorer.header(start: 0, count: nil) == "Showing single address.")
}

@Test func addressExplorerRowLayoutIsPathThenAddress() {
    let row = AddressExplorer.row(derivation: "m/84h/1h/0h/0/0", address: "tb1qexample")
    #expect(row == "m/84h/1h/0h/0/0 =>\ntb1qexample\n\n")
    #expect(!row.contains("#"))
}

@Test func addressExplorerChangeKeyIsOneWay() {
    #expect(AddressExplorer.changeKeyLabel(allowChange: true, showingChange: false) == "to show change addresses")
    #expect(AddressExplorer.changeKeyLabel(allowChange: true, showingChange: true) == nil)
    #expect(AddressExplorer.changeKeyLabel(allowChange: false, showingChange: false) == nil)
}

@Test func addressExplorerCustomPathCountAndFormatPicker() {
    #expect(AddressExplorer.listCount(path: "m/1h/{idx}") == 10)
    #expect(AddressExplorer.listCount(path: "m/1/2/3") == nil)
    #expect(AddressExplorer.formatPickerIndex(path: "m/44h/1h/0") == 1)
    #expect(AddressExplorer.formatPickerIndex(path: "m/49h/1h/0") == 2)
    #expect(AddressExplorer.formatPickerIndex(path: "m/84h/1h/0") == 0)
    #expect(AddressExplorer.formatPickerIndex(path: "m/1h/{idx}") == 0)
}

@Test func addressExplorerApplicationsHonorCoinAndStart() {
    #expect(AddressExplorer.applicationPath(.wasabi, coinType: 1) == "m/84h/1h/0h/{change}/{idx}")
    #expect(AddressExplorer.applicationPath(.samouraiPostmix, coinType: 1) == "m/84h/1h/2147483646h/{change}/{idx}")
    #expect(AddressExplorer.applicationPath(.samouraiPremix, coinType: 1) == "m/84h/1h/2147483645h/{change}/{idx}")
    #expect(AddressExplorer.csvCount(isSingle: false, start: 0) == 250)
    #expect(AddressExplorer.csvCount(isSingle: true, start: 100) == nil)
    #expect(AddressExplorer.csvCount(isSingle: false, start: AddressExplorer.maxIndex) == 1)
}

@Test func addressExplorerStoryHidesQuitOnSingleAndExportOnLaterPages() {
    let rows = [("m/84h/1h/0h/0/0", "tb1qabc")]
    let single = AddressExplorer.story(
        isSingle: true,
        pageStart: 0,
        startIndex: 0,
        rows: rows,
        exportPrompt: "Press (1) to save address summary file to SD Card."
    )
    #expect(single.hasPrefix("Showing single address.\n\n"))
    #expect(single.contains("m/84h/1h/0h/0/0 =>\n"))
    #expect(single.contains(" Press (0) to sign message with this key."))
    #expect(!single.contains("X to quit."))
    #expect(!single.contains("Press RIGHT"))

    let first = AddressExplorer.story(
        isSingle: false,
        pageStart: 0,
        startIndex: 0,
        rows: rows,
        exportPrompt: "Press (1) to save."
    )
    #expect(first.contains("Press (1) to save."))
    #expect(first.contains("Press RIGHT to see next group, LEFT to go back. X to quit."))

    let later = AddressExplorer.story(
        isSingle: false,
        pageStart: 10,
        startIndex: 0,
        rows: rows,
        exportPrompt: "Press (1) to save."
    )
    #expect(!later.contains("Press (1) to save."))
    #expect(later.contains("Press RIGHT to see next group, LEFT to go back. X to quit."))
}

@Test func addressExplorerMultisigDisplayAndCSVMatchFirmware() {
    let paths = [
        "[0F056943/48h/1h/0h/2h/0/0]",
        "[AABBCCDD/48h/1h/0h/2h/0/0]"
    ]
    #expect(AddressExplorer.multisigDerivationLine(idx: 0, change: 0, signerCount: 2, paths: paths)
            == paths.joined(separator: "\n") + "\n")
    #expect(AddressExplorer.multisigDerivationLine(idx: 1, change: 0, signerCount: 2, paths: paths) == "⋯/0/1")
    #expect(AddressExplorer.multisigDerivationLine(idx: 0, change: 0, signerCount: 5, paths: paths) == "⋯/0/0")
    #expect(AddressExplorer.multisigDerivationLine(idx: 0, change: 1, signerCount: 2, paths: paths)
            == paths.joined(separator: "\n") + "\n")

    #expect(AddressExplorer.allowQR(isMultisig: false, showFull: false))
    #expect(!AddressExplorer.allowQR(isMultisig: true, showFull: false))
    #expect(AddressExplorer.allowQR(isMultisig: true, showFull: true))

    let address = "tb1qabcdefghijklmnopqrstuvwxyz1234567890abcd"
    #expect(MultisigWalletConfig.censorAddress(address, showFull: true) == address)
    #expect(MultisigWalletConfig.censorAddress(address, showFull: false) == "tb1qabcdefgh___lmnopqrstuvwxyz1234567890abcd")

    let csv = AddressExplorer.multisigCSV(
        rows: [(index: 0, address: "tb1q___hide", scriptHex: "aabb", derivations: paths)],
        signerCount: 2
    )
    #expect(csv.hasPrefix("\"Index\",\"Payment Address\",\"Redeem Script\",\"Derivation (1 of 2)\",\"Derivation (2 of 2)\"\n"))
    #expect(csv.contains("0,\"tb1q___hide\",\"aabb\",\"[0F056943/48h/1h/0h/2h/0/0]\",\"[AABBCCDD/48h/1h/0h/2h/0/0]\""))
}

@Test func addressExplorerKeypathMenuMatchesFirmware() {
    #expect(AddressExplorer.keypathLabels(atRoot: true, cpath: "m", leaf: 0, ranged: true) == [
        "m/⋯", "m/44h/⋯", "m/49h/⋯", "m/84h/⋯", "m", "m/0/{idx}", "m/{idx}"
    ])
    #expect(AddressExplorer.keypathLabels(atRoot: true, cpath: "m", leaf: 0, ranged: false) == [
        "m/⋯", "m/44h/⋯", "m/49h/⋯", "m/84h/⋯", "m"
    ])
    let p = "m/44h/1"
    #expect(AddressExplorer.keypathLabels(atRoot: false, cpath: "m/44h", leaf: 1, ranged: true) == [
        "\(p)h/⋯", "\(p)/⋯", "\(p)h", p,
        "\(p)h/0/{idx}", "\(p)/0/{idx}", "\(p)h/{idx}", "\(p)/{idx}"
    ])
    let long = AddressExplorer.displayedKeypathLabel(
        "m/2147483647/2147483647/2147483647h/⋯",
        atRoot: false,
        cpath: "m/2147483647/2147483647",
        leaf: 2_147_483_647
    )
    #expect(long.hasPrefix("⋯"))
    #expect(long.contains("/⋯"))
}

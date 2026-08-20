import Testing
@testable import ColdcardCore

@Test func busyTitlesMatchFirmwareFullscreenCopy() {
    #expect(FirmwareBusyTitle.reading == "Reading...")
    #expect(FirmwareBusyTitle.visualizing == "Visualizing...")
    #expect(FirmwareBusyTitle.applying == "Applying...")
    #expect(FirmwareBusyTitle.aborted == "Aborted.")
    #expect(FirmwareBusyTitle.validating == "Validating...")
    #expect(FirmwareBusyTitle.abortedSeconds == 2)
    #expect(FirmwareBusyTitle.abortedLongSeconds == 3)
    #expect(FirmwareBusyTitle.abortedKeystrokesSeconds == 1)
}

@Test func toggleStoryShowsOnlyWhileSettingIsStillDefault() {
    #expect(ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: true))
    #expect(!ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: false))
}

@Test func toggleStoryForChainUsesBitcoinAsDefault() {
    #expect(ToggleMenuStory.showsStoryOnEnter(isChain: true, chainIsBitcoin: true, settingKeyMissing: false))
    #expect(!ToggleMenuStory.showsStoryOnEnter(isChain: true, chainIsBitcoin: false, settingKeyMissing: true))
}

@Test func pushTxIntroShowsOnlyWhileURLIsMissing() {
    #expect(ToggleMenuStory.showsPushTxIntro(urlMissing: true))
    #expect(!ToggleMenuStory.showsPushTxIntro(urlMissing: false))
}

@Test func noteGroupPickerUsesChosenCheckmarkNotCurrentSubtitle() {
    let groups = ["Work", "Bank", "Work"]
    #expect(NoteGroupPickerUX.sortedGroups(from: groups) == ["Bank", "Work"])
    #expect(NoteGroupPickerUX.chosenIndex(current: "", groups: groups) == 0)
    #expect(NoteGroupPickerUX.chosenIndex(current: "Work", groups: groups) == 2)
    #expect(NoteGroupPickerUX.chosenIndex(current: "Bank", groups: groups) == 1)
    #expect(NoteGroupPickerUX.isChecked(title: "(none)", current: ""))
    #expect(!NoteGroupPickerUX.isChecked(title: "(none)", current: "Work"))
    #expect(NoteGroupPickerUX.isChecked(title: "Work", current: "Work"))
    #expect(!NoteGroupPickerUX.isChecked(title: "Work", current: "Bank"))
    #expect(!NoteGroupPickerUX.isChecked(title: "New Group", current: "Work"))
}

@Test func visualizeTransactionStoryMatchesFirmware() {
    #expect(VisualizeTransactionUX.title == "Signed Transaction")
    #expect(VisualizeTransactionUX.deserializeFailed == "Unable to deserialize")
    #expect(VisualizeTransactionUX.body(inputs: 1, outputs: 1, txid: "ab") == "1 input, 1 output\n\nTxid:\nab")
    #expect(VisualizeTransactionUX.body(inputs: 2, outputs: 3, txid: "cd") == "2 inputs, 3 outputs\n\nTxid:\ncd")
}

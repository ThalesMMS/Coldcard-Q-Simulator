import Foundation
import Testing
@testable import ColdcardCore

@Test func isPSBTTasteMatchesFirmwareMagicHexAndBase64() {
    #expect(PSBT.isPSBTTaste(filename: "a.psbt", data: PSBT.magic))
    #expect(PSBT.isPSBTTaste(filename: "a.psbt", data: PSBT.magic + Data(repeating: 0, count: 8)))
    #expect(PSBT.isPSBTTaste(filename: "a.psbt", data: Data("70736274ff".utf8)))
    #expect(PSBT.isPSBTTaste(filename: "a.psbt", data: Data("70736274FF extra".utf8)))
    #expect(PSBT.isPSBTTaste(filename: "a.psbt", data: Data("cHNidP8AAAA".utf8)))
    #expect(!PSBT.isPSBTTaste(filename: "txn-signed.psbt", data: PSBT.magic))
    #expect(!PSBT.isPSBTTaste(filename: "A-SIGNED.PSBT", data: PSBT.magic))
    #expect(!PSBT.isPSBTTaste(filename: "a.psbt", data: Data("not-a-psbt".utf8)))
    #expect(!PSBT.isPSBTTaste(filename: "a.psbt", data: Data()))
}

@Test func readyToSignSilentPickAndSignAllLabelMatchFirmware() {
    #expect(ReadyToSign.silentOutcome(fileCount: 0) == .empty)
    #expect(ReadyToSign.silentOutcome(fileCount: 1) == .autoOpen)
    #expect(ReadyToSign.silentOutcome(fileCount: 2) == .picker)
    #expect(ReadyToSign.signAllLabel == "[Sign All]")
    #expect(ReadyToSign.pickerTitles(filenames: ["b.psbt", "a.psbt"]) == ["[Sign All]", "a.psbt", "b.psbt"])
}

@Test func nfcStartPSBTRxFindsLastLargeTastedRecord() {
    let small = PSBT.magic + Data(repeating: 1, count: 20)
    let first = PSBT.magic + Data(repeating: 2, count: 120)
    let last = Data(("cHNidP" + String(repeating: "A", count: 120)).utf8)
    #expect(ReadyToSign.psbtPayload(fromNDEF: [small]) == nil)
    #expect(ReadyToSign.psbtPayload(fromNDEF: [small, first]) == first)
    #expect(ReadyToSign.psbtPayload(fromNDEF: [first, last]) == last)
    #expect(ReadyToSign.psbtPayload(fromNDEF: [Data(repeating: 9, count: 200)]) == nil)
    #expect(ReadyToSign.nfcReceivePrompt == "Tap phone to screen, or CANCEL.")
    #expect(ReadyToSign.nfcSignFailedBody("boom") == "Failed to sign PSBT.\n\nboom")
}

@Test func readyToSignEmptyStoryMatchesFirmware() {
    #expect(ReadyToSign.emptyTitle(temporarySeed: false, xfp: "aabbccdd") == "")
    #expect(ReadyToSign.emptyTitle(temporarySeed: true, xfp: "aabbccdd") == "[aabbccdd]")
    let story = ReadyToSign.emptyStory(virtualDiskEnabled: true, nfcEnabled: true)
    #expect(story.hasPrefix("Coldcard is ready to sign spending transactions!\n\n"))
    #expect(story.contains("Put the proposed transaction onto MicroSD card in PSBT format"))
    #expect(story.contains("Press (B) to import PSBT from lower slot SD Card"))
    #expect(story.contains("press (2) to import from Virtual Disk"))
    #expect(story.contains("You will always be prompted to confirm the details before any signature is performed."))
    #expect(!story.contains("Press (1)"))
    #expect(!story.contains("Demo PSBT"))
}

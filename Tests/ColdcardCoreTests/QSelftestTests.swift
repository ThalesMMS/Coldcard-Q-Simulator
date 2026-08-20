import Foundation
import Testing
@testable import ColdcardCore

/// Firmware `selftest.start_selftest` on Q (`has_battery`, `has_qr`, `has_qwerty`, dual SD).
@Test func qSelftestOrderMatchesFirmwareStartSelftest() {
    let steps = QSelftest.qSequence(hasNFC: true)
    #expect(steps.map(\.source) == [
        "test_battery",
        "test_qr_scanner",
        "test_lcd", "test_lcd", "test_lcd",
        "test_gpu",
        "test_psram",
        "test_nfc_light",
        "test_nfc",
        "test_keyboard", "test_keyboard", "test_keyboard", "test_keyboard",
        "test_keyboard", "test_keyboard", "test_keyboard", "test_keyboard",
        "test_keyboard", "test_keyboard", "test_keyboard", "test_keyboard",
        "test_secure_element", "test_secure_element", "test_secure_element", "test_secure_element",
        "test_sd_active", "test_sd_active", "test_sd_active", "test_sd_active",
        "test_usb_light",
        "test_microsd",
    ])
}

@Test func qSelftestNFCFollowsHardwarePresenceNotSharingSetting() {
    let withChip = QSelftest.qSequence(hasNFC: true)
    let withoutChip = QSelftest.qSequence(hasNFC: false)
    #expect(withChip.contains { $0.source == "test_nfc" })
    #expect(!withoutChip.contains { $0.source == "test_nfc" })
    #expect(withChip.contains { $0.source == "test_nfc_light" })
    #expect(withoutChip.contains { $0.source == "test_nfc_light" })
}

@Test func qSelftestBatteryCopyAndSkipMatchFirmware() {
    let battery = QSelftest.qSequence(hasNFC: true).first { $0.source == "test_battery" }
    #expect(battery?.title == "Battery Test")
    #expect(battery?.body.contains("Connect 3.3v reference cells.") == true)
    #expect(battery?.body.contains("VIN Sense reads: 3.3 volts") == true)
    #expect(battery?.allowsSkip == true)
    #expect(QSelftest.batterySkipKey == "s")
    #expect(QSelftest.batteryAbortReason == "Battery test aborted")
    #expect(QSelftest.batteryVoltageInRange(3.2))
    #expect(QSelftest.batteryVoltageInRange(3.4))
    #expect(!QSelftest.batteryVoltageInRange(3.1))
    #expect(!QSelftest.batteryVoltageInRange(3.5))
}

@Test func qSelftestSecureElementCopyMatchesQFirmware() {
    let se = QSelftest.qSequence(hasNFC: true).filter { $0.source == "test_secure_element" }
    #expect(se.map(\.body) == [
        "^^-- Green?      ",
        "   ^^-- Red?",
        "Wait...",
        "^^-- Green?      ",
    ])
    #expect(se.map(\.led) == [
        .genuineGreen, .genuineRed, .off, .genuineGreen,
    ])
    #expect(QSelftest.secureElementBlockedReason(isBricked: true) == "bricked already")
    #expect(QSelftest.secureElementBlockedReason(isBricked: false) == nil)
}

@Test func qSelftestKeyboardPatternMatchesFirmware() {
    let keys = QSelftest.qSequence(hasNFC: true)
        .filter { $0.source == "test_keyboard" }
        .compactMap(\.keyboardKey)
    #expect(keys == ["1", "w", "d", "v", "g", "y", "7", "k", ".", "p", " ", "QR"])
    #expect(QSelftest.keyboardLabel(for: " ") == "SPACE")
    #expect(QSelftest.keyboardLabel(for: "QR") == "QR")
    #expect(QSelftest.keyboardLabel(for: "w") == "W")
    #expect(QSelftest.keyboardAbortReason == "kbd test aborted")
}

@Test func qSelftestLCDGPUAndLightStoriesMatchFirmware() {
    let steps = QSelftest.qSequence(hasNFC: true)
    let lcd = steps.filter { $0.source == "test_lcd" }
    #expect(lcd.map(\.title) == ["Selftest", "Selftest", "Selftest"])
    #expect(lcd.map(\.body) == [
        "All pixels are RED?",
        "All pixels are GREEN?",
        "All pixels are BLUE?",
    ])
    #expect(lcd.map(\.fill) == [.red, .green, .blue])
    let gpu = steps.first { $0.source == "test_gpu" }
    #expect(gpu?.title == "GPU Test okay?")
    #expect(gpu?.fill == .gpu)
    #expect(steps.first { $0.source == "test_nfc_light" }?.body == "NFC light green? --->")
    #expect(steps.first { $0.source == "test_nfc_light" }?.led == .nfc)
    #expect(steps.first { $0.source == "test_usb_light" }?.title == "USB light is on?")
    #expect(steps.first { $0.source == "test_usb_light" }?.led == .usb)
    let sd = steps.filter { $0.source == "test_sd_active" }.map(\.body)
    #expect(sd == [
        "<-- SD A is ON?  ",
        "<-- SD A is off?  ",
        "<-- SD B is ON?  ",
        "<-- SD B is off?  ",
    ])
}

@Test func qSelftestNFCShareDoesNotAllowEnter() {
    let nfc = QSelftest.qSequence(hasNFC: true).first { $0.source == "test_nfc" }
    #expect(nfc?.interaction == .nfcShare)
    #expect(nfc?.allowsEnter == false)
    #expect(nfc?.hintNFC == true)
    #expect(nfc?.body.contains(DeveloperDebug.nfcTestText(uid: DeveloperDebug.simulatorNFCUID)) == true)
    #expect(nfc?.body.contains("Tap phone to screen, or CANCEL.") == true)
    #expect(QSelftest.nfcAbortReason == "Aborted")
}

@Test func qSelftestPassFailStoriesMatchFirmware() {
    #expect(QSelftest.passTitle == "PASS")
    #expect(QSelftest.passBody == "Selftest complete")
    #expect(QSelftest.failTitle == "FAIL")
    #expect(QSelftest.failBody("Canceled") == "Test failed:\nCanceled")
    #expect(QSelftest.confirmAbortReason == "Canceled")
}

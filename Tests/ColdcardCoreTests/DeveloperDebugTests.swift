import XCTest
@testable import ColdcardCore

/// Firmware developer and debug-menu copy and helpers (`actions.py`, `mk4.py`, `gpu.py`, `nfc.py`, `ux.py`).
final class DeveloperDebugTests: XCTestCase {
    func testDeveloperMenuRequiresConfirmUnlessDevMode() {
        XCTAssertTrue(DeveloperDebug.shouldConfirmOpeningDeveloperMenu(isDevMode: false))
        XCTAssertFalse(DeveloperDebug.shouldConfirmOpeningDeveloperMenu(isDevMode: true))
    }

    func testDeveloperConfirmCopyMatchesFirmware() {
        XCTAssertEqual(DeveloperDebug.confirmTitle, "Are you SURE ?!?")
        XCTAssertEqual(
            DeveloperDebug.confirmBody,
            "Developer features could be used to weaken security or release key material.\n\nDo not proceed unless you know what you are doing and why."
        )
    }

    func testKeyboardTestMatchesFirmwareUxInput() {
        XCTAssertEqual(DeveloperDebug.keyboardTestPrompt, "Keyboard Test")
        XCTAssertEqual(DeveloperDebug.keyboardTestPlaceholder, "(type whatever)")
        XCTAssertEqual(DeveloperDebug.keyboardTestMaxLength, 128)
    }

    func testBKPWOverrideStoriesMatchFirmware() {
        XCTAssertEqual(DeveloperDebug.bkpwMinLength, 32)
        XCTAssertEqual(DeveloperDebug.bkpwMaxLength, 128)
        XCTAssertEqual(DeveloperDebug.bkpwOverrideTitle, "BKPW Override")
        XCTAssertEqual(
            DeveloperDebug.bkpwOverrideBody(hasPassword: false),
            "Password used to encrypt COLDCARD backup files.\n\nPress (0) to change backup password."
        )
        XCTAssertEqual(
            DeveloperDebug.bkpwOverrideBody(hasPassword: true),
            "Password used to encrypt COLDCARD backup files.\n\nPress (0) to change backup password, (1) to forget current password, (2) to show current active backup password."
        )
        XCTAssertEqual(DeveloperDebug.bkpwDeleteConfirm, "Delete current stored password?")
        XCTAssertEqual(
            DeveloperDebug.bkpwShowConfirm,
            "The next screen will show current active backup password.\n\nAnyone with knowledge of the password will be able to decrypt your backups."
        )
        XCTAssertEqual(DeveloperDebug.bkpwShowTitle, "Your Backup Password")
    }

    func testNFCTestPayloadMatchesFirmwareSelftest() {
        XCTAssertEqual(DeveloperDebug.nfcTestText(uid: "DEADBEEF"), "NFC is working: DEADBEEF")
        XCTAssertEqual(DeveloperDebug.simulatorNFCUID, "Q-SIMULATOR")
    }

    func testDebugCrashHooksMatchFirmwareStories() {
        XCTAssertEqual(DeveloperDebug.yikesTitle, ">>>> Yikes!! <<<<")
        XCTAssertEqual(DeveloperDebug.assertFatalBody, "AssertionError: failed assertion")
        XCTAssertEqual(DeveloperDebug.exceptFatalBody, "ZeroDivisionError: divide by zero")
    }

    func testBBQrDemoPayloadIsBinaryAndLarge() throws {
        let data = DeveloperDebug.bbqrDemoPayload()
        XCTAssertEqual(data.count, 2618 * 3)
        XCTAssertEqual(DeveloperDebug.bbqrDemoTitle, "GPU binary")
        XCTAssertEqual(DeveloperDebug.bbqrDemoFileType, BBQrFileType.binary)
        let parts = try BBQr.encode(data, fileType: .binary)
        XCTAssertFalse(parts.isEmpty)
        XCTAssertTrue(parts[0].hasPrefix("B$2B"))
    }

    func testStoredBackupPasswordPrefersOverride() {
        XCTAssertNil(DeveloperDebug.storedBackupPassword(bkpw: nil, lastWords: []))
        XCTAssertEqual(DeveloperDebug.storedBackupPassword(bkpw: "x", lastWords: ["abandon"]), "x")
        XCTAssertEqual(
            DeveloperDebug.storedBackupPassword(bkpw: "", lastWords: Array(repeating: "zoo", count: 12)),
            Array(repeating: "zoo", count: 12).joined(separator: " ")
        )
        XCTAssertNil(DeveloperDebug.storedBackupPassword(bkpw: "", lastWords: ["only", "eleven", "words", "a", "b", "c", "d", "e", "f", "g", "h"]))
    }

    func testSerialREPLStartMatchesDevEnableREPL() {
        XCTAssertEqual(
            DeveloperDebug.serialREPLStart(deltaMode: true, isDevMode: true),
            .wipeDelta
        )
        XCTAssertEqual(
            DeveloperDebug.serialREPLStart(deltaMode: false, isDevMode: false),
            .noopNotDevMode
        )
        XCTAssertEqual(
            DeveloperDebug.serialREPLStart(deltaMode: false, isDevMode: true),
            .showEnabledStory
        )
        XCTAssertEqual(
            DeveloperDebug.serialREPLEnabledStory,
            "The serial port has now been enabled.\n\n3.3v TTL on Tx/Rx/Gnd pads @ 115,200 bps."
        )
        XCTAssertTrue(DeveloperDebug.unixSimulatorIsDevMode)
    }

    func testSerialREPLSessionEnableDisableAndStatus() {
        var session = SerialREPLSession()
        XCTAssertFalse(session.vcpEnabled)
        XCTAssertEqual(session.statusLine, "VCP disabled")

        session.enable()
        XCTAssertTrue(session.vcpEnabled)
        XCTAssertEqual(session.statusLine, "VCP enabled @ 115,200 bps")
        XCTAssertTrue(session.lines.contains("REPL enabled."))

        XCTAssertEqual(session.queryVCPEnabled(), 1)
        XCTAssertEqual(session.setVCPEnabled(false), 0)
        XCTAssertFalse(session.vcpEnabled)
        XCTAssertEqual(session.statusLine, "VCP disabled")
        XCTAssertEqual(session.setVCPEnabled(true), 1)
        XCTAssertTrue(session.vcpEnabled)
    }

    func testSerialREPLEvaluatesCKCCAndHelp() {
        var session = SerialREPLSession()
        session.enable()

        XCTAssertEqual(session.submit("help()"), .output(SerialREPLSession.helpText))
        XCTAssertEqual(session.submit("ckcc.vcp_enabled(None)"), .output("1"))
        XCTAssertEqual(session.submit("ckcc.vcp_enabled(False)"), .output("0"))
        XCTAssertFalse(session.vcpEnabled)
        XCTAssertEqual(session.submit("ckcc.vcp_enabled(True)"), .output("1"))
        XCTAssertTrue(session.vcpEnabled)
        XCTAssertEqual(session.submit("import ckcc"), .silent)
        XCTAssertEqual(session.submit("version.has_qwerty"), .output("True"))
        XCTAssertEqual(session.submit("nope"), .output("NameError: name 'nope' is not defined"))
    }

    func testCheckFirewallReadPassAndFail() {
        XCTAssertEqual(DeveloperDebug.firewallReadAddress, 0x7800)
        XCTAssertEqual(DeveloperDebug.firewallReadLength, 32)
        XCTAssertEqual(DeveloperDebug.checkFirewallRead(firewallIntact: true), .blockedReset)
        XCTAssertEqual(DeveloperDebug.checkFirewallRead(firewallIntact: false), .assertionReached)
        XCTAssertEqual(DeveloperDebug.firewallAssertBody, "AssertionError")
    }

    func testReflashGPUStoriesMatchFirmware() {
        XCTAssertEqual(DeveloperDebug.gpuBundledVersion, "1.3.3")
        XCTAssertEqual(DeveloperDebug.gpuReflashBusyTitle, "Reflashing...")
        XCTAssertEqual(
            DeveloperDebug.gpuReflashConfirm(current: "1.1.1", bundled: "1.3.3"),
            """
            This action reloads the firmware on the GPU co-processor. Should not be needed in normal use.

              Current GPU version is: 1.1.1
                     We have version: 1.3.3

            Continue?
            """
        )
        XCTAssertEqual(
            DeveloperDebug.gpuReflashSuccess(version: "1.3.3"),
            "Upgraded/reflashed.\n\nNew version is: 1.3.3"
        )
        XCTAssertEqual(
            DeveloperDebug.gpuReflashFailure(detail: "gpu.py:345"),
            "GPU Flash Failed!\n\ngpu.py:345"
        )
        XCTAssertEqual(DeveloperDebug.reflashGPU(succeed: true), .success("1.3.3"))
        XCTAssertEqual(DeveloperDebug.reflashGPU(succeed: false), .failure("gpu.py:345"))
    }
}

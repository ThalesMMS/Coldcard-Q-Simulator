import Foundation

/// Firmware `shared/selftest.py` `start_selftest` for Coldcard Q.
///
/// Simulated step names, order, copy, and pass/fail UX — not ATECC/DS28C36 silicon.
public enum QSelftest: Sendable {
    public enum LCDFill: Equatable, Sendable {
        case red, green, blue, gpu
    }

    public enum LED: Equatable, Sendable {
        case off
        case genuineGreen
        case genuineRed
        case nfc
        case usb
        case sdA(on: Bool)
        case sdB(on: Bool)
    }

    public enum Interaction: Equatable, Sendable {
        /// Firmware `wait_ok` (`y` / ENTER pass, `x` / CANCEL fail).
        case confirm
        case keyboard
        /// PSRAM / MicroSD I/O / `Wait...` genuine switch — no key.
        case auto
        /// Firmware `NFCHandler.selftest` / `share_start(allow_enter=False)`.
        case nfcShare
    }

    public struct Step: Equatable, Sendable {
        public var source: String
        public var interaction: Interaction
        public var title: String
        public var body: String
        public var fill: LCDFill?
        public var led: LED
        public var keyboardKey: String?
        public var allowsSkip: Bool
        public var allowsEnter: Bool
        public var hintNFC: Bool
        public var abortReason: String

        public init(
            source: String,
            interaction: Interaction,
            title: String = "",
            body: String = "",
            fill: LCDFill? = nil,
            led: LED = .off,
            keyboardKey: String? = nil,
            allowsSkip: Bool = false,
            allowsEnter: Bool = true,
            hintNFC: Bool = false,
            abortReason: String = QSelftest.confirmAbortReason
        ) {
            self.source = source
            self.interaction = interaction
            self.title = title
            self.body = body
            self.fill = fill
            self.led = led
            self.keyboardKey = keyboardKey
            self.allowsSkip = allowsSkip
            self.allowsEnter = allowsEnter
            self.hintNFC = hintNFC
            self.abortReason = abortReason
        }
    }

    public static let batterySkipKey = "s"
    public static let batteryAbortReason = "Battery test aborted"
    public static let keyboardAbortReason = "kbd test aborted"
    public static let confirmAbortReason = "Canceled"
    public static let nfcAbortReason = "Aborted"
    public static let nfcTapPrompt = "Tap phone to screen, or CANCEL."
    public static let passTitle = "PASS"
    public static let passBody = "Selftest complete"
    public static let failTitle = "FAIL"

    /// Firmware `test_keyboard` keys: one per row/column plus QR (`KEY_QR`).
    public static let keyboardKeys = ["1", "w", "d", "v", "g", "y", "7", "k", ".", "p", " ", "QR"]

    public static func failBody(_ reason: String) -> String {
        "Test failed:\n" + reason
    }

    public static func batteryVoltageInRange(_ volts: Double) -> Bool {
        volts >= 3.2 && volts <= 3.4
    }

    public static func batteryVINLine(_ volts: Double) -> String {
        String(format: "VIN Sense reads: %.1f volts", volts)
    }

    /// Firmware `assert not get_is_bricked()` comment.
    public static func secureElementBlockedReason(isBricked: Bool) -> String? {
        isBricked ? "bricked already" : nil
    }

    public static func keyboardLabel(for key: String) -> String {
        if key == " " { return "SPACE" }
        if key == "QR" { return "QR" }
        return key.uppercased()
    }

    /// Q factory sequence. NFC is gated on hardware presence (`version.has_nfc`), not the
    /// Settings → NFC Sharing user flag (`settings.nfc`).
    public static func qSequence(
        hasNFC: Bool = true,
        nfcUID: String = DeveloperDebug.simulatorNFCUID
    ) -> [Step] {
        var steps: [Step] = [
            Step(
                source: "test_battery",
                interaction: .confirm,
                title: "Battery Test",
                body: "Connect 3.3v reference cells.\n\n" + batteryVINLine(3.3),
                allowsSkip: true,
                abortReason: batteryAbortReason
            ),
            Step(
                source: "test_qr_scanner",
                interaction: .confirm,
                title: "QR Scanner",
                body: "V2.sim"
            ),
            lcdStep(color: "RED", fill: .red),
            lcdStep(color: "GREEN", fill: .green),
            lcdStep(color: "BLUE", fill: .blue),
            Step(source: "test_gpu", interaction: .confirm, title: "GPU Test okay?", fill: .gpu),
            Step(source: "test_psram", interaction: .auto, title: "PSRAM Test"),
            Step(
                source: "test_nfc_light",
                interaction: .confirm,
                body: "NFC light green? --->",
                led: .nfc
            ),
        ]
        if hasNFC {
            let payload = DeveloperDebug.nfcTestText(uid: nfcUID)
            steps.append(
                Step(
                    source: "test_nfc",
                    interaction: .nfcShare,
                    body: payload + "\n\n" + nfcTapPrompt,
                    allowsEnter: false,
                    hintNFC: true,
                    abortReason: nfcAbortReason
                )
            )
        }
        for key in keyboardKeys {
            steps.append(
                Step(
                    source: "test_keyboard",
                    interaction: .keyboard,
                    title: "",
                    body: "Keyboard Test. Press:\n\n" + keyboardLabel(for: key),
                    keyboardKey: key,
                    abortReason: keyboardAbortReason
                )
            )
        }
        steps.append(contentsOf: [
            Step(
                source: "test_secure_element",
                interaction: .confirm,
                body: "^^-- Green?      ",
                led: .genuineGreen
            ),
            Step(
                source: "test_secure_element",
                interaction: .confirm,
                body: "   ^^-- Red?",
                led: .genuineRed
            ),
            Step(
                source: "test_secure_element",
                interaction: .auto,
                title: "Wait...",
                body: "Wait..."
            ),
            Step(
                source: "test_secure_element",
                interaction: .confirm,
                body: "^^-- Green?      ",
                led: .genuineGreen
            ),
            sdActive(slot: "A", on: true),
            sdActive(slot: "A", on: false),
            sdActive(slot: "B", on: true),
            sdActive(slot: "B", on: false),
            Step(
                source: "test_usb_light",
                interaction: .confirm,
                title: "USB light is on?",
                led: .usb
            ),
            Step(
                source: "test_microsd",
                interaction: .auto,
                title: "MicroSD Card:",
                body: "Testing"
            ),
        ])
        return steps
    }

    private static func lcdStep(color: String, fill: LCDFill) -> Step {
        Step(
            source: "test_lcd",
            interaction: .confirm,
            title: "Selftest",
            body: "All pixels are \(color)?",
            fill: fill
        )
    }

    private static func sdActive(slot: String, on: Bool) -> Step {
        let lit = on ? "ON" : "off"
        let led: LED = slot == "A" ? .sdA(on: on) : .sdB(on: on)
        return Step(
            source: "test_sd_active",
            interaction: .confirm,
            body: "<-- SD \(slot) is \(lit)?  ",
            led: led
        )
    }
}

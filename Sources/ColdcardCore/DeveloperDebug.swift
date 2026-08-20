import Foundation

/// Firmware developer and debug-menu copy and helpers (`actions.py`, `nfc.py`, `ux.py`).
public enum DeveloperDebug: Sendable {
    public static let confirmTitle = "Are you SURE ?!?"
    public static let confirmBody = "Developer features could be used to weaken security or release key material.\n\nDo not proceed unless you know what you are doing and why."

    public static let keyboardTestPrompt = "Keyboard Test"
    public static let keyboardTestPlaceholder = "(type whatever)"
    public static let keyboardTestMaxLength = 128

    public static let bkpwMinLength = 32
    public static let bkpwMaxLength = 128
    public static let bkpwOverrideTitle = "BKPW Override"
    public static let bkpwDeleteConfirm = "Delete current stored password?"
    public static let bkpwShowConfirm = "The next screen will show current active backup password.\n\nAnyone with knowledge of the password will be able to decrypt your backups."
    public static let bkpwShowTitle = "Your Backup Password"
    public static let bkpwPasswordPrompt = "Password"
    public static let savedPause = "Saved."
    public static let deletedPause = "Deleted."

    public static let simulatorNFCUID = "Q-SIMULATOR"
    public static let bbqrDemoTitle = "GPU binary"
    public static let bbqrDemoFileType = BBQrFileType.binary
    /// Firmware `gpu_binary.BINARY` length (bytes before `*3`).
    public static let gpuBinaryLength = 2618

    public static let yikesTitle = ">>>> Yikes!! <<<<"
    public static let assertFatalBody = "AssertionError: failed assertion"
    public static let exceptFatalBody = "ZeroDivisionError: divide by zero"

    public static func shouldConfirmOpeningDeveloperMenu(isDevMode: Bool) -> Bool {
        !isDevMode
    }

    public static func bkpwOverrideBody(hasPassword: Bool) -> String {
        var message = "Password used to encrypt COLDCARD backup files.\n\nPress (0) to change backup password"
        if hasPassword {
            message += ", (1) to forget current password, (2) to show current active backup password."
        } else {
            message += "."
        }
        return message
    }

    public static func nfcTestText(uid: String) -> String {
        "NFC is working: \(uid)"
    }

    /// Original stand-in for firmware `BINARY*3` BBQr Demo — same length, not GPU firmware.
    public static func bbqrDemoPayload() -> Data {
        var block = Data(count: gpuBinaryLength)
        for index in 0..<gpuBinaryLength {
            block[index] = UInt8((index &* 37 &+ 11) & 0xff)
        }
        return block + block + block
    }

    /// Firmware `settings.get('bkpw')`, with the 12-word cached backup password as fallback.
    public static func storedBackupPassword(bkpw: String?, lastWords: [String]) -> String? {
        if let bkpw, !bkpw.isEmpty { return bkpw }
        if lastWords.count == 12 { return lastWords.joined(separator: " ") }
        return nil
    }

    /// Unix `variant/version.py`: `is_devmode = True`. This iOS simulator matches that for Serial REPL.
    public static let unixSimulatorIsDevMode = true

    /// Firmware `mk4.dev_enable_repl` story after `ckcc.vcp_enabled(True)`.
    public static let serialREPLEnabledStory =
        "The serial port has now been enabled.\n\n3.3v TTL on Tx/Rx/Gnd pads @ 115,200 bps."

    /// Firmware `check_firewall_read`: `uctypes.bytes_at(0x7800, 32)`.
    public static let firewallReadAddress: UInt32 = 0x7800
    public static let firewallReadLength = 32
    /// Bare `assert False` if the firewall did not reset the MCU.
    public static let firewallAssertBody = "AssertionError"

    /// Firmware `gpu_binary.VERSION`.
    public static let gpuBundledVersion = "1.3.3"
    /// Firmware `dis.fullscreen('Reflashing...')`.
    public static let gpuReflashBusyTitle = "Reflashing..."

    /// Firmware `dev_enable_repl`: delta wipe, then `version.is_devmode` gate, then enable story.
    public static func serialREPLStart(deltaMode: Bool, isDevMode: Bool) -> SerialREPLStart {
        if deltaMode { return .wipeDelta }
        if !isDevMode { return .noopNotDevMode }
        return .showEnabledStory
    }

    /// Firmware `check_firewall_read`: a working firewall resets before `assert False`.
    public static func checkFirewallRead(firewallIntact: Bool) -> FirewallReadResult {
        firewallIntact ? .blockedReset : .assertionReached
    }

    /// Firmware `gpu.reflash_gpu_ux` confirm story.
    public static func gpuReflashConfirm(current: String, bundled: String = gpuBundledVersion) -> String {
        """
        This action reloads the firmware on the GPU co-processor. Should not be needed in normal use.

          Current GPU version is: \(current)
                 We have version: \(bundled)

        Continue?
        """
    }

    public static func gpuReflashSuccess(version: String) -> String {
        "Upgraded/reflashed.\n\nNew version is: \(version)"
    }

    public static func gpuReflashFailure(detail: String) -> String {
        "GPU Flash Failed!\n\n\(detail)"
    }

    /// Simulated `GPUAccess.upgrade()`. Failure uses `problem_file_line` style `gpu.py:345`.
    public static func reflashGPU(succeed: Bool) -> GPUReflashOutcome {
        succeed ? .success(gpuBundledVersion) : .failure("gpu.py:345")
    }
}

public enum SerialREPLStart: Equatable, Sendable {
    case wipeDelta
    case noopNotDevMode
    case showEnabledStory
}

public enum FirewallReadResult: Equatable, Sendable {
    /// Firewall blocked the bootloader read; the MCU resets.
    case blockedReset
    /// Read succeeded; firmware `assert False` is reached.
    case assertionReached
}

public enum GPUReflashOutcome: Equatable, Sendable {
    case success(String)
    case failure(String)
}

public enum SerialREPLSubmitResult: Equatable, Sendable {
    case output(String)
    case silent
}

/// In-app stand-in for the serial MicroPython REPL after `dev_enable_repl`.
public struct SerialREPLSession: Equatable, Sendable {
    public var vcpEnabled = false
    public var lines: [String] = []

    public static let helpText =
        "Type ckcc.vcp_enabled(True|False|None), version.has_qwerty, or help()."

    public init() {}

    public var statusLine: String {
        vcpEnabled ? "VCP enabled @ 115,200 bps" : "VCP disabled"
    }

    public mutating func enable() {
        vcpEnabled = true
        if !lines.contains("REPL enabled.") {
            lines.append("REPL enabled.")
        }
    }

    public func queryVCPEnabled() -> Int { vcpEnabled ? 1 : 0 }

    @discardableResult
    public mutating func setVCPEnabled(_ enabled: Bool) -> Int {
        vcpEnabled = enabled
        return queryVCPEnabled()
    }

    @discardableResult
    public mutating func submit(_ raw: String) -> SerialREPLSubmitResult {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(">>> \(raw)")
        guard !line.isEmpty else { return .silent }
        let result = evaluate(line)
        if case .output(let text) = result {
            lines.append(text)
        }
        return result
    }

    private mutating func evaluate(_ line: String) -> SerialREPLSubmitResult {
        if line == "help" || line == "help()" { return .output(Self.helpText) }
        if line == "import ckcc" || line == "import version" { return .silent }
        if line == "version.has_qwerty" { return .output("True") }
        if let argument = Self.parseVCPEnabled(line) {
            switch argument {
            case .query:
                return .output("\(queryVCPEnabled())")
            case .set(let enabled):
                return .output("\(setVCPEnabled(enabled))")
            }
        }
        if line.first?.isLetter == true || line.hasPrefix("_") {
            let name = Self.firstIdentifier(line)
            return .output("NameError: name '\(name)' is not defined")
        }
        return .output("SyntaxError: invalid syntax")
    }

    private enum VCPArgument: Equatable {
        case query
        case set(Bool)
    }

    private static func parseVCPEnabled(_ line: String) -> VCPArgument? {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.hasPrefix("ckcc.vcp_enabled("), compact.hasSuffix(")") else { return nil }
        let inner = String(compact.dropFirst("ckcc.vcp_enabled(".count).dropLast())
        switch inner {
        case "None": return .query
        case "True", "1": return .set(true)
        case "False", "0": return .set(false)
        default: return nil
        }
    }

    private static func firstIdentifier(_ line: String) -> String {
        var name = ""
        for character in line {
            if character.isLetter || character == "_" || (!name.isEmpty && character.isNumber) {
                name.append(character)
            } else if name.isEmpty {
                continue
            } else {
                break
            }
        }
        return name.isEmpty ? line : name
    }
}

import Foundation

/// Firmware `drv_entro.password_entry` / `send_keystrokes`.
/// USB HID gadget is out of scope; the simulator sends via clipboard and confirms
/// the keystrokes that would have been typed (`password` + Enter).
public enum TypePasswords {
    /// `ux_enter_bip32_index` default max (`unlimited=False`). Type Passwords does not honor `b85max`.
    public static let maxIndex: UInt32 = 9999

    public static func isHomeItemVisible(keyboardEmuEnabled: Bool, hasSecrets: Bool) -> Bool {
        keyboardEmuEnabled && hasSecrets
    }

    public static func path(index: UInt32) -> String {
        "m/83696968h/707764h/\(BIP85.passwordLength)h/\(index)h"
    }

    public static func parseIndex(_ raw: String) -> UInt32 {
        guard !raw.isEmpty, let value = UInt32(raw) else { return 0 }
        return min(value, maxIndex)
    }

    /// Firmware `ux_enter_number`: four-digit field, clamps as digits are typed.
    public static func appendDigit(_ current: String, _ digit: Character) -> String {
        guard digit.isNumber else { return current }
        let maxWidth = String(maxIndex).count
        var next: String
        if current.count >= maxWidth {
            next = String(current.dropLast()) + String(digit)
        } else {
            next = current + String(digit)
        }
        guard let value = UInt32(next) else { return current }
        return String(min(value, maxIndex))
    }

    public static func sendPrompt(okKey: String, password: String, path: String) -> String {
        var msg = "Place mouse at required password prompt, then press \(okKey) to send keystrokes."
        if !path.isEmpty {
            msg += "\n\nPassword:\n\(password)"
            msg += "\n\nPath:\n\(path)"
        }
        return msg
    }

    /// Firmware `kbd.send_keystrokes(password + '\r')`.
    public static func keystrokes(password: String) -> String {
        password + "\r"
    }

    /// Pasteable substitute for USB HID (password only; Enter is shown on-screen).
    public static func clipboardPayload(password: String) -> String {
        password
    }

    public static func sentConfirmation(password: String) -> String {
        """
        Sent.

        Copied to clipboard.

        Would have typed:
        \(password)
        [Enter]
        """
    }
}

/// Firmware `usb.EmulatedKeyboard` HID character map and `can_type`.
public enum EmulatedKeyboard {
    /// Keys the gadget can type after `.lower()` (`usb.py` `char_map`).
    public static let charMap: Set<String> = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", " ",
        "/", "*", "-", "+", "\r"
    ]

    public static func canType(_ string: String) -> Bool {
        string.allSatisfy { charMap.contains(String($0).lowercased()) }
    }
}

public enum HardwareKey: Hashable, Sendable {
    case power, qr, nfc, tab, up, down, left, right, enter, cancel
    case home, pageUp, pageDown, end
    case character(String)
    case backspace, space, shift, symbol, clear, lamp
}

public enum HardwareKeyboardInput: Equatable, Sendable {
    case characters(String)
    case upArrow, downArrow, leftArrow, rightArrow
    case home, end, pageUp, pageDown
    case returnKey, escape, delete, tab, shift, symbol, lamp
}

public enum HardwareKeyboardMapper {
    public static func map(_ input: HardwareKeyboardInput) -> HardwareKey? {
        switch input {
        case .characters(let value):
            let normalized = value.lowercased()
            if normalized == " " { return .space }
            guard value.utf8.count == 1, let ascii = value.utf8.first,
                  (33...126).contains(ascii) else { return nil }
            return .character(value)
        case .upArrow: return .up
        case .downArrow: return .down
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .home: return .home
        case .end: return .end
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .returnKey: return .enter
        case .escape: return .cancel
        case .delete: return .backspace
        case .tab: return .tab
        case .shift: return .shift
        case .symbol: return .symbol
        case .lamp: return .lamp
        }
    }

    /// Q `DECODER_SYMBOL` overlay (`shared/charcodes.py`): unshifted key → symbol-layer character.
    public static func symbolLayer(_ unshifted: String) -> String? {
        guard let first = unshifted.lowercased().first else { return nil }
        let map: [Character: Character] = [
            "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
            "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
            "q": "-", "w": "_", "e": "`",
            "u": "[", "i": "]", "o": "{", "p": "}",
            "a": "+", "f": "=", "g": ":", "h": ";", "j": "~",
            "k": "|", "l": "\\", "'": "\"",
            ",": "<", ".": ">", "/": "?"
        ]
        return map[first].map(String.init)
    }

    /// Q `DECODER_SYMBOL` z-row: F1–F6 occupy z, x, c, v, b, n (`charcodes.py`).
    public static func symbolFunctionKey(_ unshifted: String) -> Int? {
        switch unshifted.lowercased() {
        case "z": 1
        case "x": 2
        case "c": 3
        case "v": 4
        case "b": 5
        case "n": 6
        default: nil
        }
    }

    /// Q `DECODER_SYMBOL` d-pad: Left/Up/Down/Right → HOME / PAGE_UP / PAGE_DOWN / END.
    public static func symbolOverlay(_ key: HardwareKey) -> HardwareKey {
        switch key {
        case .left: .home
        case .up: .pageUp
        case .down: .pageDown
        case .right: .end
        default: key
        }
    }

    /// Q `DECODER_SHIFT`: undocumented Shift+Delete → KEY_CLEAR.
    public static func shiftOverlay(_ key: HardwareKey) -> HardwareKey {
        key == .backspace ? .clear : key
    }

    /// Held SYM/SHIFT (`keyboard.py`: caps, else SYMBOL, else SHIFT). Caps keeps arrows.
    public static func applyHeldModifiers(_ key: HardwareKey, symbol: Bool, shift: Bool, caps: Bool) -> HardwareKey {
        if caps { return key }
        if symbol { return symbolOverlay(key) }
        if shift { return shiftOverlay(key) }
        return key
    }
}

/// Q `ux.py` story paging (`STORY_H = CHARS_H`) and `menu.py` `PER_M = CHARS_H - 1`.
public enum FirmwareStoryPaging {
    public static let height = 10
    /// `menu.py` `PER_M = CHARS_H - 1` (page up/down steps).
    public static let menuPageSize = 9

    public enum Command: Sendable {
        case home, end, pageUp, pageDown
    }

    /// `ux.py` story digits: `0`/HOME, `7`/PAGE_UP, `9`/PAGE_DOWN.
    public static func digitCommand(_ value: String) -> Command? {
        switch value {
        case "0": .home
        case "7": .pageUp
        case "9": .pageDown
        default: nil
        }
    }

    public static func apply(top: Int, lineCount: Int, command: Command) -> Int {
        switch command {
        case .home:
            return 0
        case .end:
            return max(0, lineCount - (height / 2))
        case .pageUp:
            return max(0, top - height)
        case .pageDown:
            return min(max(0, lineCount - 2), top + height)
        }
    }
}

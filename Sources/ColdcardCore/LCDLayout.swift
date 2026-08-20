/// Q LCD geometry from `shared/lcd_display.py` (`CHARS_W=34`, `CHARS_H=10`).
public enum LCDDisplay {
    public static let charsW = 34
    public static let charsH = 10
    /// `font_iosevka.CELL_W` / `CELL_H` (pixels on a 320×240 Q LCD).
    public static let cellW = 9
    public static let cellH = 22
    public static let leftMargin = 7
    public static let topMargin = 15
    public static let progressBarH = 5
    public static let scrollBarW = 5
    /// `ux.py` `CH_PER_W = CHARS_W - 1` on Q.
    public static let storyWrapWidth = 33
    public static let storyHeight = 10
    /// `menu.py` `PER_M = CHARS_H - 1`.
    public static let menuPerPage = 9
    /// `menu.show` draws `range(PER_M+1)` rows.
    public static let menuVisibleRows = 10

    public static let noWrap = Character(UnicodeScalar(3)!)
    public static let addressMarker = Character(UnicodeScalar(2)!)
    /// Q `utils.word_wrap` address groups: 6 × 4 characters.
    public static let addressWrapWidth = 24

    /// Firmware `utils.show_single_address`.
    public static func showSingleAddress(_ addr: String) -> String {
        String(addressMarker) + addr
    }

    /// Firmware `utils.chunk_address`.
    public static func chunkAddress(_ addr: String) -> [String] {
        var groups: [String] = []
        var rest = Substring(addr)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(4)))
            rest = rest.dropFirst(4)
        }
        return groups
    }

    /// Spaced 4-character groups for iPhone / plaintext stories.
    public static func spacedAddress(_ addr: String) -> String {
        chunkAddress(addr).joined(separator: " ")
    }

    /// Firmware `lcd_display._draw_addr` invert payload: `' '+' '.join(chunk_address(addr))+' '`.
    public static func drawnAddress(_ addr: String) -> String {
        " " + spacedAddress(addr) + " "
    }

    /// Replace `OUT_CTRL_ADDRESS` lines with spaced addresses (iPhone story body).
    public static func storyPlaintext(_ body: String) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let text = String(line)
            if text.first == addressMarker {
                return spacedAddress(String(text.dropFirst()))
            }
            return text
        }.joined(separator: "\n")
    }

    /// `FontIosevka.DOUBLE_WIDE` (`font_iosevka.py`).
    public static let doubleWide: Set<Character> = [
        "⋯", "✔", "✓", "→", "←", "↦", "◉", "◯", "◌", "※", "—",
        "\u{0e}", "\u{11}", "\t", "\u{0f}", "\u{12}", "\u{13}", "\u{14}", "\u{16}", "\u{17}"
    ]

    public static func width(_ msg: String) -> Int {
        msg.count + msg.reduce(0) { $1.isDoubleWideLCD ? $0 + 1 : $0 }
    }

    /// Invert span for `menu_draw`: `' '+msg+' '`.
    public static func menuInvertCellCount(label: String) -> Int {
        width(" " + label + " ")
    }

    /// Firmware `utils.word_wrap`.
    public static func wordWrap(_ line: String, width: Int) -> [String] {
        var ln = Array(line)
        if ln.first == noWrap {
            return [String(ln.dropFirst())]
        }
        var result: [String] = []
        while true {
            var length = 0
            var space: Int?
            var broke = false
            var idx = 0
            for (i, ch) in ln.enumerated() {
                idx = i
                if ch == " " { space = i }
                length += 1
                if ch.isDoubleWideLCD { length += 1 }
                if length > width {
                    if ".,:;".contains(ch) {
                        idx = i + 1
                        space = nil
                    }
                    broke = true
                    break
                }
            }
            if !broke {
                result.append(String(ln))
                return result
            }
            let splitAt: Int
            var nextStart: Int
            if let space {
                splitAt = space
                nextStart = space + 1
            } else if ln.first == addressMarker {
                let addr = String(ln.dropFirst())
                var pos = addr.startIndex
                while pos < addr.endIndex {
                    let end = addr.index(pos, offsetBy: addressWrapWidth, limitedBy: addr.endIndex) ?? addr.endIndex
                    result.append(String(addressMarker) + String(addr[pos..<end]))
                    pos = end
                }
                return result
            } else {
                splitAt = min(idx, ln.count)
                nextStart = splitAt
                if splitAt < ln.count, ln[splitAt] == " " {
                    nextStart += 1
                }
            }
            result.append(String(ln[..<min(splitAt, ln.count)]))
            if nextStart >= ln.count { return result }
            ln = Array(ln[nextStart...])
            if ln.isEmpty { return result }
        }
    }
}

public enum LCDHintIcon: String, Equatable, Hashable, Sendable {
    case qr, nfc
}

public enum LCDStoryLine: Equatable, Sendable {
    case title(String, hints: [LCDHintIcon])
    case text(String)
    case address(String)
    case eot
    case blank

    public var isTitle: Bool {
        if case .title = self { return true }
        return false
    }

    public var isEOT: Bool {
        if case .eot = self { return true }
        return false
    }

    public var isBlank: Bool {
        switch self {
        case .blank: true
        case .text(let value): value.isEmpty
        default: false
        }
    }

    public var text: String {
        switch self {
        case .title(let title, _): title
        case .text(let value): value
        case .address(let value): value
        case .eot: LCDStory.eotBar
        case .blank: ""
        }
    }

    public var cellWidth: Int {
        switch self {
        case .title(let title, let hints):
            min(LCDDisplay.charsW, LCDDisplay.width(" " + title + " ") + hints.count * 2)
        case .text(let value), .address(let value):
            min(LCDDisplay.charsW, LCDDisplay.width(value))
        case .eot:
            LCDDisplay.charsW
        case .blank:
            0
        }
    }
}

/// Firmware `ux_show_story` + `draw_story`.
public enum LCDStory {
    public static let eotBar = String(repeating: "┅", count: LCDDisplay.charsW)

    public static func compose(title: String?, body: String, hintQR: Bool = false, hintNFC: Bool = false) -> [LCDStoryLine] {
        var lines: [LCDStoryLine] = []
        let heading = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !heading.isEmpty {
            var hints: [LCDHintIcon] = []
            if hintQR { hints.append(.qr) }
            if hintNFC { hints.append(.nfc) }
            lines.append(.title(heading, hints: hints))
            lines.append(.blank)
        }
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            for wrapped in LCDDisplay.wordWrap(String(raw), width: LCDDisplay.storyWrapWidth) {
                if wrapped.first == LCDDisplay.addressMarker {
                    lines.append(.address(String(wrapped.dropFirst())))
                } else {
                    lines.append(.text(wrapped))
                }
            }
        }
        while let last = lines.last, last.isBlank {
            lines.removeLast()
        }
        if lines.isEmpty {
            lines.append(.blank)
        }
        lines.append(.eot)
        return lines
    }

    public static func move(top: Int, lineCount: Int, nav: FirmwareStoryPaging.Command) -> Int {
        FirmwareStoryPaging.apply(top: top, lineCount: lineCount, command: nav)
    }

    public static func visible(lines: [LCDStoryLine], top: Int) -> ArraySlice<LCDStoryLine> {
        guard !lines.isEmpty else { return [] }
        let start = min(max(0, top), lines.count)
        let end = min(lines.count, start + LCDDisplay.storyHeight)
        if start >= end { return lines.suffix(min(LCDDisplay.storyHeight, lines.count)) }
        return lines[start..<end]
    }
}

/// Firmware `MenuSystem` cursor + `ypos` (`shared/menu.py`).
public struct LCDMenuPager: Equatable, Sendable {
    public var cursor: Int
    public var ypos: Int
    public var count: Int
    public var wrap: Bool

    public init(count: Int, wrap: Bool, cursor: Int = 0, ypos: Int = 0) {
        self.count = max(0, count)
        self.wrap = wrap
        self.cursor = min(max(0, cursor), max(0, count - 1))
        self.ypos = max(0, ypos)
    }

    public var visibleIndices: Range<Int> {
        let start = min(ypos, max(0, count))
        let end = min(count, start + LCDDisplay.menuVisibleRows)
        return start..<end
    }

    public var selectedRow: Int? {
        let row = cursor - ypos
        return (0..<LCDDisplay.menuVisibleRows).contains(row) ? row : nil
    }

    public var showsScrollBar: Bool { count > LCDDisplay.menuPerPage }

    public mutating func down() {
        guard count > 0 else { return }
        if cursor < count - 1 {
            cursor += 1
            if cursor - ypos >= LCDDisplay.menuPerPage - 1 {
                ypos += 1
            }
        } else if wrap {
            gotoIndex(0)
        }
    }

    public mutating func up() {
        guard count > 0 else { return }
        if cursor > 0 {
            cursor -= 1
            if cursor < ypos {
                ypos -= 1
            }
        } else if wrap {
            gotoIndex(count - 1)
        }
    }

    public mutating func page(_ direction: Int) {
        if direction >= 0 {
            for _ in 0..<LCDDisplay.menuPerPage { down() }
        } else {
            for _ in 0..<LCDDisplay.menuPerPage { up() }
        }
    }

    public mutating func home() {
        cursor = 0
        ypos = 0
    }

    public mutating func gotoIndex(_ n: Int) {
        guard count > 0 else {
            cursor = 0
            ypos = 0
            return
        }
        let index = min(max(0, n), count - 1)
        cursor = index
        if index < LCDDisplay.menuPerPage - 1 {
            ypos = 0
        } else {
            ypos = index - 2
        }
    }
}

public struct LCDScrollBar: Equatable, Sendable {
    public var thumbOffset: Int
    public var thumbHeight: Int

    /// Firmware `_draw_scroll_bar` (`lcd_display.py`).
    public static func geometry(offset: Int, count: Int, perPage: Int, activeHeight: Int) -> LCDScrollBar {
        let safeCount = max(count, 1)
        let pages = max(Double(safeCount) / Double(max(perPage, 1)), 2)
        let thumbHeight = max(Int(Double(activeHeight) / pages), 4)
        var pos = Int(Double(activeHeight - thumbHeight) * (Double(offset) / Double(safeCount)))
        let isLast = offset != 0 && offset + perPage >= safeCount
        if isLast {
            pos = activeHeight - thumbHeight
        }
        return LCDScrollBar(thumbOffset: max(0, pos), thumbHeight: thumbHeight)
    }
}

public enum LCDPowerIcon: Equatable, Sendable {
    case plugged
    case battery(Int)
}

public enum LCDStatus {
    public static func xfpGlyphs(_ xfp: String) -> String {
        String(xfp.filter(\.isHexDigit).prefix(8)).lowercased()
    }

    public static func showsXFP(_ xfp: String?) -> Bool {
        guard let xfp else { return false }
        return !xfpGlyphs(xfp).isEmpty
    }

    /// Firmware `stash.bip39_passphrase` → `bip39_1` icon.
    public static func bip39IconOn(passphrase: String) -> Bool { !passphrase.isEmpty }

    /// Firmware `pa.tmp_value` → `tmp_1` icon. Passphrase-only wallets do not set this.
    public static func tmpIconOn(hasEphemeralSeed: Bool) -> Bool { hasEphemeralSeed }

    /// Firmware `get_batt_threshold`: `None` (USB / charging) → plugged; else 0…3.
    public static func powerIcon(level: Float, isCharging: Bool, isUnknown: Bool) -> LCDPowerIcon {
        if isCharging { return .plugged }
        if isUnknown { return .plugged }
        if level <= 0.15 { return .battery(0) }
        if level <= 0.40 { return .battery(1) }
        if level <= 0.70 { return .battery(2) }
        return .battery(3)
    }
}

/// GPU `busy_bar` stripes (`unix/simulator.py` `gpu_draw_busy`) and `progress_bar` fill.
public enum LCDBusyBar {
    public static let phaseCount = 16
    public static let pixelWidth = 320

    public static func isForeground(x: Int, phase: Int) -> Bool {
        let index = phaseCount - (phase % phaseCount) - 1 + x
        let wrapped = index % 8
        return wrapped >= 2
    }

    public static func fillWidth(progress: Double, total: Int) -> Int {
        let clamped = min(1, max(0, progress))
        return Int(Double(total) * clamped)
    }
}

private extension Character {
    var isDoubleWideLCD: Bool { LCDDisplay.doubleWide.contains(self) }
}

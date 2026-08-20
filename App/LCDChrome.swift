import SwiftUI
import UIKit
import ColdcardCore

/// Q LCD orange (`COL_TEXT` 0xfd60).
let lcdText = Color(red: 1.0, green: 174.0 / 255.0, blue: 0)
let lcdMuted = Color(red: 163.0 / 255.0, green: 112.0 / 255.0, blue: 0)
let lcdScrollTrack = Color(red: 80.0 / 255.0, green: 56.0 / 255.0, blue: 0)

struct LCDScreenMetrics: Equatable {
    var size: CGSize
    var statusHeight: CGFloat
    var progressHeight: CGFloat
    var cellWidth: CGFloat
    var cellHeight: CGFloat
    var leftMargin: CGFloat
    var hairline: CGFloat

    static func make(size: CGSize) -> LCDScreenMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let status = height * CGFloat(LCDDisplay.topMargin) / 240
        let progress = height * CGFloat(LCDDisplay.progressBarH) / 240
        let hairline: CGFloat = 1
        let left = width * CGFloat(LCDDisplay.leftMargin) / 320
        let contentH = max(1, height - status - progress - hairline)
        return LCDScreenMetrics(
            size: size,
            statusHeight: status,
            progressHeight: progress,
            cellWidth: width * CGFloat(LCDDisplay.cellW) / 320,
            cellHeight: contentH / CGFloat(LCDDisplay.charsH),
            leftMargin: left,
            hairline: hairline
        )
    }

    var fontSize: CGFloat { min(cellWidth * 1.15, cellHeight * 0.72) }
    /// Monospace size that fits `CHARS_W` columns in `cellWidth` (no Iosevka vendor).
    var monoFontSize: CGFloat {
        let probe: CGFloat = 24
        let font = UIFont.monospacedSystemFont(ofSize: probe, weight: .medium)
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        let fitted = cellWidth * probe / max(advance, 0.1)
        return min(fitted, cellHeight * 0.92)
    }
    var contentHeight: CGFloat { cellHeight * CGFloat(LCDDisplay.charsH) }

    /// Content-area 34×10 grid (status/progress already stripped by the parent).
    static func characterGrid(size: CGSize) -> LCDScreenMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        return LCDScreenMetrics(
            size: CGSize(width: width, height: height),
            statusHeight: 0,
            progressHeight: 0,
            cellWidth: width / CGFloat(LCDDisplay.charsW),
            cellHeight: height / CGFloat(LCDDisplay.charsH),
            leftMargin: 0,
            hairline: 1
        )
    }
}

private struct LCDMetricsKey: EnvironmentKey {
    static let defaultValue = LCDScreenMetrics.make(size: CGSize(width: 320, height: 240))
}

extension EnvironmentValues {
    var lcdMetrics: LCDScreenMetrics {
        get { self[LCDMetricsKey.self] }
        set { self[LCDMetricsKey.self] = newValue }
    }
}

struct LCDStatusBar: View {
    @Bindable var store: SimulatorStore
    @Environment(\.lcdMetrics) private var metrics

    /// Keep a visible strip even if a 34×10 content grid injects `statusHeight` 0.
    private var barHeight: CGFloat { metrics.statusHeight > 1 ? metrics.statusHeight : 16 }

    var body: some View {
        HStack(spacing: 2) {
            LCDMetaGlyph(label: "⇧", on: store.keyboardShift)
            LCDMetaGlyph(label: "SYM", on: store.keyboardSymbol)
            LCDMetaGlyph(label: "aA", on: store.keyboardCaps)
            Spacer(minLength: 2)
            LCDStatusMark("B39", on: LCDStatus.bip39IconOn(passphrase: store.activePassphrase))
            LCDStatusMark("TMP", on: LCDStatus.tmpIconOn(hasEphemeralSeed: store.ephemeralPhrase != nil || store.ephemeralXPRV != nil))
            if let glyphs = store.lcdXFPGlyphs {
                Text(glyphs)
                    .font(.system(size: max(6, barHeight * 0.48), weight: .semibold, design: .monospaced))
                    .foregroundStyle(lcdText)
                    .tracking(0.6)
                    .textCase(.lowercase)
            }
            LCDPowerGlyph(icon: store.lcdPowerIcon)
        }
        .padding(.horizontal, metrics.leftMargin > 0 ? metrics.leftMargin : 6)
        .frame(height: barHeight)
        .background(Color(white: 0.035))
        .onAppear { store.refreshLCDPower() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            store.refreshLCDPower()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            store.refreshLCDPower()
        }
    }
}

struct LCDMetaGlyph: View {
    let label: String
    let on: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(on ? Color.black : lcdText.opacity(0.22))
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background(on ? lcdText : Color.clear)
    }
}

struct LCDStatusMark: View {
    let text: String
    var on: Bool
    init(_ text: String, on: Bool) {
        self.text = text
        self.on = on
    }

    var body: some View {
        Text(text)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(on ? lcdText : lcdText.opacity(0.22))
    }
}

struct LCDPowerGlyph: View {
    let icon: LCDPowerIcon

    var body: some View {
        switch icon {
        case .plugged:
            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 0.5)
                    .stroke(lcdText.opacity(0.9), lineWidth: 0.8)
                    .frame(width: 11, height: 6)
                Rectangle()
                    .fill(lcdText.opacity(0.9))
                    .frame(width: 2, height: 3)
            }
            .accessibilityLabel("Plugged")
        case .battery(let level):
            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 0.5)
                        .stroke(lcdText.opacity(0.9), lineWidth: 0.8)
                        .frame(width: 12, height: 7)
                    Rectangle()
                        .fill(lcdText.opacity(level == 0 ? 0.35 : 0.9))
                        .frame(width: max(2, CGFloat(level + 1) * 2.4), height: 4)
                        .padding(.leading, 1.5)
                }
                Rectangle()
                    .fill(lcdText.opacity(0.9))
                    .frame(width: 1.5, height: 3)
            }
            .accessibilityLabel("Battery \(level)")
        }
    }
}

struct LCDBusyOverlay: View {
    let title: String
    var progress: Double?
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        // Title covers the 10-row text area. `DeviceScreenRoot` owns the GPU
        // `busy_bar` / `progress_bar` strip under that area (D018).
        ZStack(alignment: .top) {
            Color.black
            Text(title.isEmpty ? "Wait..." : title)
                .font(.system(size: metrics.fontSize * 1.15, weight: .medium, design: .monospaced))
                .foregroundStyle(lcdText)
                .frame(maxWidth: .infinity)
                .padding(.top, metrics.cellHeight * 3)
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.isEmpty ? "Wait..." : title)
        .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "busy")
    }
}

/// Firmware `draw_bbqr_progress`: pattern, Keep scanning / Got all parts, TYPE_LABELS count.
struct LCDBBQrProgressOverlay: View {
    let progress: BBQrScanProgress
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            if !progress.partPattern.isEmpty {
                Text(progress.partPattern)
                    .font(.system(size: metrics.monoFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(lcdText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.cellHeight)
            }
            Text(progress.instructionLine)
                .font(.system(size: metrics.monoFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(lcdText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.cellHeight)
            Text(progress.countLine)
                .font(.system(size: metrics.monoFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(lcdMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.cellHeight)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.statusMessage)
    }
}

struct LCDProgressStrip: View {
    var isBusy: Bool
    var progress: Double?
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        Group {
            if isBusy, let progress {
                GeometryReader { geo in
                    let width = LCDBusyBar.fillWidth(progress: progress, total: max(1, Int(geo.size.width)))
                    ZStack(alignment: .leading) {
                        Color.black
                        lcdText.frame(width: CGFloat(width))
                    }
                }
            } else if isBusy {
                TimelineView(.periodic(from: .now, by: 1.0 / 16.0)) { timeline in
                    let phase = Int(timeline.date.timeIntervalSinceReferenceDate * 16) % LCDBusyBar.phaseCount
                    Canvas { context, size in
                        let stripe = max(1, size.width / CGFloat(LCDBusyBar.pixelWidth))
                        var x: CGFloat = 0
                        var pixel = 0
                        while x < size.width {
                            let fg = LCDBusyBar.isForeground(x: pixel, phase: phase)
                            context.fill(
                                Path(CGRect(x: x, y: 0, width: stripe, height: size.height)),
                                with: .color(fg ? lcdText : Color.black)
                            )
                            x += stripe
                            pixel += 1
                        }
                    }
                }
            } else {
                Color.black
            }
        }
        .frame(height: metrics.progressHeight)
        .clipped()
    }
}

struct LCDScrollTrack: View {
    var offset: Int
    var count: Int
    var perPage: Int
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        let bar = LCDScrollBar.geometry(
            offset: offset, count: count, perPage: perPage,
            activeHeight: max(1, Int(metrics.contentHeight))
        )
        ZStack(alignment: .top) {
            lcdScrollTrack
            lcdText
                .frame(height: CGFloat(bar.thumbHeight))
                .offset(y: CGFloat(bar.thumbOffset))
        }
        .frame(width: max(3, metrics.size.width * CGFloat(LCDDisplay.scrollBarW) / 320), height: metrics.contentHeight)
        .accessibilityHidden(true)
    }
}

struct LCDStoryPage: View {
    let lines: [LCDStoryLine]
    var top: Int
    var onTap: (() -> Void)? = nil
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        let visible = LCDStory.visible(lines: lines, top: top)
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                    LCDStoryRow(line: line)
                        .frame(height: metrics.cellHeight)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, metrics.leftMargin)
            LCDScrollTrack(offset: top, count: max(lines.count, 1), perPage: LCDDisplay.storyHeight)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

private struct LCDStoryRow: View {
    let line: LCDStoryLine
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            switch line {
            case .title(let title, let hints):
                Text(" \(title) ")
                    .font(lcdFont)
                    .foregroundStyle(Color.black)
                    .background(lcdText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !hints.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(hints, id: \.self) { hint in
                            LCDHintGlyph(icon: hint)
                        }
                    }
                    .foregroundStyle(lcdMuted)
                    .padding(.trailing, 4)
                }
            case .text(let value):
                Text(value)
                    .font(lcdFont)
                    .foregroundStyle(lcdText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .address(let value):
                Text(LCDDisplay.drawnAddress(value))
                    .font(lcdFont)
                    .foregroundStyle(Color.black)
                    .background(lcdText)
                    .lineLimit(1)
            case .eot:
                Text(LCDStory.eotBar)
                    .font(lcdFont)
                    .foregroundStyle(lcdMuted)
                    .lineLimit(1)
            case .blank:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(lcdFont)
    }

    private var lcdFont: Font {
        .system(size: metrics.fontSize, weight: .medium, design: .monospaced)
    }
}

struct LCDHintGlyph: View {
    let icon: LCDHintIcon
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        Group {
            switch icon {
            case .qr:
                Image(systemName: "qrcode")
            case .nfc:
                Image(systemName: "wave.3.right")
            }
        }
        .font(.system(size: metrics.fontSize * 0.95, weight: .semibold))
        .foregroundStyle(lcdMuted)
        .frame(width: metrics.cellWidth * 2, height: metrics.cellHeight)
        .accessibilityLabel(icon == .qr ? "QR" : "NFC")
    }
}

struct LCDMenuList: View {
    @Bindable var store: SimulatorStore

    var body: some View {
        GeometryReader { geo in
            let metrics = LCDScreenMetrics.characterGrid(size: geo.size)
            menuGrid(metrics: metrics)
                .environment(\.lcdMetrics, metrics)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func menuGrid(metrics: LCDScreenMetrics) -> some View {
        let wrap = store.preferences.menuWrapping || store.menuItems.count > LCDDisplay.menuVisibleRows
        let pager = LCDMenuPager(
            count: store.menuItems.count, wrap: wrap,
            cursor: store.selectedMenuIndex, ypos: store.menuYPos
        )
        return ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                ForEach(0..<LCDDisplay.menuVisibleRows, id: \.self) { row in
                    let index = pager.ypos + row
                    Group {
                        if store.menuItems.indices.contains(index) {
                            let item = store.menuItems[index]
                            if item.isPaperWalletFormatChooser {
                                LCDPaperWalletFormatChooserRow(
                                    store: store,
                                    selected: store.selectedMenuIndex == index
                                ) {
                                    store.jumpMenu(to: index)
                                }
                            } else {
                                LCDMenuRow(
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    checked: item.checked,
                                    selected: store.selectedMenuIndex == index,
                                    simulatorOnly: item.simulatorOnly
                                ) {
                                    store.jumpMenu(to: index)
                                    store.activateCurrentSelection()
                                }
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: metrics.cellHeight)
                }
            }
            if pager.showsScrollBar {
                LCDScrollTrack(offset: pager.ypos, count: pager.count, perPage: LCDDisplay.menuPerPage)
            }
        }
    }
}

/// Firmware `paper.py` `addr_format_chooser` — in-place Classic/Segwit pick on the row.
private struct LCDPaperWalletFormatChooserRow: View {
    @Bindable var store: SimulatorStore
    var selected: Bool
    var onFocus: () -> Void
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                LCDMenuPicker(
                    options: [false, true],
                    title: { $0 ? "Segwit P2WPKH" : "Classic P2PKH" },
                    selection: Binding(
                        get: { store.paperWalletIsSegwit },
                        set: { store.setPaperWalletSegwit($0) }
                    )
                )
                .padding(.leading, metrics.cellWidth * 0.9)
                LCDMenuCursor(selected: selected)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }
}

struct LCDMenuRow: View {
    let title: String
    var subtitle: String? = nil
    var checked = false
    let selected: Bool
    var simulatorOnly = false
    let action: () -> Void
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        let invertCells = min(LCDDisplay.charsW, LCDDisplay.menuInvertCellCount(label: title))
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    if selected {
                        lcdText.frame(width: metrics.cellWidth * CGFloat(invertCells), height: metrics.cellHeight)
                    }
                    Text(" \(title) ")
                        .font(lcdFont)
                        .foregroundStyle(selected ? Color.black : lcdText)
                        .lineLimit(1)
                    LCDMenuCursor(selected: selected)
                }
                .frame(width: metrics.cellWidth * CGFloat(invertCells), height: metrics.cellHeight, alignment: .leading)
                .clipped()
                if simulatorOnly {
                    Text("SIM")
                        .font(.system(size: metrics.monoFontSize * 0.55, weight: .bold, design: .monospaced))
                        .foregroundStyle(lcdText)
                }
                if let subtitle {
                    Text(" \(subtitle)")
                        .font(.system(size: metrics.monoFontSize * 0.78, design: .monospaced))
                        .foregroundStyle(lcdMuted)
                        .lineLimit(1)
                }
                if checked {
                    Text("✔")
                        .font(lcdFont)
                        .foregroundStyle(lcdText)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .frame(height: metrics.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lcdFont: Font {
        .system(size: metrics.monoFontSize, weight: .medium, design: .monospaced)
    }
}

private struct LCDMenuCursor: View {
    let selected: Bool
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.52)) { timeline in
            let on = selected && Int(timeline.date.timeIntervalSinceReferenceDate / 0.52) % 2 == 0
            Rectangle()
                .fill(on ? Color.black : Color.clear)
                .frame(width: max(1, metrics.cellWidth * 0.22), height: metrics.cellHeight * 0.7)
                .padding(.leading, metrics.cellWidth * 0.2)
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight, alignment: .leading)
        .allowsHitTesting(false)
    }
}

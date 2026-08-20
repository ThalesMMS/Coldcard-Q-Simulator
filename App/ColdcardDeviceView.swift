import SwiftUI
import UIKit
import ColdcardCore

struct ColdcardDeviceView: View {
    @Bindable var store: SimulatorStore
    @FocusState private var acceptsHardwareKeyboardInput: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.035), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("COLDCARD Q SIMULATOR").font(.caption.bold())
                        Text("unofficial · \(store.network.displayName) · no network").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.interfaceMode = .phone
                    } label: {
                        Image(systemName: "iphone")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Switch to iPhone interface")
                    Button {
                        store.isScreenExpanded.toggle()
                    } label: {
                        Image(systemName: store.isScreenExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(store.isScreenExpanded ? "Show full device" : "Expand screen")
                }
                .padding(.horizontal)

                if store.isScreenExpanded {
                    DeviceScreenRoot(store: store)
                        .aspectRatio(350 / 260, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .padding()
                } else {
                    GeometryReader { proxy in
                        let availableWidth = max(200, proxy.size.width - 12)
                        let availableHeight = max(300, proxy.size.height - 4)
                        let width = min(availableWidth, availableHeight * 518 / 853)
                        let height = width * 853 / 518
                        QShell(store: store, size: CGSize(width: width, height: height))
                            .frame(width: width, height: height)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
            }
            .padding(.top, 4)
        }
        .preferredColorScheme(.dark)
        .focusable()
        .focused($acceptsHardwareKeyboardInput)
        .focusEffectDisabled()
        .onAppear { acceptsHardwareKeyboardInput = true }
        .onChange(of: store.screen) { _, _ in acceptsHardwareKeyboardInput = true }
        .onKeyPress(phases: [.down, .repeat], action: handleKeyPress)
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard !press.modifiers.contains(.command), !press.modifiers.contains(.control),
              let key = HardwareKeyboardMapper.map(keyboardInput(for: press)) else {
            return .ignored
        }
        let option = press.modifiers.contains(.option)
        let shift = press.modifiers.contains(.shift)
        let overlay = HardwareKeyboardMapper.applyHeldModifiers(
            key, symbol: option, shift: shift, caps: store.keyboardCaps
        )
        if overlay != key {
            store.handleHardwareKey(overlay)
            return .handled
        }
        if shift { store.handleHardwareKey(.shift) }
        if option { store.handleHardwareKey(.symbol) }
        store.handleHardwareKey(key)
        return .handled
    }

    private func keyboardInput(for press: KeyPress) -> HardwareKeyboardInput {
        if press.key == .upArrow { return .upArrow }
        if press.key == .downArrow { return .downArrow }
        if press.key == .leftArrow { return .leftArrow }
        if press.key == .rightArrow { return .rightArrow }
        if press.key == .home { return .home }
        if press.key == .end { return .end }
        if press.key == .pageUp { return .pageUp }
        if press.key == .pageDown { return .pageDown }
        if press.key == .return { return .returnKey }
        if press.key == .escape { return .escape }
        if press.key == .delete || press.key == .deleteForward { return .delete }
        if press.key == .tab { return .tab }
        if press.key == .space { return .characters(" ") }
        return .characters(press.characters)
    }
}

private struct QShell: View {
    @Bindable var store: SimulatorStore
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("q1-background")
                .resizable()
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)

            DeviceScreenRoot(store: store)
                .frame(width: size.width * 0.676, height: size.height * 0.305)
                .position(x: size.width * (0.158 + 0.676 / 2), y: size.height * (0.101 + 0.305 / 2))
                .clipShape(RoundedRectangle(cornerRadius: size.width * 0.017))

            if store.torchOn {
                Color.yellow.opacity(0.28)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            SelftestLEDOverlay(led: store.selftestLED, size: size)

            ForEach(HardwareHitTarget.all) { target in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.handleHardwareKey(target.key)
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: size.width * target.rect.width, height: size.height * target.rect.height)
                .position(x: size.width * target.rect.midX, y: size.height * target.rect.midY)
                .accessibilityLabel(target.accessibilityLabel)
            }
        }
    }
}

private struct HardwareHitTarget: Identifiable {
    let id: String
    let key: HardwareKey
    let rect: CGRect
    let accessibilityLabel: String

    static let all: [HardwareHitTarget] = {
        func target(_ id: String, _ key: HardwareKey, _ x: CGFloat, _ y: CGFloat,
                    _ width: CGFloat, _ height: CGFloat, label: String? = nil) -> HardwareHitTarget {
            HardwareHitTarget(id: id, key: key, rect: CGRect(x: x, y: y, width: width, height: height), accessibilityLabel: label ?? id)
        }
        var values: [HardwareHitTarget] = [
            target("power", .power, 0.052, 0.463, 0.091, 0.052, label: "Power"),
            target("qr", .qr, 0.153, 0.463, 0.108, 0.052, label: "QR"),
            target("nfc", .nfc, 0.052, 0.520, 0.091, 0.052, label: "NFC"),
            target("tab", .tab, 0.153, 0.520, 0.108, 0.052, label: "Tab"),
            target("up", .up, 0.427, 0.462, 0.145, 0.052, label: "Up"),
            target("down", .down, 0.427, 0.520, 0.145, 0.052, label: "Down"),
            target("left", .left, 0.285, 0.486, 0.125, 0.075, label: "Left"),
            target("right", .right, 0.590, 0.486, 0.125, 0.075, label: "Right"),
            target("cancel", .cancel, 0.743, 0.462, 0.205, 0.052, label: "Cancel"),
            target("enter", .enter, 0.743, 0.520, 0.205, 0.052, label: "Enter")
        ]

        let numberKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let qRow = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
        let aRow = ["a", "s", "d", "f", "g", "h", "j", "k", "l", "'"]
        let zRow = ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
        let centers = (0..<10).map { 0.088 + CGFloat($0) * 0.092 }
        for (rowID, keys, y) in [("num", numberKeys, CGFloat(0.618)), ("q", qRow, CGFloat(0.687)), ("a", aRow, CGFloat(0.756)), ("z", zRow, CGFloat(0.825))] {
            for (index, character) in keys.enumerated() {
                values.append(target("\(rowID)-\(character)", .character(character), centers[index] - 0.038, y - 0.029, 0.076, 0.058, label: character.uppercased()))
            }
        }
        values.append(target("lamp", .lamp, 0.042, 0.868, 0.108, 0.058, label: "Lamp"))
        values.append(target("space", .space, 0.351, 0.868, 0.301, 0.058, label: "Space"))
        values.append(target("backspace", .backspace, 0.850, 0.868, 0.101, 0.058, label: "Backspace"))
        values.append(target("shift", .shift, 0.160, 0.868, 0.175, 0.058, label: "Shift"))
        values.append(target("symbol", .symbol, 0.672, 0.868, 0.165, 0.058, label: "Symbol"))
        return values
    }()
}

/// On-screen stand-in for Q genuine / NFC / USB / SD activity lights (`selftest.py`).
private struct SelftestLEDOverlay: View {
    let led: QSelftest.LED
    let size: CGSize

    var body: some View {
        if let spec = placement {
            Image(spec.asset)
                .resizable()
                .scaledToFit()
                .frame(width: size.width * spec.width)
                .position(x: size.width * spec.x, y: size.height * spec.y)
                .allowsHitTesting(false)
                .accessibilityLabel(spec.label)
        }
    }

    private var placement: (asset: String, x: CGFloat, y: CGFloat, width: CGFloat, label: String)? {
        switch led {
        case .off:
            nil
        case .genuineGreen:
            ("led-green", 0.78, 0.055, 0.07, "Genuine green")
        case .genuineRed:
            ("led-red", 0.78, 0.055, 0.07, "Genuine red")
        case .nfc:
            ("led-green", 0.88, 0.22, 0.06, "NFC light")
        case .usb:
            ("led-green", 0.50, 0.028, 0.06, "USB light")
        case .sdA(let on):
            on ? ("led-green", 0.055, 0.20, 0.05, "SD A on") : nil
        case .sdB(let on):
            on ? ("led-green", 0.055, 0.30, 0.05, "SD B on") : nil
        }
    }
}

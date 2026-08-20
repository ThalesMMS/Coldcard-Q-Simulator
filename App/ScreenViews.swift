import SwiftUI
import ColdcardCore

private let coldcardGold = Color(red: 0.72, green: 0.54, blue: 0.20)
private let screenText = Color(white: 0.88)
private let mutedText = Color(white: 0.58)

struct DeviceScreenRoot: View {
    @Bindable var store: SimulatorStore

    var body: some View {
        GeometryReader { geo in
            let metrics = LCDScreenMetrics.make(size: geo.size)
            VStack(spacing: 0) {
                statusBar
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: metrics.hairline)
                screenBody
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.contentHeight)
                    .clipped()
                    .overlay {
                        if store.isWorking && !store.gpuBusyBar {
                            LCDBusyOverlay(title: store.busyTitle, progress: store.busyProgress)
                        } else if let progress = store.bbqrScanProgress, !progress.skipsProgressUI {
                            LCDBBQrProgressOverlay(progress: progress)
                        }
                    }
                LCDProgressStrip(
                    isBusy: store.isWorking || store.showsBBQrProgressBar,
                    progress: store.bbqrScanProgress.map(\.fraction) ?? store.busyProgress
                )
            }
            .environment(\.lcdMetrics, metrics)
            .foregroundStyle(lcdText)
            .background(selftestLCDBackground)
        }
    }

    @ViewBuilder
    private var screenBody: some View {
        switch store.screen {
        case .menu: FirmwareMenuScreen(store: store)
        case .unlock: UnlockScreen(store: store)
        case .pinSetup: PINSetupScreen(store: store)
        case .seedWords: SeedWordsScreen(store: store)
        case .wordQuiz: WordQuizScreen(store: store)
        case .diceRoll: DiceRollScreen(store: store)
        case .importSeed: ImportSeedScreen(store: store)
        case .passphrase: PassphraseScreen(store: store)
        case .listedFileRename: ListedFileRenameScreen(store: store)
        case .passphraseConfirm: PassphraseConfirmScreen(store: store)
        case .addresses: AddressListScreen(store: store)
        case .addressDetail: AddressDetailScreen(store: store)
        case .accountNumber: AccountNumberScreen(store: store)
        case .psbt: PSBTScreen(store: store)
        case .nfcReceive: NFCReceiveScreen(store: store)
        case .psbtSigned: SignedPSBTScreen(store: store)
        case .walletExport: WalletExportScreen(store: store)
        case .messageSigning: MessageSigningScreen(store: store)
        case .noteEditor: NoteEditorScreen(store: store)
        case .backupPassword: BackupPasswordScreen(store: store)
        case .verifyBackup: VerifyBackupScreen(store: store)
        case .hexEntry: HexEntryScreen(store: store)
        case .calculator: CalculatorScreen(store: store)
        case .story: StoryScreen(store: store)
        case .viewIdentity: ViewIdentityScreen(store: store)
        case .brick: BrickScreen(store: store)
        case .wordEntry: WordEntryScreen(store: store)
        case .entropyCollect: EntropyCollectScreen(store: store)
        case .psbtExplorer: PSBTExplorerScreen(store: store)
        case .loginCountdown: LoginCountdownScreen(store: store)
        case .nicknameSplash: NicknameSplashScreen(store: store)
        case .typePasswordIndex: TypePasswordIndexScreen(store: store)
        case .typePasswordConfirm: TypePasswordConfirmScreen(store: store)
        case .serialREPL: SerialREPLScreen(store: store)
        case .factoryBagged: FactoryBaggedScreen(store: store)
        case .factoryDFU: FactoryDFUScreen(store: store)
        case .poweredOff: PoweredOffScreen()
        }
    }

    @ViewBuilder
    private var selftestLCDBackground: some View {
        switch store.selftestFill {
        case .red: Color.red
        case .green: Color.green
        case .blue: Color.blue
        case .gpu:
            HStack(spacing: 0) {
                Color.red
                Color.green
                Color.blue
            }
        case nil:
            Color.black
        }
    }

    /// Firmware `lcd_display.draw_status`: icon strip only.
    private var statusBar: some View {
        LCDStatusBar(store: store)
    }
}

private struct ScreenScaffold<Content: View>: View {
    @Bindable var store: SimulatorStore
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            if let error = store.errorMessage, store.screen != .listedFileRename {
                Text(error)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 3)
                    .background(Color.black.opacity(0.72))
            } else if let status = store.statusMessage {
                Text(status)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 3)
                    .background(Color.black.opacity(0.72))
            }
        }
    }
}

/// Firmware `draw_story` title: invert `' '+title+' '` in original case.
private struct LCDInvertTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(" \(title) ")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.black)
            .background(screenText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LCDStoryView: View {
    @Bindable var store: SimulatorStore
    var title: String = ""
    var bodyText: String
    var hintQR = false
    var hintNFC = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        let lines = composedLines(title: title, body: bodyText)
        LCDStoryPage(lines: lines, top: store.storyTop, onTap: onTap)
            .onAppear { store.noteStoryLineCount(lines.count) }
            .onChange(of: title) { _, newTitle in
                store.noteStoryLineCount(composedLines(title: newTitle, body: bodyText).count)
            }
            .onChange(of: bodyText) { _, newBody in
                store.noteStoryLineCount(composedLines(title: title, body: newBody).count)
            }
    }

    private func composedLines(title: String, body: String) -> [LCDStoryLine] {
        LCDStory.compose(
            title: title.isEmpty ? nil : title,
            body: body,
            hintQR: hintQR,
            hintNFC: hintNFC
        )
    }
}

/// Invisible confirm control for screens whose ENTER path is missing in the store.
private struct LCDHitStrip: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct LCDMenuPicker<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(title(option)) { selection = option }
            }
        } label: {
            HStack(spacing: 3) {
                Text(title(selection))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 6, weight: .bold))
            }
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(coldcardGold)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

private struct LCDCheckbox: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 4) {
                Text(isOn ? "[✓]" : "[ ]").foregroundStyle(coldcardGold)
                Text(label)
            }
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

private struct LCDSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(selection == option ? coldcardGold : Color.white.opacity(0.10))
                        .foregroundStyle(selection == option ? Color.black : screenText)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Firmware `actions.show_nickname`: centered until any key.
private struct NicknameSplashScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            Text(store.nickname)
                .font(.system(size: 14, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { store.dismissNicknameSplash() }
        }
    }
}

private struct FirmwareMenuScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDMenuList(store: store)
        }
    }
}

private struct UnlockScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            PINPadView(
                subtitle: nil,
                prefix: store.unlockPhase == .prefix ? "" : store.pinPrefix,
                current: store.pinInput,
                isConfirmation: store.unlockPhase == .confirmRiskyAttempt,
                footer: store.unlockFooter,
                scrambleMap: store.scrambleDigitMap,
                antiPhishing: store.unlockPhase == .prefix ? "" : store.antiPhishingWords(for: store.pinPrefix)
            )
            .contentShape(Rectangle())
            .onTapGesture { store.unlock() }
        }
    }
}

private struct PINSetupScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            switch store.pinSetupPhase {
            case .warning, .proveRead:
                // Choose PIN / WARNING are `ux_show_story` screens, not this PIN grid.
                Color.clear
            case .prefix, .confirmPrefix, .suffix, .confirmSuffix:
                PINPadView(
                    subtitle: pinSubtitle,
                    prefix: prefixValue,
                    current: currentValue,
                    isConfirmation: store.pinSetupPhase == .confirmPrefix || store.pinSetupPhase == .confirmSuffix,
                    footer: (store.pinSetupPhase == .confirmPrefix || store.pinSetupPhase == .confirmSuffix)
                        ? FirmwareCopy.confirmPINValue : "",
                    scrambleMap: [:],
                    antiPhishing: showsPhish ? store.antiPhishingWords(for: store.pinPrefix) : ""
                )
                .contentShape(Rectangle())
                .onTapGesture { store.advancePINSetup() }
            }
        }
    }

    private var pinSubtitle: String? {
        if store.pinSetupPurpose == .trickNew || store.pinSetupPurpose == .trickChange {
            return "New Trick PIN"
        }
        if store.pinSetupPurpose == .ssspBypass { return "Spending Policy Unlock" }
        if store.pinSetupCollectingOld { return "Old Main PIN" }
        if store.pinSetupIsChange { return "New Main PIN" }
        return nil
    }

    private var prefixValue: String {
        switch store.pinSetupPhase {
        case .prefix, .confirmPrefix: return ""
        default: return store.pinPrefix
        }
    }

    private var currentValue: String {
        switch store.pinSetupPhase {
        case .prefix, .confirmPrefix: return store.pinPrefix
        default: return store.pinInput
        }
    }

    private var showsPhish: Bool {
        store.pinSetupPhase == .suffix || store.pinSetupPhase == .confirmSuffix
    }
}

/// Firmware `ux_show_pin` (`shared/ux_q1.py`).
private struct PINPadView: View {
    var subtitle: String?
    var prefix: String
    var current: String
    var isConfirmation: Bool
    var footer: String
    var scrambleMap: [Character: Character]
    var antiPhishing: String

    var body: some View {
        VStack(spacing: 0) {
            if !scrambleMap.isEmpty {
                LCDPINScrambleMap(map: scrambleMap)
            }
            VStack(spacing: 6) {
                Spacer(minLength: 4)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
                Text(prefix.isEmpty ? FirmwareCopy.pinPrefixPrompt : FirmwareCopy.pinSuffixPrompt)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(subtitle == nil ? screenText : mutedText)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    LCDPINBox(
                        digitCount: prefix.isEmpty ? current.count : prefix.count,
                        active: prefix.isEmpty
                    )
                    Text("⋯").foregroundStyle(mutedText)
                    LCDPINBox(
                        digitCount: prefix.isEmpty ? 0 : current.count,
                        active: !prefix.isEmpty
                    )
                }
                if !antiPhishing.isEmpty {
                    let parts = antiPhishing.split(whereSeparator: \.isWhitespace).map(String.init)
                    HStack {
                        Spacer()
                        if parts.indices.contains(0) { Text(parts[0]) }
                        Spacer()
                        if parts.indices.contains(1) { Text(parts[1]) }
                        Spacer()
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.top, 8)
                }
                Spacer()
                if !footer.isEmpty {
                    Text(footer)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(mutedText)
                        .frame(maxWidth: .infinity)
                } else if isConfirmation {
                    Text(FirmwareCopy.confirmPINValue)
                        .font(.system(size: 8, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

/// `ux_show_pin` randomize banner: inverted shuffled digits over `↳ 1 … 0` at x=1, 34 columns.
private struct LCDPINScrambleMap: View {
    var map: [Character: Character]
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        let rows = PINEntryChrome.scrambleMap(from: map)
        VStack(spacing: 0) {
            LCDPINCharRow(text: rows.topRow, invertColumns: rows.invertColumns)
            LCDPINCharRow(text: rows.bottomRow, invertColumns: nil)
        }
        .padding(.leading, metrics.leftMargin)
        .frame(height: metrics.cellHeight * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scramble map")
        .accessibilityValue("\(rows.invertedDigits) over \(rows.keyLegend)")
    }
}

private struct LCDPINCharRow: View {
    var text: String
    var invertColumns: Range<Int>?
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        let cells = Array(text)
        HStack(spacing: 0) {
            ForEach(0..<LCDDisplay.charsW, id: \.self) { column in
                let glyph = column < cells.count ? String(cells[column]) : " "
                let invert = invertColumns?.contains(column) == true
                Text(glyph)
                    .font(.system(size: metrics.monoFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(invert ? Color.black : lcdText)
                    .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                    .background(invert ? lcdText : Color.clear)
            }
        }
        .frame(height: metrics.cellHeight, alignment: .leading)
    }
}

private struct LCDPINBox: View {
    var digitCount: Int
    var active: Bool
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        let cursor = active ? PINEntryChrome.cursor(digitCount: digitCount) : nil
        HStack(spacing: 0) {
            Color.clear.frame(width: metrics.cellWidth, height: metrics.cellHeight)
            ForEach(0..<PINEntryChrome.maxPartLen, id: \.self) { slot in
                ZStack {
                    if slot < digitCount {
                        Text("•")
                            .font(.system(size: max(11, metrics.monoFontSize), weight: .medium, design: .monospaced))
                            .foregroundStyle(active ? screenText : mutedText)
                    }
                    if let cursor, cursor.index == slot {
                        PINLCDCursorMark(style: cursor.style)
                    }
                }
                .frame(width: metrics.cellWidth, height: metrics.cellHeight)
            }
            Color.clear.frame(width: metrics.cellWidth, height: metrics.cellHeight)
        }
        .frame(width: metrics.cellWidth * 8, height: max(18, metrics.cellHeight))
        .overlay(
            Rectangle().stroke(active ? screenText : mutedText.opacity(0.45), lineWidth: 1)
        )
        .accessibilityLabel(active ? "PIN digits" : "PIN digits inactive")
        .accessibilityValue(String(repeating: "•", count: digitCount))
        .accessibilityHint(cursorHint(cursor))
    }

    private func cursorHint(_ cursor: PINCursor?) -> String {
        guard let cursor else { return "" }
        switch cursor.style {
        case .outline: return "Outline cursor on sixth digit"
        case .solid: return "Solid cursor"
        }
    }
}

/// GPU `CURSOR_OUTLINE` (cell border) vs `CURSOR_SOLID` (fill / hollow), blinking.
private struct PINLCDCursorMark: View {
    var style: PINCursor.Style
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.52)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.52) % 2 == 0
            let line = max(1, metrics.hairline)
            switch style {
            case .outline:
                Rectangle()
                    .strokeBorder(phase ? lcdText : Color.black, lineWidth: line)
            case .solid:
                if phase {
                    lcdText
                } else {
                    Rectangle()
                        .strokeBorder(lcdText, lineWidth: line)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SeedWordsScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    LCDInvertTitle(seedTitle)
                    SeedWordColumns(words: store.mnemonicWords)
                    Text(FirmwareCopy.seedWordsNotes(ephemeral: store.pendingEphemeral))
                        .font(.system(size: 8, design: .monospaced))
                    if store.pendingEphemeral, store.pendingMnemonic != nil {
                        Text(SeedCreation.skipQuizHint)
                            .font(.system(size: 8, design: .monospaced))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if store.xorQuizzingSplit || store.pendingMnemonic != nil { store.continueAfterSeedWords() }
                else { store.back() }
            }
        }
    }

    private var seedTitle: String {
        if store.mnemonicWords.isEmpty { return "Seed Words" }
        if store.pendingMnemonic == nil {
            return "Seed words (\(store.mnemonicWords.count)):"
        }
        return "Record these \(store.mnemonicWords.count) secret words!"
    }
}

private struct WordQuizScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            ZStack {
                VStack(alignment: .leading, spacing: 6) {
                    LCDInvertTitle(store.screenTitle)
                    if let quiz = store.wordQuiz {
                        ForEach(Array(quiz.choices.enumerated()), id: \.offset) { index, word in
                            Button {
                                store.selectedMenuIndex = index
                                store.answerWordQuiz(word)
                            } label: {
                                Text(" \(index + 1): \(word)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(screenText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(SeedCreation.quizPrompt)
                        .font(.system(size: 8.5, design: .monospaced))
                        .padding(.horizontal, 6)
                    Text(SeedCreation.quizGiveUp)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(mutedText)
                        .padding(.horizontal, 6)
                    Spacer()
                }
                .padding(.top, 4)
                if store.quizWrongPause {
                    ZStack {
                        Color.black
                        Text("Wrong!")
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                    }
                }
            }
        }
    }
}

/// Firmware `ux_dice_rolling` (dice-only). Mix-in dice uses `.entropyCollect`.
private struct DiceRollScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Press 1-6 for each dice roll")
                Text("to mix in.")
                Text("\(store.diceRolls.count) rolls so far")
                    .foregroundStyle(Color.black)
                    .background(screenText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                Spacer()
                if !store.diceRunningHash.isEmpty {
                    let lines = store.diceRunningHashLines
                    Text(lines.top)
                        .foregroundStyle(mutedText)
                    Text("  " + lines.bottom)
                        .foregroundStyle(mutedText)
                }
            }
            .font(.system(size: 8.5, design: .monospaced))
            .padding(8)
        }
    }
}

private struct ImportSeedScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 4) {
                LCDInvertTitle("Enter Seed Words")
                SeedWordColumns(words: importWords)
                    .padding(.horizontal, 6)
                Spacer()
                LCDHitStrip(label: "Validate seed") { store.validateImportedSeed() }
            }
            .padding(.top, 4)
        }
    }

    private var importWords: [String] {
        var words = store.importSeedText.split(whereSeparator: \.isWhitespace).map(String.init)
        while words.count < store.seedWordCount { words.append("") }
        if words.count > store.seedWordCount { words = Array(words.prefix(store.seedWordCount)) }
        return words
    }
}

private struct PassphraseScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 6) {
                LCDInvertTitle(passphrasePrompt)
                if store.textEntryIsNickname {
                    TextField("", text: $store.passphraseInput).coldcardField()
                } else if store.textEntryIsNoteGroup {
                    TextField("", text: $store.passphraseInput)
                        .coldcardField()
                        .onChange(of: store.passphraseInput) { _, value in
                            if value.count > SecureNotesSupport.oneLineLimit {
                                store.passphraseInput = String(value.prefix(SecureNotesSupport.oneLineLimit))
                            }
                        }
                } else {
                    TextField("", text: $store.passphraseInput)
                        .coldcardField()
                        .onChange(of: store.passphraseInput) { _, value in
                            let limit: Int
                            if store.textEntryIsKeyboardTest || store.textEntryIsBKPWOverride || store.textEntryIsNotesImportPassword || store.textEntryIsCustomBackupPassword {
                                limit = DeveloperDebug.bkpwMaxLength
                            } else if store.textEntryIsPushtxURL {
                                limit = 256
                            } else if store.textEntryIsWIF {
                                limit = 52
                            } else if store.renamingMultisigIndex != nil {
                                limit = 20
                            } else if store.renamingVaultSeedID != nil {
                                limit = SeedVaultMenuCopy.renameMaxLength
                            } else if store.teleportTextKind == .numericPassword {
                                limit = KeyTeleport.numericCodeLength
                            } else if store.teleportTextKind == .paranoidPassword {
                                limit = KeyTeleport.paranoidPasswordLength
                            } else {
                                let next = BIP39Passphrase.sanitized(value)
                                if next != value { store.passphraseInput = next }
                                return
                            }
                            if store.teleportTextKind == .numericPassword {
                                let digits = String(value.filter(\.isNumber).prefix(limit))
                                if digits != value { store.passphraseInput = digits }
                            } else if value.count > limit {
                                store.passphraseInput = String(value.prefix(limit))
                            }
                        }
                    if !store.passphraseCompletionHint.isEmpty {
                        Text(store.passphraseCompletionHint)
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(mutedText)
                    }
                }
                Spacer()
            }
            .padding(8)
        }
    }

    private var passphrasePrompt: String {
        if store.renamingVaultSeedID != nil { return "Rename" }
        if store.renamingMultisigIndex != nil { return "Rename" }
        if store.textEntryIsNickname { return LoginUX.nicknamePrompt }
        if store.textEntryIsNoteGroup { return "Group" }
        if store.textEntryIsKeyboardTest { return DeveloperDebug.keyboardTestPrompt }
        if store.textEntryIsBKPWOverride { return DeveloperDebug.bkpwPasswordPrompt }
        if store.textEntryIsNotesImportPassword { return "Your Backup Password" }
        if store.textEntryIsCustomBackupPassword { return BackupFile.backupPasswordPrompt }
        if store.textEntryIsPushtxURL { return FirmwareCopy.enterPushtxURL }
        if store.textEntryIsNFCSeed { return "Import via NFC" }
        if store.textEntryIsNFCTools { return store.nfcStandInTitle }
        if store.textEntryIsWIF { return "Enter WIF" }
        if let prompt = store.teleportPassphrasePrompt { return prompt }
        return "Your BIP-39 Passphrase"
    }
}

private struct ListedFileRenameScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 6) {
                LCDInvertTitle(FirmwareCopy.uxInputTextPrompt)
                TextField("", text: $store.passphraseInput)
                    .coldcardField()
                    .onChange(of: store.passphraseInput) { _, value in
                        store.errorMessage = nil
                        if value.count > 32 {
                            store.passphraseInput = String(value.prefix(32))
                        }
                    }
                if let error = store.errorMessage {
                    Text(error)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundStyle(mutedText)
                        .frame(maxWidth: .infinity)
                }
                Text(FirmwareCopy.uxInputTextDoneFooter)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .frame(maxWidth: .infinity)
                Spacer()
                LCDHitStrip(label: "Save") { store.saveListedFileRename() }
            }
            .padding(8)
        }
    }
}

private struct PassphraseConfirmScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDStoryView(store: store, 
                title: store.pendingPassphraseXFP.isEmpty ? "" : "[\(store.pendingPassphraseXFP)]",
                bodyText: store.passphraseConfirmBody
            )
        }
    }
}

private struct AddressListScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDStoryView(store: store, bodyText: store.addressListStory)
        }
    }
}

private struct AddressDetailScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            if let address = store.selectedAddress {
                LCDStoryView(store: store, bodyText: """
                Showing single address.

                \(address.path) =>
                \(SimulatorStore.chunkAddress(address.address))

                 Press (0) to sign message with this key.
                """)
            }
        }
    }
}

private struct AccountNumberScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 8) {
                LCDInvertTitle(store.screenTitle)
                TextField("", text: $store.accountPromptValue)
                    .keyboardType(.numberPad)
                    .coldcardField()
                    .onSubmit { store.submitAccountNumber() }
                Text("CANCEL or ENTER when done.")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
            .padding(8)
        }
    }
}

private struct PSBTScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            if store.psbtReview != nil {
                LCDStoryView(store: store, 
                    title: store.screenTitle,
                    bodyText: store.psbtApprovalBody
                )
            } else {
                LCDStoryView(
                    store: store,
                    title: store.screenTitle,
                    bodyText: store.psbtEmptyStory,
                    hintQR: true,
                    hintNFC: store.preferences.nfcSharingEnabled
                )
            }
        }
    }
}

private struct NFCReceiveScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                let phase = Int(timeline.date.timeIntervalSinceReferenceDate * 4) % 2
                VStack(alignment: .center, spacing: 6) {
                    Spacer(minLength: 0)
                    Text(phase == 0 ? "[ NFC ]" : "[     ]")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(screenText)
                    Spacer(minLength: 0)
                    Text(ReadyToSign.nfcReceivePrompt)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(mutedText)
                        .multilineTextAlignment(.center)
                    if store.nfcReceiveNeedsStandIn {
                        Text("ENTER to paste, (1) to import a file.")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(mutedText)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
            }
        }
    }
}

private struct SignedPSBTScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDStoryView(
                store: store,
                title: store.screenTitle,
                bodyText: store.signedTransactionStory,
                hintQR: true,
                hintNFC: store.preferences.nfcSharingEnabled
            )
        }
    }
}

private struct WalletExportScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDStoryView(
                store: store,
                title: store.walletExportTitle,
                bodyText: store.walletExportText,
                hintQR: true,
                hintNFC: store.preferences.nfcSharingEnabled
            )
        }
    }
}

private struct MessageSigningScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 6) {
                LCDInvertTitle("Enter MSG")
                if store.messageText.isEmpty {
                    Text(" ")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(mutedText)
                } else {
                    Text(store.messageText)
                        .font(.system(size: 8.5, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                LCDHitStrip(label: "ENTER") { store.signMessage() }
            }
            .padding(8)
        }
    }
}

private struct NoteEditorScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if store.noteEditorMode == .changePassword {
                        Text("\"\(store.noteTitle)\"").foregroundStyle(screenText)
                        passwordFields
                    } else {
                        LCDInvertTitle("Title")
                        TextField("(required for menu)", text: $store.noteTitle)
                            .coldcardField()
                            .onChange(of: store.noteTitle) { _, value in
                                if value.count > SecureNotesSupport.oneLineLimit {
                                    store.noteTitle = String(value.prefix(SecureNotesSupport.oneLineLimit))
                                }
                            }
                        if store.noteEditorMode == .createPassword || store.noteEditorMode == .editPasswordMetadata {
                            LCDInvertTitle("Username")
                            TextField("(optional)", text: $store.noteUsername)
                                .coldcardField()
                                .onChange(of: store.noteUsername) { _, value in
                                    if value.count > SecureNotesSupport.oneLineLimit {
                                        store.noteUsername = String(value.prefix(SecureNotesSupport.oneLineLimit))
                                    }
                                }
                            if store.noteEditorMode == .createPassword {
                                passwordFields
                            }
                            LCDInvertTitle("Website")
                            TextField("(optional)", text: $store.noteSite)
                                .coldcardField()
                                .onChange(of: store.noteSite) { _, value in
                                    if value.count > SecureNotesSupport.oneLineLimit {
                                        store.noteSite = String(value.prefix(SecureNotesSupport.oneLineLimit))
                                    }
                                }
                            LCDInvertTitle("More Notes")
                            TextField("(optional)", text: $store.noteBody, axis: .vertical).coldcardField()
                        } else {
                            LCDInvertTitle("Your Notes")
                            TextField("(freeform text)", text: $store.noteBody, axis: .vertical).coldcardField()
                        }
                    }
                    LCDHitStrip(label: "Save note") { store.addSecureNote() }
                }.padding(7)
            }
        }
    }

    @ViewBuilder private var passwordFields: some View {
        LCDInvertTitle("Password")
        SecureField("(optional)", text: $store.notePassword)
            .coldcardField()
            .onChange(of: store.notePassword) { _, value in
                if value.count > SecureNotesSupport.passwordLimit {
                    store.notePassword = String(value.prefix(SecureNotesSupport.passwordLimit))
                }
            }
        Text(SecureNotes.passwordFunctionKeyLegend)
            .font(.system(size: 6.5, design: .monospaced))
            .foregroundStyle(mutedText)
            .frame(maxWidth: .infinity)
        HStack(spacing: 4) {
            ForEach(1...6, id: \.self) { key in
                Button("F\(key)") { store.generateNotePassword(key) }
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lcdText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .buttonStyle(.plain)
                    .accessibilityLabel("F\(key)")
            }
        }
    }
}

private struct BackupPasswordScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(BackupFile.recordPasswordPrompt)
                        .font(.system(size: 8.5, design: .monospaced))
                    Text(SeedXOR.renderPartWords(store.backupPasswordWords))
                        .font(.system(size: 8, design: .monospaced))
                    Text(FirmwareCopy.seedWordsFooter)
                        .font(.system(size: 8, design: .monospaced))
                    if store.pendingNotesFileExport {
                        Text(BackupFile.cleartextKeyHint)
                            .font(.system(size: 8, design: .monospaced))
                    }
                }
                .padding(8)
            }
            LCDHitStrip(label: "Continue") { store.continueBackupPassword() }
        }
    }
}

private struct HexEntryScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 6) {
                LCDInvertTitle(FirmwareCopy.tapsignerKeyPrompt)
                TextField("", text: $store.hexEntryText)
                    .coldcardField()
                    .onChange(of: store.hexEntryText) { _, value in
                        store.hexEntryText = SimulatorStore.normalizedHexEntry(value)
                    }
                Text("\(store.hexEntryText.count)/32")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(mutedText)
                Spacer()
                LCDHitStrip(label: "Confirm") { store.confirmHexEntry() }
            }
            .padding(8)
        }
    }
}

private struct VerifyBackupScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 4) {
                LCDInvertTitle("Enter Password:")
                SeedWordColumns(words: passwordWords)
                    .padding(.horizontal, 6)
                TextField("", text: $store.backupPassword)
                    .coldcardField()
                    .padding(.horizontal, 6)
                Spacer()
                LCDHitStrip(label: "Confirm backup password") {
                    if store.pendingEncryptedNotesData != nil {
                        store.decryptAndImportNotes()
                    } else if store.importPurpose == .backup {
                        store.showFileImporter = true
                    } else {
                        store.requestVerifyBackup()
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var passwordWords: [String] {
        var words = store.backupPassword.split(whereSeparator: \.isWhitespace).map(String.init)
        while words.count < 12 { words.append("") }
        if words.count > 12 { words = Array(words.prefix(12)) }
        return words
    }
}

private struct CalculatorScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(spacing: 4) {
                LCDInvertTitle(" ECC Calculator ")
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(store.calculatorLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(line.hasPrefix(">> ") ? mutedText : screenText)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: store.calculatorLines.count) { _, count in
                        proxy.scrollTo(max(0, count - 1))
                    }
                }
                Text("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Text(">>").font(.system(size: 10, design: .monospaced))
                    TextField("", text: $store.calculatorExpression)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .coldcardField()
                        .onChange(of: store.calculatorExpression) { _, value in
                            if value.count > CalculatorLogin.maxInputLength {
                                store.calculatorExpression = String(value.prefix(CalculatorLogin.maxInputLength))
                            }
                        }
                        .onSubmit { store.evaluateCalculator() }
                }
            }.padding(6)
        }
    }
}

private struct SerialREPLScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(spacing: 4) {
                LCDInvertTitle(" Serial REPL ")
                Text(store.serialREPL.statusLine)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LCDCheckbox(label: "VCP enabled", isOn: $store.serialREPLVCPEnabled)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(store.serialREPL.lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(line.hasPrefix(">>> ") ? mutedText : screenText)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: store.serialREPL.lines.count) { _, count in
                        proxy.scrollTo(max(0, count - 1))
                    }
                }
                Text("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Text(">>>").font(.system(size: 10, design: .monospaced))
                    TextField("", text: $store.serialREPLInput)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .coldcardField()
                        .onSubmit { store.submitSerialREPL() }
                }
            }.padding(6)
        }
    }
}

private struct StoryScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDStoryView(
                store: store,
                title: store.story.title,
                bodyText: store.story.body,
                hintQR: store.story.hintQR,
                hintNFC: store.story.hintNFC,
                onTap: store.story.confirmCode == nil ? { store.confirmStory() } : nil
            )
        }
    }
}

private struct ViewIdentityScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDStoryView(
                store: store,
                bodyText: store.identityText,
                hintQR: true,
                hintNFC: store.preferences.nfcSharingEnabled
            )
        }
    }
}

private struct BrickScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDStoryView(store: store,
                title: store.screenTitle,
                bodyText: LoginUX.brickStory(numFails: max(store.failedPINAttempts, 1))
            )
        }
    }
}

private struct PoweredOffScreen: View {
    var body: some View {
        Color.black
    }
}

private struct FactoryBaggedScreen: View {
    @Bindable var store: SimulatorStore
    @Environment(\.lcdMetrics) private var metrics

    var body: some View {
        ScreenScaffold(store: store) {
            VStack(spacing: 0) {
                ForEach(0..<LCDDisplay.charsH, id: \.self) { row in
                    Group {
                        if row == 3 {
                            Text(" \(store.displayedBagNumber ?? FirmwareCopy.unbaggedTitle) ")
                                .font(.system(size: metrics.monoFontSize, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.black)
                                .background(screenText)
                                .frame(maxWidth: .infinity)
                        } else if row == 6 {
                            Text(FirmwareCopy.putIntoBagAndSeal)
                                .font(.system(size: metrics.monoFontSize, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 4)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: metrics.cellHeight)
                }
            }
        }
    }
}

private struct FactoryDFUScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDFullscreenMessage(title: FirmwareCopy.enterBootloaderDFU)
        }
    }
}

private struct WordEntryScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 4) {
                LCDInvertTitle(store.screenTitle)
                SeedWordColumns(
                    words: displayedWords,
                    currentIndex: store.wordEntryComplete ? nil : store.wordEntryFilledCount,
                    cursor: store.wordEntryComplete ? nil : store.wordEntryCursor
                )
                    .padding(.horizontal, 6)
                if !store.wordEntryHint.isEmpty {
                    Text(store.wordEntryHint)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundStyle(mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                }
            }.padding(.top, 4)
        }
    }

    private var displayedWords: [String] {
        var words = store.wordEntryWords
        let index = store.wordEntryFilledCount
        if words.indices.contains(index), !store.wordEntryPrefix.isEmpty {
            words[index] = store.wordEntryPrefix
        }
        return words
    }
}

private struct EntropyCollectScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDFullscreenMessage(
                title: store.screenTitle,
                line2: store.entropyCollectLine2,
                line3: store.entropyCollectLine3,
                progress: entropyProgress
            )
        }
    }

    private var entropyProgress: Double {
        switch store.entropyKind {
        case .mash: Double(store.mashCount) / 65
        case .coin: Double(store.coinFlips.count) / 128
        case .diceMix: Double(store.diceRolls.count) / 50
        }
    }
}

/// Firmware `Display.fullscreen` / `update_entropy_screen` on Q.
private struct LCDFullscreenMessage: View {
    var title: String
    var line2: String?
    var line3: String?
    var progress: Double?

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(title)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity)
            if let line2 {
                Text(line2)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .frame(maxWidth: .infinity)
            }
            if let line3 {
                Text(line3)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            }
            Spacer()
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.12))
                        Rectangle()
                            .fill(coldcardGold)
                            .frame(width: geo.size.width * min(1, max(0, progress)))
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

private struct PSBTExplorerScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDStoryView(store: store, title: store.screenTitle, bodyText: store.psbtExplorerBody)
        }
    }
}

private struct LoginCountdownScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(spacing: 10) {
                LCDInvertTitle(FirmwareCopy.loginCountdownTitle)
                Text(store.loginCountdownMustWait)
                    .font(.system(size: 9, design: .monospaced))
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity)
                Text(store.loginCountdownDelayText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 8)
        }
    }
}

private struct TypePasswordIndexScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            VStack(alignment: .leading, spacing: 8) {
                LCDInvertTitle(store.screenTitle)
                TextField("", text: $store.typePasswordIndexText)
                    .keyboardType(.numberPad)
                    .coldcardField()
                    .onSubmit { store.submitTypePasswordIndex() }
                Text("CANCEL or ENTER when done.")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
            .padding(8)
        }
    }
}

private struct TypePasswordConfirmScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScreenScaffold(store: store) {
            LCDStoryView(store: store, bodyText: store.typePasswordConfirmBody) {
                store.confirmTypePasswordSend()
            }
        }
    }
}

private struct SeedWordColumns: View {
    let words: [String]
    var currentIndex: Int? = nil
    var cursor: PINCursor? = nil
    var body: some View {
        let columns = SeedCreation.columnCount(wordCount: words.count)
        let rows = SeedCreation.rows(wordCount: words.count)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 4) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = SeedCreation.gridIndex(row: row, column: col, wordCount: words.count)
                        if words.indices.contains(index) {
                            let word = words[index]
                            ZStack(alignment: .leading) {
                                Text(SeedCreation.drawCell(index: index, word: word, count: words.count))
                                    .font(.system(size: 8, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if currentIndex == index, let cursor, cursor.style == .outline {
                                    PINLCDCursorMark(style: .outline)
                                        .frame(width: 8, height: 10)
                                        .offset(x: CGFloat(8 + min(word.count, 8)) * 5, y: 0)
                                        .accessibilityLabel("Outline cursor on eighth letter")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private extension View {
    func coldcardField() -> some View {
        self
            .font(.system(size: 10, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

import SwiftUI
import UIKit
import ColdcardCore

private let coldcardGold = Color(red: 0.72, green: 0.54, blue: 0.20)

@MainActor
private func walletExportHelperText(for store: SimulatorStore) -> String? {
    guard let kind = store.pendingExport, kind.firmwarePrompt != nil else { return nil }
    return kind.firmwareIntroStory
}

struct PhoneInterfaceView: View {
    @Bindable var store: SimulatorStore
    @FocusState private var acceptsHardwareKeyboardInput: Bool

    var body: some View {
        NavigationStack {
            screenContent
                .navigationTitle(store.screenTitle.isEmpty ? "COLDCARD" : store.screenTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if store.showsBack {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { store.back() } label: { Image(systemName: "chevron.backward") }
                                .accessibilityLabel("Back")
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { store.handleQRKey() } label: { Image(systemName: "qrcode") }
                            .accessibilityLabel("QR")
                            .accessibilityHint(store.scannerPrompt)
                        Button { store.interfaceMode = .device } label: { Image(systemName: "candybarphone") }
                            .accessibilityLabel("Show Coldcard Q device")
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) { messageBanner }
                .safeAreaInset(edge: .bottom, spacing: 0) { statusFooter }
                .overlay {
                    if store.isWorking {
                        ZStack {
                            if store.gpuBusyBar {
                                VStack {
                                    Spacer()
                                    ProgressView().tint(coldcardGold)
                                        .padding(.bottom, 24)
                                }
                            } else {
                                Color.black.opacity(0.55).ignoresSafeArea()
                                VStack(spacing: 10) {
                                    if let progress = store.busyProgress {
                                        ProgressView(value: progress)
                                            .tint(coldcardGold)
                                            .frame(width: 180)
                                    } else {
                                        ProgressView().tint(coldcardGold)
                                    }
                                    Text(store.busyTitle.isEmpty ? "Wait..." : store.busyTitle).font(.caption.bold())
                                }
                            }
                        }
                    } else if let progress = store.bbqrScanProgress, !progress.skipsProgressUI {
                        PhoneBBQrProgressOverlay(progress: progress)
                    }
                }
        }
        .tint(coldcardGold)
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
        if press.key == .return { return .returnKey }
        if press.key == .escape { return .escape }
        if press.key == .delete || press.key == .deleteForward { return .delete }
        if press.key == .tab { return .tab }
        if press.key == .space { return .characters(" ") }
        return .characters(press.characters)
    }

    @ViewBuilder private var screenContent: some View {
        switch store.screen {
        case .menu: PhoneFirmwareMenuScreen(store: store)
        case .unlock: PhoneUnlockScreen(store: store)
        case .pinSetup: PhonePINSetupScreen(store: store)
        case .seedWords: PhoneSeedWordsScreen(store: store)
        case .wordQuiz: PhoneWordQuizScreen(store: store)
        case .diceRoll: PhoneDiceRollScreen(store: store)
        case .importSeed: PhoneImportSeedScreen(store: store)
        case .passphrase: PhonePassphraseScreen(store: store)
        case .listedFileRename: PhoneListedFileRenameScreen(store: store)
        case .passphraseConfirm: PhonePassphraseConfirmScreen(store: store)
        case .addresses: PhoneAddressListScreen(store: store)
        case .addressDetail: PhoneAddressDetailScreen(store: store)
        case .accountNumber: PhoneAccountNumberScreen(store: store)
        case .psbt: PhonePSBTScreen(store: store)
        case .nfcReceive: PhoneNFCReceiveScreen(store: store)
        case .psbtSigned: PhoneSignedPSBTScreen(store: store)
        case .walletExport: PhoneWalletExportScreen(store: store)
        case .messageSigning: PhoneMessageSigningScreen(store: store)
        case .noteEditor: PhoneNoteEditorScreen(store: store)
        case .backupPassword: PhoneBackupPasswordScreen(store: store)
        case .verifyBackup: PhoneVerifyBackupScreen(store: store)
        case .hexEntry: PhoneHexEntryScreen(store: store)
        case .calculator: PhoneCalculatorScreen(store: store)
        case .story: PhoneStoryScreen(store: store)
        case .viewIdentity: PhoneViewIdentityScreen(store: store)
        case .brick: PhoneBrickScreen(store: store)
        case .wordEntry: PhoneWordEntryScreen(store: store)
        case .entropyCollect: PhoneEntropyCollectScreen(store: store)
        case .psbtExplorer: PhonePSBTExplorerScreen(store: store)
        case .loginCountdown: PhoneLoginCountdownScreen(store: store)
        case .nicknameSplash: PhoneNicknameSplashScreen(store: store)
        case .typePasswordIndex: PhoneTypePasswordIndexScreen(store: store)
        case .typePasswordConfirm: PhoneTypePasswordConfirmScreen(store: store)
        case .serialREPL: PhoneSerialREPLScreen(store: store)
        case .factoryBagged: PhoneFactoryBaggedScreen(store: store)
        case .factoryDFU: PhoneFactoryDFUScreen(store: store)
        case .poweredOff: PhonePoweredOffScreen(store: store)
        }
    }

    @ViewBuilder private var messageBanner: some View {
        if let error = store.errorMessage {
            banner(text: error, color: .red, icon: "exclamationmark.triangle.fill")
        } else if let status = store.statusMessage {
            banner(text: status, color: .green, icon: "checkmark.circle.fill")
        }
    }

    private func banner(text: String, color: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12))
    }

    private var statusFooter: some View {
        HStack {
            Circle().fill(store.isUnlocked ? Color.green : Color.red).frame(width: 8, height: 8)
            Text(store.nickname)
            Spacer()
            if LCDStatus.bip39IconOn(passphrase: store.activePassphrase) {
                Text("B39").foregroundStyle(coldcardGold)
            }
            if LCDStatus.tmpIconOn(hasEphemeralSeed: store.ephemeralPhrase != nil || store.ephemeralXPRV != nil) {
                Text("TMP").foregroundStyle(coldcardGold)
            }
            Text(store.lcdXFPGlyphs ?? "--------")
                .foregroundStyle(coldcardGold)
                .textCase(.lowercase)
            Text(store.network == .mainnet ? "BTC" : store.network == .testnet ? "XTN" : "XRT")
                .foregroundStyle(.secondary)
        }
        .font(.caption.monospaced())
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct PhoneBBQrProgressOverlay: View {
    let progress: BBQrScanProgress

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 6) {
                if !progress.partPattern.isEmpty {
                    Text(progress.partPattern)
                        .font(.caption.monospaced())
                }
                Text(progress.instructionLine)
                    .font(.subheadline.weight(.semibold))
                Text(progress.countLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress.fraction)
                    .tint(coldcardGold)
                    .frame(width: 180)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.statusMessage)
    }
}

private struct PhoneActionButton: View {
    let title: String
    var prominent = false
    var disabled = false
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .fontWeight(prominent ? .semibold : .regular)
                .frame(maxWidth: .infinity)
        }
        .disabled(disabled)
    }
}

private struct PhoneMenuRow: View {
    let title: String
    var subtitle: String? = nil
    var checked = false
    var simulatorOnly = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).foregroundStyle(.primary)
                        if simulatorOnly {
                            Text("SIM").font(.caption2.bold()).foregroundStyle(coldcardGold)
                        }
                    }
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if checked {
                    Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(coldcardGold)
                }
                Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct PhoneFirmwareMenuScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            ForEach(Array(store.menuItems.enumerated()), id: \.element.id) { index, item in
                if item.isPaperWalletFormatChooser {
                    Picker(selection: Binding(
                        get: { store.paperWalletIsSegwit },
                        set: { store.selectedMenuIndex = index; store.setPaperWalletSegwit($0) }
                    )) {
                        Text("Classic P2PKH").tag(false)
                        Text("Segwit P2WPKH").tag(true)
                    } label: {
                        Text(store.paperWalletIsSegwit ? "Segwit P2WPKH" : "Classic P2PKH")
                    }
                    .pickerStyle(.menu)
                } else {
                    PhoneMenuRow(title: item.title, subtitle: item.subtitle, checked: item.checked,
                                 simulatorOnly: item.simulatorOnly) {
                        store.selectedMenuIndex = index
                        if store.currentMenu == .xorVaultPick {
                            store.toggleXORVaultPick()
                        } else {
                            store.activateCurrentSelection()
                        }
                    }
                }
            }
            if store.currentMenu == .xorVaultPick {
                Section {
                    PhoneActionButton(title: "PRESS 1 — select") { store.typeCharacter("1") }
                    PhoneActionButton(title: "ENTER", prominent: true) { store.activateCurrentSelection() }
                } footer: {
                    Text("Press (1) to select or deselect, ENTER when done.")
                }
            }
        }
    }
}

private struct PhoneNicknameSplashScreen: View {
    @Bindable var store: SimulatorStore
    @State private var keystroke = ""
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(store.nickname)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(coldcardGold)
                .padding(.horizontal)
            Spacer()
            TextField("Press any key", text: $keystroke)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .onChange(of: keystroke) { _, value in
                    guard let ch = value.last else { return }
                    keystroke = ""
                    store.typeCharacter(String(ch))
                }
                .padding(.horizontal)
            PhoneActionButton(title: "Continue", prominent: true) { store.dismissNicknameSplash() }
                .padding(.horizontal)
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture { store.dismissNicknameSplash() }
    }
}

private struct PhoneUnlockScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                if store.unlockPhase == .prefix {
                    Text(FirmwareCopy.pinPrefixPrompt).foregroundStyle(.secondary)
                } else {
                    Text(FirmwareCopy.pinSuffixPrompt).foregroundStyle(.secondary)
                    Text(store.antiPhishingWords(for: store.pinPrefix)).foregroundStyle(coldcardGold)
                }
                HStack(spacing: 8) {
                    Text(String(repeating: "•", count: store.unlockPhase == .prefix ? store.pinInput.count : store.pinPrefix.count))
                        .font(.title.monospaced())
                    Text("⋯").foregroundStyle(.secondary)
                    Text(store.unlockPhase == .prefix ? "" : String(repeating: "•", count: store.pinInput.count))
                        .font(.title.monospaced())
                }
            }
            if !store.scrambleDigitMap.isEmpty {
                Section {
                    let rows = PINEntryChrome.scrambleMap(from: store.scrambleDigitMap)
                    Text(rows.invertedDigits)
                        .font(.caption.monospaced())
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .background(Color.primary)
                    Text(rows.keyLegend)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                PhonePINKeypad(scrambleMap: store.scrambleDigitMap) { store.typeCharacter($0) }
                PhoneLoginKeyCapture { store.typeCharacter($0) }
            }
            Section {
                PhoneActionButton(
                    title: store.unlockPhase == .prefix ? "Continue" : "Unlock",
                    prominent: true,
                    disabled: store.pinInput.count < 2
                ) { store.unlock() }
                PhoneActionButton(title: "CANCEL") { store.back() }
            }
            if !store.unlockFooter.isEmpty {
                Section { Text(store.unlockFooter).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct PhoneLoginKeyCapture: View {
    @State private var keystroke = ""
    let onKey: (String) -> Void

    var body: some View {
        TextField("Press any key", text: $keystroke)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .onChange(of: keystroke) { _, value in
                guard let ch = value.last else { return }
                keystroke = ""
                onKey(String(ch))
            }
            .accessibilityLabel("Kill key and other login keys")
    }
}

private struct PhonePINKeypad: View {
    var scrambleMap: [Character: Character]
    let onDigit: (String) -> Void

    var body: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["0"]]
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { physical in
                        let shown = String(LoginUX.scrambledDigit(physical.first ?? "0", map: scrambleMap))
                        Button {
                            onDigit(physical)
                        } label: {
                            VStack(spacing: 2) {
                                Text(shown).font(.title2.monospaced())
                                if !scrambleMap.isEmpty {
                                    Text(physical).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

private struct PhonePINSetupScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            switch store.pinSetupPhase {
            case .warning, .proveRead:
                EmptyView()
            case .prefix, .confirmPrefix:
                Section {
                    if store.pinSetupPurpose == .trickNew || store.pinSetupPurpose == .trickChange {
                        Text("New Trick PIN").foregroundStyle(.secondary)
                    } else if store.pinSetupPurpose == .ssspBypass {
                        Text("Spending Policy Unlock").foregroundStyle(.secondary)
                    } else if store.pinSetupCollectingOld {
                        Text("Old Main PIN").foregroundStyle(.secondary)
                    } else if store.pinSetupIsChange {
                        Text("New Main PIN").foregroundStyle(.secondary)
                    }
                    Text(FirmwareCopy.pinPrefixPrompt).foregroundStyle(.secondary)
                    SecureField("", text: $store.pinPrefix)
                        .keyboardType(.numberPad)
                        .font(.body.monospaced())
                        .onChange(of: store.pinPrefix) { _, value in
                            store.pinPrefix = SimulatorStore.clampPINPart(value)
                        }
                } footer: {
                    if store.pinSetupPhase == .confirmPrefix {
                        Text(FirmwareCopy.confirmPINValue)
                    }
                }
                Section { PhoneActionButton(title: "Continue", prominent: true) { store.advancePINSetup() } }
            case .suffix, .confirmSuffix:
                Section {
                    if store.pinSetupPurpose == .trickNew || store.pinSetupPurpose == .trickChange {
                        Text("New Trick PIN").foregroundStyle(.secondary)
                    } else if store.pinSetupPurpose == .ssspBypass {
                        Text("Spending Policy Unlock").foregroundStyle(.secondary)
                    } else if store.pinSetupCollectingOld {
                        Text("Old Main PIN").foregroundStyle(.secondary)
                    } else if store.pinSetupIsChange {
                        Text("New Main PIN").foregroundStyle(.secondary)
                    }
                    Text(FirmwareCopy.pinSuffixPrompt).foregroundStyle(.secondary)
                    Text(store.antiPhishingWords(for: store.pinPrefix)).foregroundStyle(coldcardGold)
                    SecureField("", text: $store.pinInput)
                        .keyboardType(.numberPad)
                        .font(.body.monospaced())
                        .onChange(of: store.pinInput) { _, value in
                            store.pinInput = SimulatorStore.clampPINPart(value)
                        }
                } footer: {
                    if store.pinSetupPhase == .confirmSuffix {
                        Text(FirmwareCopy.confirmPINValue)
                    }
                }
                Section { PhoneActionButton(title: "Continue", prominent: true) { store.advancePINSetup() } }
            }
        }
    }
}

private struct PhoneSeedWordsScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            Section {
                SeedWordList(words: store.mnemonicWords)
                Text(FirmwareCopy.seedWordsNotes(ephemeral: store.pendingEphemeral)).foregroundStyle(.secondary)
                if store.pendingEphemeral {
                    Text(SeedCreation.skipQuizHint).foregroundStyle(.secondary)
                }
            }
            if store.pendingMnemonic != nil || store.xorQuizzingSplit {
                Section {
                    PhoneActionButton(title: "Continue", prominent: true) { store.continueAfterSeedWords() }
                    if store.pendingMnemonic != nil, !store.xorQuizzingSplit {
                        PhoneActionButton(title: "PRESS (6)") { store.typeCharacter("6") }
                    }
                }
            }
        }
    }
}

private struct PhoneWordQuizScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            Section {
                if let quiz = store.wordQuiz {
                    ForEach(Array(quiz.choices.enumerated()), id: \.offset) { index, word in
                        Button(" \(index + 1): \(word)") { store.answerWordQuiz(word) }
                            .disabled(store.quizWrongPause)
                    }
                }
                Text(SeedCreation.quizPrompt).foregroundStyle(.secondary)
            }
            Section { PhoneActionButton(title: "See words again") { store.reviewSeedWordsFromQuiz() } }
            Section { Text(SeedCreation.quizGiveUp).foregroundStyle(.secondary) }
        }
        .overlay {
            if store.quizWrongPause {
                Color.black.opacity(0.7).ignoresSafeArea()
                Text("Wrong!").font(.largeTitle.bold()).foregroundStyle(.red)
            }
        }
    }
}

private struct PhoneDiceRollScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                Text("Press 1-6 for each dice roll to mix in.").foregroundStyle(.secondary)
                LabeledContent("Rolls so far", value: "\(store.diceRolls.count)")
                if !store.diceRunningHash.isEmpty {
                    Text(store.diceRunningHashLines.top).font(.caption.monospaced()).foregroundStyle(coldcardGold)
                    Text("  " + store.diceRunningHashLines.bottom).font(.caption.monospaced()).foregroundStyle(coldcardGold)
                }
                Text(store.diceRolls.isEmpty ? " " : store.diceRolls).font(.body.monospaced())
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                    ForEach(["1", "2", "3", "4", "5", "6"], id: \.self) { digit in
                        Button(digit) { store.addDiceRoll(Character(digit)) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            Section { PhoneActionButton(title: "Done", prominent: true) { store.finishDiceRolls() } }
        }
    }
}

private struct PhoneImportSeedScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                Text("Enter \(store.seedWordCount) words or SeedQR digits").foregroundStyle(.secondary)
                TextEditor(text: $store.importSeedText)
                    .frame(minHeight: 120)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                PhoneActionButton(title: "Validate", prominent: true) { store.validateImportedSeed() }
            } footer: {
                Text(store.scannerPrompt)
            }
        }
    }
}

private struct PhonePassphraseScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            if store.renamingVaultSeedID != nil {
                Section { TextField("Label", text: $store.passphraseInput)
                    .onChange(of: store.passphraseInput) { _, value in
                        if value.count > SeedVaultMenuCopy.renameMaxLength {
                            store.passphraseInput = String(value.prefix(SeedVaultMenuCopy.renameMaxLength))
                        }
                    }
                }
                Section { PhoneActionButton(title: "Save", prominent: true) { store.saveVaultRename() } }
            } else if store.renamingMultisigIndex != nil {
                Section { TextField("Name", text: $store.passphraseInput)
                    .onChange(of: store.passphraseInput) { _, value in
                        if value.count > 20 { store.passphraseInput = String(value.prefix(20)) }
                    }
                }
                Section { PhoneActionButton(title: "Save", prominent: true) { store.saveMultisigRename() } }
            } else if store.textEntryIsNickname {
                Section { TextField(LoginUX.nicknamePrompt, text: $store.passphraseInput) }
                Section { PhoneActionButton(title: "Save", prominent: true) { store.saveNicknameFromField() } }
            } else if store.textEntryIsNoteGroup {
                Section { TextField("Group", text: $store.passphraseInput)
                    .onChange(of: store.passphraseInput) { _, value in
                        if value.count > SecureNotesSupport.oneLineLimit {
                            store.passphraseInput = String(value.prefix(SecureNotesSupport.oneLineLimit))
                        }
                    }
                }
                Section { PhoneActionButton(title: "Save", prominent: true) { store.saveNoteGroupFromField() } }
            } else if store.textEntryIsKeyboardTest {
                Section {
                    Text(DeveloperDebug.keyboardTestPrompt).foregroundStyle(.secondary)
                    TextField(DeveloperDebug.keyboardTestPlaceholder, text: $store.passphraseInput)
                        .onChange(of: store.passphraseInput) { _, value in
                            if value.count > DeveloperDebug.keyboardTestMaxLength {
                                store.passphraseInput = String(value.prefix(DeveloperDebug.keyboardTestMaxLength))
                            }
                        }
                } footer: {
                    Text("QR to scan. ENTER when done.")
                }
                Section {
                    PhoneActionButton(title: "Done", prominent: true) { store.finishKeyboardTest() }
                }
            } else if store.textEntryIsBKPWOverride {
                Section {
                    Text(DeveloperDebug.bkpwPasswordPrompt).foregroundStyle(.secondary)
                    TextField("Min \(DeveloperDebug.bkpwMinLength) characters", text: $store.passphraseInput)
                        .onChange(of: store.passphraseInput) { _, value in
                            if value.count > DeveloperDebug.bkpwMaxLength {
                                store.passphraseInput = String(value.prefix(DeveloperDebug.bkpwMaxLength))
                            }
                        }
                } footer: {
                    Text(store.passphraseCompletionHint)
                }
                Section {
                    PhoneActionButton(title: "Save", prominent: true) { store.commitBKPWOverride() }
                        .disabled(store.passphraseInput.count < DeveloperDebug.bkpwMinLength)
                }
            } else if store.textEntryIsNotesImportPassword {
                Section {
                    Text("Your Backup Password").foregroundStyle(.secondary)
                    TextField("Min \(SecureNotes.customPasswordMinLength) characters", text: $store.passphraseInput)
                        .onChange(of: store.passphraseInput) { _, value in
                            if value.count > SecureNotes.customPasswordMaxLength {
                                store.passphraseInput = String(value.prefix(SecureNotes.customPasswordMaxLength))
                            }
                        }
                } footer: {
                    Text(store.passphraseCompletionHint)
                }
                Section {
                    PhoneActionButton(title: "Continue", prominent: true) { store.commitNotesImportPassword() }
                        .disabled(store.passphraseInput.count < SecureNotes.customPasswordMinLength)
                }
            } else if store.textEntryIsCustomBackupPassword {
                Section {
                    Text(BackupFile.backupPasswordPrompt).foregroundStyle(.secondary)
                    SecureField("Min \(DeveloperDebug.bkpwMinLength) characters", text: $store.passphraseInput)
                        .onChange(of: store.passphraseInput) { _, value in
                            if value.count > DeveloperDebug.bkpwMaxLength {
                                store.passphraseInput = String(value.prefix(DeveloperDebug.bkpwMaxLength))
                            }
                        }
                } footer: {
                    Text(store.passphraseCompletionHint)
                }
                Section {
                    PhoneActionButton(title: "Continue", prominent: true) { store.commitCustomBackupPassword() }
                        .disabled(store.passphraseInput.count < DeveloperDebug.bkpwMinLength)
                }
            } else if store.textEntryIsPushtxURL {
                Section {
                    Text(FirmwareCopy.enterPushtxURL).foregroundStyle(.secondary)
                    TextField("https://host/pushtx#", text: $store.passphraseInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: store.passphraseInput) { _, value in
                            if value.count > 256 {
                                store.passphraseInput = String(value.prefix(256))
                            }
                        }
                } footer: {
                    Text("Must start with http:// or https:// and end with #, ?, or &. QR to scan.")
                }
                Section {
                    PhoneActionButton(title: "Save", prominent: true) { store.commitPushtxURLFromField() }
                    PhoneActionButton(title: "Scan QR") { store.showScanner = true }
                }
            } else if store.textEntryIsWIF {
                Section {
                    Text("Enter WIF").foregroundStyle(.secondary)
                    TextField("Compressed WIF (52 characters)", text: $store.passphraseInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: store.passphraseInput) { _, value in
                            if value.count > 52 {
                                store.passphraseInput = String(value.prefix(52))
                            }
                        }
                } footer: {
                    Text(store.passphraseCompletionHint)
                }
                Section {
                    PhoneActionButton(title: "Import", prominent: true) { store.commitManualWIFEntry() }
                }
            } else if store.textEntryIsNFCSeed {
                Section {
                    Text("Paste 12, 18, or 24 seed words").foregroundStyle(.secondary)
                    TextEditor(text: $store.passphraseInput)
                        .frame(minHeight: 120)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(store.passphraseCompletionHint)
                }
                Section {
                    PhoneActionButton(title: "Import", prominent: true) { store.finishNFCSeedPaste() }
                    PhoneActionButton(title: "Import file") { store.beginNFCStandInFileImport() }
                }
            } else if store.textEntryIsNFCTools {
                Section {
                    Text(store.nfcStandInPrompt).foregroundStyle(.secondary)
                    TextEditor(text: $store.passphraseInput)
                        .frame(minHeight: 120)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(store.passphraseCompletionHint)
                }
                Section {
                    PhoneActionButton(title: "Use pasted text", prominent: true) { store.finishNFCToolsPaste() }
                    PhoneActionButton(title: "Import file") { store.beginNFCStandInFileImport() }
                    PhoneActionButton(title: "Scan QR") { store.beginNFCToolsQRStandIn() }
                }
            } else if store.teleportTextKind != .none {
                Section {
                    Text(store.teleportPassphrasePrompt ?? "").foregroundStyle(.secondary)
                    if store.teleportTextKind == .numericPassword {
                        TextField("########", text: $store.passphraseInput)
                            .keyboardType(.numberPad)
                            .onChange(of: store.passphraseInput) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(KeyTeleport.numericCodeLength))
                                if digits != value { store.passphraseInput = digits }
                            }
                    } else if store.teleportTextKind == .quickNote {
                        TextField(KeyTeleportCopy.quickNotePlaceholder, text: $store.passphraseInput, axis: .vertical)
                    } else {
                        TextField("********", text: $store.passphraseInput)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: store.passphraseInput) { _, value in
                                if value.count > KeyTeleport.paranoidPasswordLength {
                                    store.passphraseInput = String(value.prefix(KeyTeleport.paranoidPasswordLength))
                                }
                            }
                    }
                } footer: {
                    Text(store.passphraseCompletionHint)
                }
                Section {
                    PhoneActionButton(title: "ENTER", prominent: true) { store.submitTeleportTextEntry() }
                }
            } else {
                Section {
                    Text("Your BIP-39 Passphrase").foregroundStyle(.secondary)
                    TextField("", text: $store.passphraseInput)
                        .onChange(of: store.passphraseInput) { _, value in
                            let next = BIP39Passphrase.sanitized(value)
                            if next != value { store.passphraseInput = next }
                        }
                } footer: {
                    Text(store.passphraseCompletionHint)
                }
                Section {
                    PhoneActionButton(title: "Apply", prominent: true) { store.applyPassphrasePreview() }
                }
            }
        }
    }
}

private struct PhoneListedFileRenameScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                TextField("", text: $store.passphraseInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: store.passphraseInput) { _, value in
                        store.errorMessage = nil
                        if value.count > 32 {
                            store.passphraseInput = String(value.prefix(32))
                        }
                    }
            } footer: {
                Text(FirmwareCopy.uxInputTextDoneFooter)
            }
            Section {
                PhoneActionButton(title: "Save", prominent: true) { store.saveListedFileRename() }
            }
        }
    }
}

private struct PhonePassphraseConfirmScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            Section {
                Text(store.passphraseConfirmBody)
            }
            Section {
                PhoneActionButton(title: "Use this wallet", prominent: true) { store.confirmPassphrase(save: false) }
                PhoneActionButton(title: "Apply and save (1)") { store.confirmPassphrase(save: true) }
                PhoneActionButton(title: "Abort") { store.back() }
            }
        }
    }
}

private struct PhoneAddressListScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            if store.customSingleAddress {
                Section {
                    Text("Showing single address.").foregroundStyle(.secondary)
                    Text("Press (0) to sign message with this key.").foregroundStyle(.secondary)
                    PhoneActionButton(title: "Sign message (0)") { store.startMessageSigningFromAddress() }
                }
            } else if !store.addressChange, store.addressAllowChange {
                Section {
                    PhoneActionButton(title: "Show change addresses (0)") { store.toggleChangeAddresses() }
                }
            }
            Section {
                ForEach(store.derivedAddresses, id: \.id) { address in
                    Button { store.selectAddress(address) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(address.path) =>")
                                .font(.footnote.monospaced()).foregroundStyle(.primary)
                            Text(address.address).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                if !store.customSingleAddress {
                    PhoneActionButton(title: "Previous (LEFT)") { store.pageAddresses(by: -10) }
                    PhoneActionButton(title: "Next (RIGHT)") { store.pageAddresses(by: 10) }
                    PhoneActionButton(title: "HOME (index 0)") { store.resetAddressExplorerHome() }
                    PhoneActionButton(title: "Save to SD / Files (1)") { store.exportAddressCSV(destination: .sdCard) }
                    PhoneActionButton(title: "Lower slot (B)") { store.exportAddressCSV(destination: .lowerSlot) }
                    if store.preferences.virtualDiskMode != 0 {
                        PhoneActionButton(title: "Virtual Disk (2)") { store.exportAddressCSV(destination: .virtDisk) }
                    }
                    if store.preferences.nfcSharingEnabled {
                        PhoneActionButton(title: "NFC") { store.shareAddressListNFC() }
                    }
                    if store.addressQRAllowed {
                        PhoneActionButton(title: "QR") { store.showAddressListQR() }
                    }
                }
            } header: {
                Text(store.customSingleAddress
                     ? AddressExplorer.header(start: store.addressPageStart, count: nil)
                     : AddressExplorer.header(start: store.addressPageStart, count: AddressExplorer.pageSize))
            } footer: {
                if !store.customSingleAddress {
                    if store.addressPageStart == store.addressStartIndex {
                        Text(store.addressExportPrompt + " Press RIGHT to see next group, LEFT to go back. X to quit.")
                    } else {
                        Text("Press RIGHT to see next group, LEFT to go back. X to quit.")
                    }
                }
            }
        }
        .onChange(of: store.addressChange) { _, _ in store.loadAddresses() }
    }
}

private struct PhoneAddressDetailScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        if let address = store.selectedAddress {
            List {
                Section("Derivation") { Text(address.path).font(.callout.monospaced()).foregroundStyle(coldcardGold) }
                Section("Address") { Text(SimulatorStore.chunkAddress(address.address)).font(.callout.monospaced()).textSelection(.enabled) }
                Section {
                    PhoneActionButton(title: "Copy") { UIPasteboard.general.string = address.address }
                    PhoneActionButton(title: "Show QR", prominent: true) { store.showSelectedAddressQR() }
                    PhoneActionButton(title: "Sign message (0)") { store.startMessageSigningFromAddress() }
                }
            }
        }
    }
}

private struct PhoneAccountNumberScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section { TextField("0", text: $store.accountPromptValue).keyboardType(.numberPad) }
            Section { PhoneActionButton(title: "ENTER", prominent: true) { store.submitAccountNumber() } }
        }
    }
}

private struct PhonePSBTScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        if store.psbtReview != nil {
            List {
                Section {
                    Text(LCDDisplay.storyPlaintext(store.psbtApprovalBody))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                Section {
                    PhoneActionButton(title: "ENTER", prominent: true) { store.signCurrentPSBT() }
                    PhoneActionButton(title: "(2) explore") { store.openMenu(.psbtExplorer) }
                    if store.psbtInputMethod == "sd" {
                        PhoneActionButton(title: "(B) lower SD slot") { store.signCurrentPSBT(writeToLowerSlot: true) }
                    }
                    PhoneActionButton(title: "CANCEL", role: .destructive) { store.refusePSBT() }
                }
            }
        } else {
            List {
                if !store.screenTitle.isEmpty {
                    Section { Text(store.screenTitle).font(.headline.monospaced()) }
                }
                Section { Text(store.psbtEmptyStory).foregroundStyle(.secondary) }
                Section {
                    PhoneActionButton(title: "Import from Files (B)", prominent: true) { store.requestPSBTImport() }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "Import from Virtual Disk (2)") { store.importPSBTFromVirtualDisk() }
                    }
                    if store.preferences.nfcSharingEnabled {
                        PhoneActionButton(title: "Import via NFC") { store.requestPSBTNFCImport() }
                    }
                    PhoneActionButton(title: "Scan QR") { store.handleQRKey() }
                }
            }
        }
    }
}

private struct PhoneNFCReceiveScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            Section {
                Text(ReadyToSign.nfcReceivePrompt)
                    .font(.callout.monospaced())
            }
            if store.nfcReceiveNeedsStandIn {
                Section {
                    PhoneActionButton(title: "Paste PSBT", prominent: true) {
                        store.nfcStandInKind = .psbt
                        store.showNFCStandIn = true
                    }
                    PhoneActionButton(title: "Import file") { store.consumeNFCReceiveStandInFile() }
                } footer: {
                    Text("Core NFC is unavailable here. Files and paste are the iOS stand-in, not a platformLimit stub. Tag emulation remains out of scope.")
                }
            }
            Section {
                PhoneActionButton(title: "CANCEL", role: .destructive) { store.back() }
            }
        }
    }
}

private struct PhoneSignedPSBTScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            Section {
                Text(store.signedTransactionStory)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            Section {
                PhoneActionButton(title: "PRESS 1 — SD / Files", prominent: true) { store.typeCharacter("1") }
                PhoneActionButton(title: "PRESS B — lower slot") { store.typeCharacter("b") }
                if store.virtualDiskEnabled {
                    PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                }
                if store.preferences.nfcSharingEnabled {
                    PhoneActionButton(title: "NFC") { store.shareSignedResultNFC() }
                }
                PhoneActionButton(title: "QR") { store.showPSBTQR() }
                if store.postSignTxid != nil {
                    PhoneActionButton(title: "PRESS 6 — QR of TXID") { store.typeCharacter("6") }
                }
                if store.canTeleportSignedPSBT {
                    PhoneActionButton(title: "PRESS T — Key Teleport") { store.typeCharacter("t") }
                }
                PhoneActionButton(title: "CANCEL", role: .destructive) { store.back() }
            }
        }
    }
}

private struct PhoneWalletExportScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            if let helper = walletExportHelperText(for: store) {
                Section {
                    Text(helper).foregroundStyle(.secondary)
                }
            }
            Section(store.walletExportTitle) {
                Text(store.walletExportText).font(.caption.monospaced()).textSelection(.enabled)
            }
            Section {
                PhoneActionButton(title: "Copy") { UIPasteboard.general.string = store.walletExportText }
                if store.isXPUBOnlyExport {
                    PhoneActionButton(title: "File (simulator)") { store.exportCurrentWalletText() }
                    PhoneActionButton(title: "QR", prominent: true) { store.showCurrentWalletExportQR() }
                } else {
                    PhoneActionButton(title: "File", prominent: true) { store.exportCurrentWalletText() }
                    PhoneActionButton(title: "QR") { store.showCurrentWalletExportQR() }
                }
            } footer: {
                if store.isXPUBOnlyExport {
                    Text("Firmware Export XPUB is QR/NFC only. File save is simulator-only.")
                }
            }
        }
    }
}

private struct PhoneMessageSigningScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                TextField("Enter MSG", text: $store.messageText, axis: .vertical)
                    .font(.body.monospaced())
                    .onChange(of: store.messageText) { _, _ in
                        store.clampMessageText()
                    }
                if store.messagePathLocked {
                    Text(SimulatorStore.hardNotation(store.messagePath)).font(.caption.monospaced()).foregroundStyle(.secondary)
                } else {
                    Text("ENTER signs after address format, account, Change?, and index prompts.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Message")
            }
            Section { PhoneActionButton(title: "ENTER", prominent: true) { store.signMessage() } }
        }
    }
}

private struct PhoneNoteEditorScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                if store.noteEditorMode == .changePassword {
                    Text("\"\(store.noteTitle)\"").foregroundStyle(.secondary)
                    passwordFields
                } else {
                    Text("Title").font(.caption).foregroundStyle(.secondary)
                    TextField("(required for menu)", text: $store.noteTitle)
                        .onChange(of: store.noteTitle) { _, value in
                            if value.count > SecureNotesSupport.oneLineLimit {
                                store.noteTitle = String(value.prefix(SecureNotesSupport.oneLineLimit))
                            }
                        }
                    if store.noteEditorMode == .createPassword || store.noteEditorMode == .editPasswordMetadata {
                        Text("Username").font(.caption).foregroundStyle(.secondary)
                        TextField("(optional)", text: $store.noteUsername)
                            .onChange(of: store.noteUsername) { _, value in
                                if value.count > SecureNotesSupport.oneLineLimit {
                                    store.noteUsername = String(value.prefix(SecureNotesSupport.oneLineLimit))
                                }
                            }
                        if store.noteEditorMode == .createPassword {
                            passwordFields
                        }
                        Text("Website").font(.caption).foregroundStyle(.secondary)
                        TextField("(optional)", text: $store.noteSite)
                            .onChange(of: store.noteSite) { _, value in
                                if value.count > SecureNotesSupport.oneLineLimit {
                                    store.noteSite = String(value.prefix(SecureNotesSupport.oneLineLimit))
                                }
                            }
                        Text("More Notes").font(.caption).foregroundStyle(.secondary)
                        TextField("(optional)", text: $store.noteBody, axis: .vertical)
                    } else {
                        Text("Your Notes").font(.caption).foregroundStyle(.secondary)
                        TextField("(freeform text)", text: $store.noteBody, axis: .vertical)
                    }
                }
            }
            Section { PhoneActionButton(title: "Save", prominent: true) { store.addSecureNote() } }
        }
    }

    @ViewBuilder private var passwordFields: some View {
        Text("Password").font(.caption).foregroundStyle(.secondary)
        SecureField("(optional)", text: $store.notePassword)
            .onChange(of: store.notePassword) { _, value in
                if value.count > SecureNotesSupport.passwordLimit {
                    store.notePassword = String(value.prefix(SecureNotesSupport.passwordLimit))
                }
            }
        Text(SecureNotes.passwordFunctionKeyLegend).font(.caption).foregroundStyle(.secondary)
        passwordGenerators
    }

    @ViewBuilder private var passwordGenerators: some View {
        HStack {
            Button("F1") { store.generateNotePassword(1) }
            Button("F2") { store.generateNotePassword(2) }
            Button("F3") { store.generateNotePassword(3) }
            Button("F4") { store.generateNotePassword(4) }
            Button("F5") { store.generateNotePassword(5) }
            Button("F6") { store.generateNotePassword(6) }
        }
        .buttonStyle(.bordered)
        .font(.caption.monospaced())
    }
}

private struct PhoneBackupPasswordScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            Section {
                Text(SeedXOR.renderPartWords(store.backupPasswordWords))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text(BackupFile.recordPasswordPrompt)
            } footer: {
                Text(FirmwareCopy.seedWordsFooter)
            }
            Section { PhoneActionButton(title: "Continue — quiz", prominent: true) { store.continueBackupPassword() } }
            if store.pendingNotesFileExport {
                Section {
                    PhoneActionButton(title: "Cleartext (6)") { store.typeCharacter("6") }
                } footer: {
                    Text(BackupFile.cleartextKeyHint)
                }
            }
        }
    }
}

private struct PhoneHexEntryScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                Text(FirmwareCopy.tapsignerKeyPrompt).foregroundStyle(.secondary)
                TextField("", text: $store.hexEntryText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .onChange(of: store.hexEntryText) { _, value in
                        store.hexEntryText = SimulatorStore.normalizedHexEntry(value)
                    }
            } footer: {
                Text("\(store.hexEntryText.count)/32")
            }
            Section {
                PhoneActionButton(title: "Continue", prominent: true, disabled: store.hexEntryText.count != 32) {
                    store.confirmHexEntry()
                }
            }
        }
    }
}

private struct PhoneVerifyBackupScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                Text(store.pendingEncryptedNotesData != nil
                     ? "Enter the 12-word backup password to decrypt notes."
                     : "Enter the 12-word backup password, then pick the backup file.")
                    .foregroundStyle(.secondary)
                TextField("Backup password words", text: $store.backupPassword)
            }
            if store.pendingEncryptedNotesData != nil {
                Section { PhoneActionButton(title: "Decrypt notes", prominent: true) { store.decryptAndImportNotes() } }
            } else {
                Section { PhoneActionButton(title: "Choose file", prominent: true) {
                    if store.importPurpose == .backup { store.showFileImporter = true }
                    else { store.requestVerifyBackup() }
                } }
            }
        }
    }
}

private struct PhoneCalculatorScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                ForEach(Array(store.calculatorLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(line.hasPrefix(">> ") ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                }
            }
            Section {
                HStack(spacing: 4) {
                    Text(">>").font(.body.monospaced()).foregroundStyle(coldcardGold)
                    TextField("", text: $store.calculatorExpression)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onChange(of: store.calculatorExpression) { _, value in
                            if value.count > CalculatorLogin.maxInputLength {
                                store.calculatorExpression = String(value.prefix(CalculatorLogin.maxInputLength))
                            }
                        }
                        .onSubmit { store.evaluateCalculator() }
                }
            }
            Section { PhoneActionButton(title: "ENTER", prominent: true) { store.evaluateCalculator() } }
        }
    }
}

private struct PhoneSerialREPLScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section {
                Toggle("VCP enabled", isOn: $store.serialREPLVCPEnabled)
                Text(store.serialREPL.statusLine).foregroundStyle(.secondary)
            } footer: {
                Text("3.3v TTL on Tx/Rx/Gnd pads @ 115,200 bps. In-app stand-in for the serial MicroPython REPL.")
            }
            Section {
                ForEach(Array(store.serialREPL.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(line.hasPrefix(">>> ") ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                }
            }
            Section {
                HStack(spacing: 4) {
                    Text(">>>").font(.body.monospaced()).foregroundStyle(coldcardGold)
                    TextField("", text: $store.serialREPLInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onSubmit { store.submitSerialREPL() }
                }
            }
            Section { PhoneActionButton(title: "ENTER", prominent: true) { store.submitSerialREPL() } }
        }
    }
}

@ViewBuilder
private func phoneSelftestFill(_ fill: SelftestFill) -> some View {
    switch fill {
    case .red: Color.red
    case .green: Color.green
    case .blue: Color.blue
    case .gpu:
        HStack(spacing: 0) {
            Color.red
            Color.green
            Color.blue
        }
    }
}

@ViewBuilder
private func phoneSelftestLED(_ led: QSelftest.LED) -> some View {
    let spec: (Color, String)? = {
        switch led {
        case .off: nil
        case .genuineGreen: (Color.green, "Genuine green")
        case .genuineRed: (Color.red, "Genuine red")
        case .nfc: (Color.green, "NFC light")
        case .usb: (Color.green, "USB light")
        case .sdA(let on): on ? (Color.green, "SD A on") : nil
        case .sdB(let on): on ? (Color.green, "SD B on") : nil
        }
    }()
    if let spec {
        HStack(spacing: 8) {
            Circle()
                .fill(spec.0)
                .frame(width: 14, height: 14)
            Text(spec.1)
                .font(.caption.monospaced())
        }
        .accessibilityLabel(spec.1)
    }
}

private struct PhoneStoryScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let fill = store.selftestFill {
                    phoneSelftestFill(fill)
                        .frame(height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if store.selftestLED != .off {
                    phoneSelftestLED(store.selftestLED)
                }
                if !store.story.title.isEmpty || store.story.hintQR || store.story.hintNFC {
                    HStack(alignment: .firstTextBaseline) {
                        if !store.story.title.isEmpty {
                            Text(store.story.title).font(.headline.monospaced())
                        }
                        Spacer(minLength: 8)
                        if store.story.hintQR {
                            Image(systemName: "qrcode").accessibilityLabel("QR")
                        }
                        if store.story.hintNFC {
                            Image(systemName: "wave.3.right").accessibilityLabel("NFC")
                        }
                    }
                }
                Text(store.story.body).textSelection(.enabled)
                if let expected = store.selftestExpectedKey {
                    PhoneActionButton(title: "PRESS \(store.selftestExpectedKeyLabel)", prominent: true) {
                        store.submitSelftestKey(expected)
                    }
                } else if store.selftestAwaitingNFCShare {
                    PhoneActionButton(title: "PRESS NFC", prominent: true) {
                        store.completeSelftestNFCShare()
                    }
                } else if store.selftestAllowsSkip {
                    PhoneActionButton(title: "ENTER", prominent: true) { store.confirmStory() }
                    PhoneActionButton(title: "SKIP (s)") { store.submitSelftestKey("s") }
                } else if store.story.onConfirm != .listedFileDetail,
                          store.story.onConfirm != .signedMessageExport,
                          store.story.onConfirm != .batchSignImport,
                          store.story.onConfirm != .xorSplitParts,
                          store.story.onConfirm != .xorRestoreMore,
                          store.story.onConfirm != .exportNotesFile,
                          store.story.onConfirm != .importNotesSource {
                    Button {
                        if let code = store.story.confirmCode {
                            store.typeCharacter(code)
                        } else {
                            store.confirmStory()
                        }
                    } label: {
                        Text(store.story.confirmCode.map { "PRESS \($0)" } ?? "ENTER").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if store.story.onConfirm == .listedFileDetail {
                    PhoneActionButton(title: "PRESS 1 — rename") { store.typeCharacter("1") }
                    if store.hasSeed || store.tmpSeedActive {
                        PhoneActionButton(title: "PRESS 4 — sign digest") { store.typeCharacter("4") }
                    }
                    PhoneActionButton(title: "PRESS 6 — delete") { store.typeCharacter("6") }
                }
                if store.story.onConfirm == .pasteNFCSeed {
                    PhoneActionButton(title: "PRESS 1 — import file") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .nfcToolsStandIn {
                    PhoneActionButton(title: "PRESS 1 — import file") { store.typeCharacter("1") }
                    PhoneActionButton(title: "Scan QR") { store.beginNFCToolsQRStandIn() }
                }
                if store.story.onConfirm == .nfcShowAddress {
                    PhoneActionButton(title: "Show QR") { store.showNFCShownAddressQR() }
                    if store.preferences.nfcSharingEnabled {
                        PhoneActionButton(title: "Share via NFC") { store.shareNFCShownAddress() }
                    }
                }
                if store.story.onConfirm == .nfcVerifiedAddress {
                    PhoneActionButton(title: "Show QR") { store.showNFCShownAddressQR() }
                    if store.pendingOwnershipCanSign {
                        PhoneActionButton(title: "PRESS 0 — sign message") { store.typeCharacter("0") }
                    }
                }
                if store.story.onConfirm == .enrollImportedMultisig {
                    PhoneActionButton(title: "PRESS 1 — extended public keys") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .importMultisigPrompt {
                    PhoneActionButton(title: "PRESS 1 — SD / Files") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS B — lower slot") { store.typeCharacter("b") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                    }
                    PhoneActionButton(title: "Scan QR") { store.handleQRKey() }
                    if store.preferences.nfcSharingEnabled {
                        PhoneActionButton(title: "NFC") { store.handleHardwareKey(.nfc) }
                    }
                }
                if store.story.onConfirm == .createAirgappedSource {
                    PhoneActionButton(title: "Scan QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .createAirgappedFormat {
                    PhoneActionButton(title: "PRESS 1 — P2SH-P2WSH") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .exportPrettyDescriptor {
                    PhoneActionButton(title: "PRESS 1 — pretty export") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .keyTeleportReusePubkey {
                    PhoneActionButton(title: "PRESS R — new values") { store.typeCharacter("r") }
                    PhoneActionButton(title: "Scan sender QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .keyTeleportPickPSBTFile {
                    PhoneActionButton(title: "PRESS 1 — SD / Files") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS B — lower slot") { store.typeCharacter("b") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                    }
                }
                if store.story.onConfirm == .keyTeleportShowPayload {
                    PhoneActionButton(title: "SHOW QR") { store.showPendingKeyTeleportQR() }
                    if store.story.hintNFC {
                        PhoneActionButton(title: "NFC Files") { store.sharePendingKeyTeleportNFC() }
                    }
                }
                if store.story.onConfirm == .pickPushTxnFromFiles {
                    PhoneActionButton(title: "ENTER — pick .txn file", prominent: true) { store.confirmStory() }
                }
                if store.story.onConfirm == .continueAddressExplorer {
                    PhoneActionButton(title: "PRESS 6") { store.typeCharacter("6") }
                }
                if store.story.onConfirm == .continueExport, store.pendingExport?.asksAccount == true {
                    PhoneActionButton(title: "PRESS 1") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .openKeyExpressionMenu {
                    PhoneActionButton(title: "PRESS 1") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .descriptorIntExt {
                    PhoneActionButton(title: "PRESS 1") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .messageChange || store.story.onConfirm == .signedMessageQR
                    || store.story.onConfirm == .simpleTextQR {
                    PhoneActionButton(title: "PRESS 0") { store.typeCharacter("0") }
                }
                if store.story.onConfirm == .signedMessageExport {
                    PhoneActionButton(title: "PRESS 1 — SD / Files") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS B — lower slot") { store.typeCharacter("b") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                    }
                    if store.preferences.nfcSharingEnabled {
                        PhoneActionButton(title: "NFC") { store.shareSignedMessageNFC() }
                    }
                    PhoneActionButton(title: "QR") { store.showSignedMessageQR() }
                }
                if store.story.onConfirm == .skipBackupCache {
                    PhoneActionButton(title: "PRESS 1") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .backupFirstCopyWritten || store.story.onConfirm == .backupMoreCopies {
                    PhoneActionButton(title: "PRESS 2 — another copy") { store.typeCharacter("2") }
                }
                if store.story.onConfirm == .notesCustomPassword {
                    PhoneActionButton(title: "PRESS 1 — custom password") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .continuePassphrase {
                    PhoneActionButton(title: "PRESS 2") { store.typeCharacter("2") }
                }
                if store.story.onConfirm == .skipVaultSave {
                    PhoneActionButton(title: "PRESS 1") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .deleteVaultSeedConfirm, !store.pendingVaultDeleteIsActive {
                    PhoneActionButton(title: "PRESS 1 — keep settings") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .exportNotesFile {
                    PhoneActionButton(title: "PRESS 1 — SD / Files") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS B — lower slot") { store.typeCharacter("b") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                    }
                    PhoneActionButton(title: "QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .importNotesSource {
                    PhoneActionButton(title: "PRESS 1 — SD / Files") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS B — lower slot") { store.typeCharacter("b") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                    }
                    PhoneActionButton(title: "QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .notesCustomPWD {
                    PhoneActionButton(title: "PRESS 1 — custom string") { store.typeCharacter("1") }
                    PhoneActionButton(title: "ENTER — 12 word password", prominent: true) { store.confirmStory() }
                }
                if store.story.onConfirm == .wifImportPrompt || store.story.onConfirm == .wifSignImport {
                    PhoneActionButton(title: "PRESS 0 — type") { store.typeCharacter("0") }
                    PhoneActionButton(title: "PRESS 1 — Files / SD") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS B — lower slot") { store.typeCharacter("b") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                    }
                    if store.preferences.nfcSharingEnabled {
                        PhoneActionButton(title: "NFC") { store.handleHardwareKey(.nfc) }
                    }
                    PhoneActionButton(title: "QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .importVisualizedWIF {
                    PhoneActionButton(title: "PRESS 1 — import to WIF Store") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .showXPUBQR {
                    if store.pendingExport != .xpubMaster {
                        PhoneActionButton(title: "PRESS 1") { store.typeCharacter("1") }
                        if store.pendingExport == .xpubSegwit || store.pendingExport == .xpubWrapped {
                            PhoneActionButton(title: "PRESS 2") { store.typeCharacter("2") }
                        }
                    }
                    if store.preferences.nfcSharingEnabled {
                        PhoneActionButton(title: "PRESS NFC") { store.shareXPUBNFC() }
                    }
                }
                if store.story.onConfirm == .batchSignImport {
                    PhoneActionButton(title: "PRESS 1 — SD / Files") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS B — lower slot") { store.typeCharacter("b") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                    }
                }
                if store.story.onConfirm == .batchSignConfirm {
                    PhoneActionButton(title: "PRESS (1) — skip this PSBT") { store.typeCharacter("1") }
                    PhoneActionButton(title: "CANCEL") { store.back() }
                }
                if store.story.onConfirm == .tapsignerImportSource {
                    PhoneActionButton(title: "PRESS 1 — Files") { store.typeCharacter("1") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                    }
                    if store.preferences.nfcSharingEnabled {
                        PhoneActionButton(title: "PRESS NFC") { store.handleHardwareKey(.nfc) }
                    }
                    PhoneActionButton(title: "Scan QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .importXPRVSource {
                    PhoneActionButton(title: "PRESS 1 — Files / SD") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS B — lower slot") { store.typeCharacter("b") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — Virtual Disk") { store.typeCharacter("2") }
                    }
                    if store.preferences.nfcSharingEnabled {
                        PhoneActionButton(title: "NFC") { store.handleHardwareKey(.nfc) }
                    }
                    PhoneActionButton(title: "QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .restoreMasterConfirm {
                    PhoneActionButton(title: "PRESS 1 — save & keep") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .xorSplitParts {
                    PhoneActionButton(title: "PRESS 2") { store.typeCharacter("2") }
                    PhoneActionButton(title: "PRESS 3") { store.typeCharacter("3") }
                    PhoneActionButton(title: "PRESS 4") { store.typeCharacter("4") }
                }
                if store.story.onConfirm == .xorSplitRNG {
                    PhoneActionButton(title: "PRESS 2 — TRNG") { store.typeCharacter("2") }
                }
                if store.story.onConfirm == .xorShowParts {
                    PhoneActionButton(title: "PRESS 4 — SeedQR") { store.typeCharacter("4") }
                    PhoneActionButton(title: "SHOW QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .xorRestoreWordCount {
                    PhoneActionButton(title: "PRESS 1 — 12 words") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS 2 — 18 words") { store.typeCharacter("2") }
                }
                if store.story.onConfirm == .xorRestoreInclude, store.xorCanIncludeCurrent {
                    PhoneActionButton(title: "PRESS 1 — include current seed") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .xorRestoreVault {
                    PhoneActionButton(title: "PRESS 2 — Seed Vault") { store.typeCharacter("2") }
                }
                if store.story.onConfirm == .xorRestoreMore {
                    PhoneActionButton(title: "PRESS 1 — next part") { store.typeCharacter("1") }
                    if store.xorEntropyParts.count >= 2 {
                        PhoneActionButton(title: "PRESS 2 — done") { store.typeCharacter("2") }
                        PhoneActionButton(title: "SHOW QR") { store.handleQRKey() }
                    }
                }
                if store.story.onConfirm == .bip85Reveal {
                    PhoneActionButton(title: "PRESS 1 — save") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS 0 — apply as tmp") { store.typeCharacter("0") }
                    PhoneActionButton(title: "SHOW QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .paperWalletSave {
                    PhoneActionButton(title: "PRESS 1 — MicroSD") { store.typeCharacter("1") }
                    if store.virtualDiskEnabled {
                        PhoneActionButton(title: "PRESS 2 — VirtDisk") { store.typeCharacter("2") }
                    }
                }
                if store.story.onConfirm == .paperWalletDone {
                    PhoneActionButton(title: "SHOW QR") { store.handleQRKey() }
                }
                if store.story.onConfirm == .bkpwOverride {
                    PhoneActionButton(title: "PRESS 0 — change") { store.typeCharacter("0") }
                    if store.storedBackupPassword != nil {
                        PhoneActionButton(title: "PRESS 1 — forget") { store.typeCharacter("1") }
                        PhoneActionButton(title: "PRESS 2 — show") { store.typeCharacter("2") }
                    }
                }
                if store.story.onConfirm == .cccGenerateKeyC {
                    PhoneActionButton(title: "PRESS 1 — import 12 words") { store.typeCharacter("1") }
                    PhoneActionButton(title: "PRESS 2 — import 24 words") { store.typeCharacter("2") }
                    if store.preferences.seedVaultEnabled, !store.preferences.vaultedSeeds.isEmpty {
                        PhoneActionButton(title: "PRESS 6 — Seed Vault") { store.typeCharacter("6") }
                    }
                }
                if store.story.body.contains("Press (4) to clear") || store.story.body.contains("Press (4) to delete") {
                    PhoneActionButton(title: "PRESS 4") { store.typeCharacter("4") }
                }
                if store.story.body.contains("Press (1) to clear block height") {
                    PhoneActionButton(title: "PRESS 1 — reset height") { store.typeCharacter("1") }
                }
                if store.story.onConfirm == .enableWeb2FA || store.pendingWeb2FA != nil {
                    PhoneActionButton(title: "SHOW QR") { store.handleQRKey() }
                }
            }
            .padding()
        }
    }
}

private struct PhoneViewIdentityScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScrollView {
            Text(store.identityText)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            if store.rootKey != nil {
                PhoneActionButton(title: "Show QR") { store.showIdentityQR() }
                    .padding(.horizontal)
            }
            PhoneActionButton(title: "ENTER", prominent: true) { store.back() }
                .padding(.horizontal)
        }
    }
}

private struct PhoneBrickScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(LoginUX.brickStory(numFails: max(store.failedPINAttempts, 1)))
                PhoneActionButton(title: "ENTER", prominent: true) { store.openBrickedCalculator() }
            }
            .padding()
        }
    }
}

private struct PhonePoweredOffScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            PhoneActionButton(title: "Power", prominent: true) { store.goToLockedRoot() }
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }
}

private struct PhoneFactoryBaggedScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(store.displayedBagNumber ?? FirmwareCopy.unbaggedTitle)
                .font(.title.monospaced().weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(.black)
                .background(Color(white: 0.88))
            Text(FirmwareCopy.putIntoBagAndSeal)
                .font(.body.monospaced())
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            PhoneActionButton(title: "Power", prominent: true) {
                store.finishFactoryLockupReboot()
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

private struct PhoneFactoryDFUScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(FirmwareCopy.enterBootloaderDFU)
                .font(.title3.monospaced())
                .multilineTextAlignment(.center)
            Spacer()
            PhoneActionButton(title: "Power", prominent: true) {
                store.finishFactoryLockupReboot()
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

private struct PhoneWordEntryScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            Section {
                ForEach(Array(store.wordEntryWords.enumerated()), id: \.offset) { index, word in
                    let current = index == store.wordEntryFilledCount
                    HStack {
                        Text(SeedCreation.drawCell(index: index, word: current ? store.wordEntryPrefix : word, count: store.wordEntryWords.count))
                            .font(.body.monospaced())
                            .foregroundStyle(current ? coldcardGold : .primary)
                        if current, store.wordEntryCursor.style == .outline {
                            Text("[]")
                                .font(.body.monospaced())
                                .foregroundStyle(coldcardGold)
                                .accessibilityLabel("Outline cursor on eighth letter")
                        }
                    }
                }
            }
            Section {
                TextField("Type letters", text: $store.wordEntryPrefix)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: store.wordEntryPrefix) { _, value in
                        store.setWordEntryPrefixFromField(value)
                    }
                if !store.wordEntryHint.isEmpty {
                    Text(store.wordEntryHint).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                PhoneActionButton(title: "ENTER") { store.commitWordEntry() }
                PhoneActionButton(title: "Clear") { store.clearCurrentField() }
            } footer: {
                Text(store.scannerPrompt)
            }
        }
    }
}

private struct PhoneEntropyCollectScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            if store.entropyKind == .mash {
                Section {
                    LabeledContent("Progress", value: store.entropyCollectLine2)
                    Text(store.entropyCollectLine3).font(.footnote).foregroundStyle(.secondary)
                    PhoneActionButton(title: "Mash") { store.mashKey("x") }
                    PhoneActionButton(title: "Done", prominent: true, disabled: store.mashCount < 65) { store.finishMashIfReady() }
                }
            } else if store.entropyKind == .diceMix {
                Section {
                    LabeledContent("Progress", value: store.entropyCollectLine2)
                    Text(store.diceRolls.isEmpty ? " " : store.diceRolls).font(.body.monospaced())
                } footer: {
                    Text(store.entropyCollectLine3)
                }
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                        ForEach(["1", "2", "3", "4", "5", "6"], id: \.self) { digit in
                            Button(digit) { store.addDiceRoll(Character(digit)) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                Section { PhoneActionButton(title: "Done", prominent: true) { store.finishDiceRolls() } }
            } else {
                Section {
                    LabeledContent("Progress", value: store.entropyCollectLine2)
                    Text(store.entropyCollectLine3).font(.footnote).foregroundStyle(.secondary)
                    PhoneActionButton(title: "0 Tails") { store.addCoinFlip("0") }
                    PhoneActionButton(title: "1 Heads") { store.addCoinFlip("1") }
                    PhoneActionButton(title: "Done", prominent: true, disabled: store.coinFlips.count < 128) { store.finishCoinIfReady() }
                }
            }
        }
    }
}

private struct PhonePSBTExplorerScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            Section {
                Text(store.psbtExplorerBody).font(.footnote.monospaced())
            }
            Section {
                PhoneActionButton(title: "Previous") { store.pagePSBTExplorer(by: -1) }
                PhoneActionButton(title: "Next") { store.pagePSBTExplorer(by: 1) }
                if store.psbtExplorerMax > 1 {
                    PhoneActionButton(title: "Go to index") { store.promptPSBTExploreIndex() }
                }
                PhoneActionButton(title: "Show QR", prominent: true) { store.handleQRKey() }
            }
        }
    }
}

private struct SeedWordList: View {
    let words: [String]
    var body: some View {
        let columns = SeedCreation.columnCount(wordCount: words.count)
        let rows = SeedCreation.rows(wordCount: words.count)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = SeedCreation.gridIndex(row: row, column: col, wordCount: words.count)
                        if words.indices.contains(index) {
                            Text(SeedCreation.drawCell(index: index, word: words[index], count: words.count))
                                .font(.callout.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

private struct PhoneLoginCountdownScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        VStack(spacing: 16) {
            Text(LoginUX.countdownTitle)
                .font(.title3.monospaced())
            Text(store.loginCountdownMustWait)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(store.loginCountdownDelayText)
                .font(.title.monospaced().bold())
                .foregroundStyle(coldcardGold)
            PhoneLoginKeyCapture { store.typeCharacter($0) }
        }
        .padding()
    }
}

private struct PhoneTypePasswordIndexScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        Form {
            Section { TextField("0", text: $store.typePasswordIndexText).keyboardType(.numberPad) }
            Section { PhoneActionButton(title: "ENTER", prominent: true) { store.submitTypePasswordIndex() } }
        }
    }
}

private struct PhoneTypePasswordConfirmScreen: View {
    @Bindable var store: SimulatorStore
    var body: some View {
        List {
            Section {
                Text(store.typePasswordConfirmBody)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            Section {
                PhoneActionButton(title: "ENTER", prominent: true) { store.confirmTypePasswordSend() }
            }
        }
    }
}

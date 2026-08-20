import Foundation
import ColdcardCore

extension SimulatorStore {
    var trickTable: TrickPinTable { TrickPinTable(slots: record?.trickPins ?? []) }

    var pinSetupTrickSubtitle: String? {
        (pinSetupPurpose == .trickNew || pinSetupPurpose == .trickChange) ? "New Trick PIN" : nil
    }

    func resetTrickSessionOnLock() {
        deltaModeActive = false
        blankWalletSession = false
        trickBrickAfterCountdown = false
        loginCountdownOverrideMinutes = nil
        sessionPIN = ""
        awaitingPostCountdownPIN = awaitingPostCountdownPIN && loginCountdownRemaining > 0
    }

    func commitTrickTable(_ table: TrickPinTable) {
        guard var record else { return }
        record.trickPins = table.slots
        commitWalletRecord(record)
    }

    func performTrickCommand(_ command: SimulatorCommand) -> Bool {
        switch command {
        case .trickAddNew: beginAddNewTrick()
        case .trickAddIfWrong: beginAddIfWrong()
        case .trickDeleteAll: confirmDeleteAllTricks()
        case .openTrickPIN(let pin):
            selectedTrickPIN = pin
            openMenu(.trickPINDetail)
        case .trickHide: confirmHideTrick()
        case .trickDelete: confirmDeleteTrick()
        case .trickChangePIN: beginChangeTrickPIN()
        case .trickActivateWallet: confirmActivateTrickWallet()
        case .trickDuressDetails: presentDuressDetails()
        case .trickCountdownDetails: presentCountdownDetails()
        case .trickPickAction(let label, let flags, let arg):
            pickTrickAction(label: label, flags: TrickPinFlags(rawValue: flags), arg: arg)
        case .trickOpenWipeMenu: presentWipeMenu()
        case .trickOpenDuressMenu(let afterWipe): presentDuressMenu(afterWipe: afterWipe)
        case .trickOpenCountdownMenu: presentCountdownMenu()
        case .setTrickCountdown(let minutes): saveTrickCountdownPeriod(minutes)
        default:
            return false
        }
        return true
    }

    func confirmTrickStory(_ action: StoryConfirmAction) -> Bool {
        switch action {
        case .trickSaveProposed:
            back()
            saveProposedTrick()
        case .trickOpenWipeMenu:
            back()
            openMenu(.trickWipeChoices)
        case .trickOpenDuressMenu:
            back()
            trickWipeThenWallet = false
            openMenu(.trickDuressChoices)
        case .trickOpenDuressAfterWipe:
            back()
            trickWipeThenWallet = true
            openMenu(.trickDuressChoices)
        case .trickOpenCountdownMenu:
            back()
            openMenu(.trickCountdownChoices)
        case .trickContinueAddIfWrong:
            back()
            accountPromptPurpose = .trickWrongCount
            accountPromptValue = "1"
            navigate(to: .accountNumber)
        case .trickConfirmDeleteAllPolicy:
            continueDeleteAllAfterPolicy()
        case .trickConfirmDeleteAllDuress:
            finishDeleteAllTricks()
        case .trickConfirmDeleteAll:
            continueDeleteAllAfterIntro()
        case .trickConfirmDelete:
            back()
            deleteSelectedTrick()
        case .trickConfirmHide:
            back()
            hideSelectedTrick()
        case .trickConfirmActivate:
            back()
            activateSelectedTrickWallet()
        case .trickDuressDetails, .trickCountdownDetails, .trickDismiss:
            back()
        default:
            return false
        }
        return true
    }

    func handleTrickStoryKey(_ value: String) -> Bool {
        if story.onConfirm == .trickCountdownDetails, value == "4" {
            openMenu(.trickCountdownPeriod)
            return true
        }
        if story.onConfirm == .trickDuressDetails, value == "6" {
            presentDuressSecrets()
            return true
        }
        return false
    }

    func submitTrickWrongCount(_ value: UInt32) {
        var count = Int(value)
        if count == 0 { count = 1 }
        count = min(max(count, 1), 12)
        proposedTrickWrongCount = count
        proposedTrickPIN = TrickPins.wrongPINCode
        back()
        openMenu(.trickWrongActions)
    }

    func finishProposedTrickPIN(_ pin: String) {
        guard isValidPIN(pin) else {
            errorMessage = SimulatorInputError.invalidPIN.localizedDescription
            return
        }
        if pin == selectedTrickPIN {
            showStory(title: "", body: FirmwareCopy.trickNotANewValue)
            return
        }
        if pin == sessionPIN || trickTable.uniquePINConflict(pin, currentPIN: sessionPIN, excluding: nil) {
            showStory(title: "", body: FirmwareCopy.trickPINInUse(pin))
            return
        }
        if trickTable.forgottenPIN(matching: pin) {
            var table = trickTable
            _ = table.restore(pin: pin)
            commitTrickTable(table)
            pinSetupPurpose = .wallet
            popToTrickPINList()
            showStory(title: "", body: FirmwareCopy.trickRememberedPIN)
            return
        }
        proposedTrickPIN = pin
        pinSetupPurpose = .wallet
        popToTrickPINList()
        openMenu(.trickNewActions)
    }

    func finishChangeTrickPIN(_ pin: String) {
        guard isValidPIN(pin), let old = selectedTrickPIN else {
            errorMessage = SimulatorInputError.invalidPIN.localizedDescription
            return
        }
        if pin == old {
            showStory(title: "", body: FirmwareCopy.trickNotANewValue)
            return
        }
        if pin == sessionPIN || trickTable.uniquePINConflict(pin, currentPIN: sessionPIN, excluding: old) {
            showStory(title: "", body: FirmwareCopy.trickPINInUse(pin))
            return
        }
        var table = trickTable
        var arg: UInt16?
        if table.slot(forPIN: old)?.isDelta == true {
            let (problem, encoded) = TrickPins.validateDeltaPIN(truePIN: sessionPIN, proposed: pin)
            if let problem {
                showStory(title: "Sorry!", body: problem)
                return
            }
            arg = encoded
        }
        do {
            try table.changePIN(from: old, to: pin, arg: arg)
            commitTrickTable(table)
            pinSetupPurpose = .wallet
            selectedTrickPIN = pin
            popToTrickPINList()
            statusMessage = FirmwareCopy.trickChanged
        } catch {
            showStory(title: "", body: "Failed: \(error.localizedDescription)")
        }
    }

    /// Returns true when the entered PIN was consumed as a trick (including catch-all after fail).
    func applyNamedTrickLogin(pin: String) -> Bool {
        let decision = trickTable.decision(forPIN: pin)
        if decision == .notATrick { return false }
        sessionPIN = pin
        applyTrickDecision(decision, incrementFailureOnFake: true)
        return true
    }

    func applyWrongPINCatchall() -> Bool {
        let decision = trickTable.wrongPINDecision(failCount: failedPINAttempts)
        if decision == .notATrick { return false }
        applyTrickDecision(decision, incrementFailureOnFake: false)
        return true
    }

    func restorePendingTrickPinsIfNeeded() {
        guard !pendingRestoreTrickPins.isEmpty else { return }
        var table = TrickPinTable()
        table.restoreFromBackup(values: pendingRestoreTrickPins, truePIN: sessionPIN)
        pendingRestoreTrickPins = []
        commitTrickTable(table)
    }

    @discardableResult
    func wipeIfDeltaMode() -> Bool {
        guard deltaModeActive else { return false }
        deltaModeActive = false
        performKillWipe()
        showStory(title: "", body: FirmwareCopy.trickWipedLockup)
        return true
    }

    func presentMainPINTrickConflictIfNeeded(_ pin: String) -> Bool {
        if let problem = trickTable.checkNewMainPIN(pin) {
            pinSetupPhase = .prefix
            pinPrefix = ""
            pinInput = ""
            screen = .pinSetup
            showStory(title: "Try Again", body: problem)
            return true
        }
        return false
    }

    func noteMainPINChanged(_ pin: String) {
        var table = trickTable
        table.mainPINHasChanged(to: pin)
        sessionPIN = pin
        commitTrickTable(table)
    }

    // MARK: - Menu flows

    private func beginAddNewTrick() {
        guard hasPIN, record?.hasSeed == true, !tmpSeedActive else {
            showStory(title: "", body: FirmwareCopy.trickNeedSeedAndPIN)
            return
        }
        selectedTrickPIN = nil
        beginTrickPINCapture(purpose: .trickNew)
    }

    private func beginChangeTrickPIN() {
        beginTrickPINCapture(purpose: .trickChange)
    }

    private func beginTrickPINCapture(purpose: PINSetupPurpose) {
        pinSetupPurpose = purpose
        pinSetupIsChange = false
        pinSetupCollectingOld = false
        pinSetupPhase = .prefix
        pinPrefix = ""
        pinInput = ""
        setupPIN = ""
        confirmPIN = ""
        firstPINValue = ""
        navigate(to: .pinSetup)
    }

    private func beginAddIfWrong() {
        showStory(title: "", body: FirmwareCopy.trickAddIfWrongIntro, onConfirm: .trickContinueAddIfWrong)
    }

    private func presentWipeMenu() {
        showStory(title: "", body: FirmwareCopy.trickWipeSeed, onConfirm: .trickOpenWipeMenu)
    }

    private func presentDuressMenu(afterWipe: Bool) {
        let action: StoryConfirmAction = afterWipe ? .trickOpenDuressAfterWipe : .trickOpenDuressMenu
        let body = afterWipe ? FirmwareCopy.trickWipeToWallet : FirmwareCopy.trickDuressWallet
        showStory(title: "", body: body, onConfirm: action)
    }

    private func presentCountdownMenu() {
        let minutes = TrickPins.defaultCountdownMinutes(loginSetting: preferences.loginCountdownMinutes)
        let label = TrickPins.countdownMenuLabel(minutes).trimmingCharacters(in: .whitespaces)
        showStory(title: "", body: FirmwareCopy.trickLoginCountdown(label), onConfirm: .trickOpenCountdownMenu)
    }

    private func pickTrickAction(label: String, flags: TrickPinFlags, arg: UInt16) {
        pendingTrickLabel = label
        pendingTrickFlags = flags
        pendingTrickArg = arg
        let body = storyBody(for: label, flags: flags)
        showStory(title: "", body: body, onConfirm: .trickSaveProposed)
    }

    private func storyBody(for label: String, flags: TrickPinFlags) -> String {
        switch label {
        case "Brick Self": FirmwareCopy.trickBrickSelf
        case "Look Blank": FirmwareCopy.trickLookBlank
        case "Just Reboot":
            if flags.contains(.wipe) {
                FirmwareCopy.trickWipeReboot
            } else if proposedTrickPIN == TrickPins.wrongPINCode {
                FirmwareCopy.trickWrongJustReboot
            } else {
                FirmwareCopy.trickJustReboot
            }
        case "Delta Mode": FirmwareCopy.trickDeltaMode
        case "Policy Unlock": FirmwareCopy.trickPolicyUnlock
        case "Policy Unlock & Wipe": FirmwareCopy.trickPolicyUnlockWipe
        case "Wipe & Reboot": FirmwareCopy.trickWipeReboot
        case "Silent Wipe": FirmwareCopy.trickSilentWipe
        case "Say Wiped, Stop", "Wipe, Stop": FirmwareCopy.trickSayWipedStop
        case "Wipe & Countdown": FirmwareCopy.trickWipeCountdown
        case "Countdown & Brick": FirmwareCopy.trickCountdownBrick
        case "Just Countdown": FirmwareCopy.trickJustCountdown
        case "Last Chance": FirmwareCopy.trickLastChance
        case "BIP-85 Wallet #1", "BIP-85 Wallet #2", "BIP-85 Wallet #3":
            FirmwareCopy.trickBIP85(masterWordCount)
        case "Legacy Wallet": FirmwareCopy.trickLegacyWallet
        default:
            flags.contains(.wipe) ? FirmwareCopy.trickWipeSeed : label
        }
    }

    private func saveProposedTrick() {
        var flags = pendingTrickFlags
        var arg = pendingTrickArg
        if trickWipeThenWallet { flags.insert(.wipe) }
        let pin = proposedTrickPIN.isEmpty ? TrickPins.wrongPINCode : proposedTrickPIN
        if flags.contains(.deltaMode) {
            let (problem, encoded) = TrickPins.validateDeltaPIN(truePIN: sessionPIN, proposed: pin)
            if let problem {
                showStory(title: "Sorry!", body: problem)
                return
            }
            arg = encoded
        }
        var xdata = Data()
        if flags.contains(.wordWallet) || flags.contains(.xprvWallet) {
            do {
                if let secret = try TrickPins.constructDuressSecret(flags: flags, arg: arg, root: try trickMasterRoot()) {
                    xdata = secret.secret
                }
            } catch {
                showStory(title: "", body: "Failed: \(error.localizedDescription)")
                return
            }
        }
        var table = trickTable
        do {
            try table.add(pin: pin, flags: flags, arg: arg, xdata: xdata)
            commitTrickTable(table)
            trickWipeThenWallet = false
            proposedTrickPIN = ""
            popToTrickPINList()
            statusMessage = FirmwareCopy.trickSaved
        } catch TrickPinError.noSpaceLeft {
            showStory(title: "", body: "Failed: no space left")
        } catch TrickPinError.pinInUse {
            showStory(title: "", body: FirmwareCopy.trickPINInUse(pin))
        } catch {
            showStory(title: "", body: "Failed: \(error.localizedDescription)")
        }
    }

    private func confirmDeleteAllTricks() {
        showStory(title: "Are you SURE ?!?", body: FirmwareCopy.trickDeleteAll, onConfirm: .trickConfirmDeleteAll)
    }

    private func continueDeleteAllAfterIntro() {
        if trickTable.hasSpendingPolicyUnlock {
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.trickDeleteAllPolicy,
                      onConfirm: .trickConfirmDeleteAllPolicy)
            return
        }
        continueDeleteAllAfterPolicy()
    }

    private func continueDeleteAllAfterPolicy() {
        if trickTable.hasDuressWallet {
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.trickDeleteAllDuress,
                      onConfirm: .trickConfirmDeleteAllDuress)
            return
        }
        finishDeleteAllTricks()
    }

    private func finishDeleteAllTricks() {
        var table = trickTable
        table.clearAll()
        commitTrickTable(table)
        popToTrickPINList()
    }

    private func confirmHideTrick() {
        guard let pin = selectedTrickPIN, let slot = trickTable.slot(forPIN: pin) else { return }
        if slot.isDelta {
            showStory(title: "", body: FirmwareCopy.trickHideDelta)
            return
        }
        let body: String
        if slot.isSpendingPolicyUnlock && slot.flags == .firmwareDefined {
            body = FirmwareCopy.trickHidePolicy
        } else if slot.isWrongCatchall {
            body = FirmwareCopy.trickHideWrong
        } else {
            body = FirmwareCopy.trickHidePIN(pin)
        }
        showStory(title: "Are you SURE ?!?", body: body, onConfirm: .trickConfirmHide)
    }

    private func hideSelectedTrick() {
        guard let pin = selectedTrickPIN else { return }
        var table = trickTable
        do {
            try table.hide(pin: pin)
            commitTrickTable(table)
            popToTrickPINList()
        } catch {
            showStory(title: "", body: error.localizedDescription)
        }
    }

    private func confirmDeleteTrick() {
        guard let pin = selectedTrickPIN, let slot = trickTable.slot(forPIN: pin) else { return }
        if slot.isDuressWallet {
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.trickDeleteDuress, onConfirm: .trickConfirmDelete)
            return
        }
        if slot.isSpendingPolicyUnlock && slot.flags == .firmwareDefined {
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.trickDeletePolicy, onConfirm: .trickConfirmDelete)
            return
        }
        let body = slot.isWrongCatchall ? FirmwareCopy.trickDeleteWrong : FirmwareCopy.trickDeletePIN(pin)
        showStory(title: "Are you SURE ?!?", body: body, onConfirm: .trickConfirmDelete)
    }

    private func deleteSelectedTrick() {
        guard let pin = selectedTrickPIN else { return }
        var table = trickTable
        table.delete(pin: pin)
        commitTrickTable(table)
        selectedTrickPIN = nil
        popToTrickPINList()
    }

    private func confirmActivateTrickWallet() {
        showStory(title: "", body: FirmwareCopy.trickActivateWallet, onConfirm: .trickConfirmActivate)
    }

    private func activateSelectedTrickWallet() {
        guard let pin = selectedTrickPIN, let slot = trickTable.slot(forPIN: pin) else { return }
        do {
            if slot.flags.contains(.xprvWallet), let parts = slot.xprvParts() {
                let key = try HDKey.master(privateKey: parts.privateKey, chainCode: parts.chainCode, network: network)
                pendingExtendedKey = try key.serializePrivate()
                pendingMnemonic = nil
                ephemeralOrigin = "Mk3 Duress"
            } else if slot.flags.contains(.wordWallet) {
                let mnemonic = try BIP39Mnemonic(entropy: slot.wordEntropy())
                pendingMnemonic = mnemonic
                pendingExtendedKey = nil
                ephemeralOrigin = "Duress #\(Int(slot.arg) % 10)"
            } else {
                return
            }
            try applyEphemeralSeed()
        } catch {
            present(error)
        }
    }

    private func presentDuressDetails() {
        guard let pin = selectedTrickPIN, let slot = trickTable.slot(forPIN: pin) else { return }
        let body: String
        if slot.flags.contains(.xprvWallet) {
            body = FirmwareCopy.trickLegacyDuressDetails(pin)
        } else {
            let words = TrickPins.bip85WordCount(arg: slot.arg)
            body = FirmwareCopy.trickBIP85DuressDetails(words: words, index: Int(slot.arg), pin: pin)
        }
        showStory(title: "", body: body, onConfirm: .trickDuressDetails)
    }

    private func presentDuressSecrets() {
        guard let pin = selectedTrickPIN, let slot = trickTable.slot(forPIN: pin) else { return }
        if slot.flags.contains(.xprvWallet), let parts = slot.xprvParts() {
            do {
                let key = try HDKey.master(privateKey: parts.privateKey, chainCode: parts.chainCode, network: network)
                let xprv = try key.serializePrivate()
                showStory(title: "Master XPRV", body: xprv)
            } catch {
                showStory(title: "", body: "Not found in SE2. Delete and remake.")
            }
            return
        }
        if slot.flags.contains(.wordWallet) {
            do {
                let mnemonic = try BIP39Mnemonic(entropy: slot.wordEntropy())
                let body = mnemonic.words.enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
                showStory(title: "Seed words (\(mnemonic.words.count)):", body: body)
            } catch {
                showStory(title: "", body: "Not found in SE2. Delete and remake.")
            }
        }
    }

    private func presentCountdownDetails() {
        guard let pin = selectedTrickPIN, let slot = trickTable.slot(forPIN: pin) else { return }
        let minutes = Int(slot.arg == 0 ? 60 : slot.arg)
        let label = TrickPins.countdownMenuLabel(minutes).trimmingCharacters(in: .whitespaces)
        var msg = "Shows login countdown (\(label))"
        if slot.flags.contains(.wipe) {
            msg += ", wipes the seed"
        } else {
            msg += " and reboots at end of countdown"
        }
        if slot.flags.contains(.brick) {
            msg += " and bricks system at end of countdown"
        }
        msg += ".\n\nPress (4) to change time."
        showStory(title: "", body: msg, onConfirm: .trickCountdownDetails)
    }

    private func saveTrickCountdownPeriod(_ minutes: Int) {
        guard let pin = selectedTrickPIN else { return }
        var table = trickTable
        try? table.update(pin: pin, arg: UInt16(minutes))
        commitTrickTable(table)
        back()
    }

    private func popToTrickPINList() {
        pinSetupPurpose = .wallet
        menuStack.removeAll { $0 == .trickNewActions || $0 == .trickWipeChoices
            || $0 == .trickDuressChoices || $0 == .trickCountdownChoices
            || $0 == .trickWrongActions || $0 == .trickPINDetail
            || $0 == .trickCountdownPeriod }
        openMenu(.trickPINs, remember: false)
    }

    private var masterWordCount: Int {
        let phrase = record?.mnemonic ?? ""
        let count = phrase.split(whereSeparator: \.isWhitespace).count
        return count == 12 ? 12 : 24
    }

    private func trickMasterRoot() throws -> HDKey {
        guard let record else { throw SimulatorInputError.missingSeed }
        if let xprv = record.extendedPrivateKey, !xprv.isEmpty {
            return try HDKey(extendedKey: xprv, network: record.network)
        }
        let mnemonic = try BIP39Mnemonic(phrase: record.mnemonic)
        return try HDKey(seed: mnemonic.seed(), network: record.network)
    }

    private func applyTrickDecision(_ decision: TrickLoginDecision, incrementFailureOnFake: Bool) {
        pinInput = ""
        pinPrefix = ""
        unlockPhase = .prefix
        switch decision {
        case .notATrick:
            break
        case .fakeWrongPIN(let wipeSeed):
            if wipeSeed { wipeMasterSeedPreservingTricks() }
            if incrementFailureOnFake {
                failUnlockPIN(applyCatchall: false)
            } else {
                showWrongPINStory()
            }
        case .brick(let wipeSeed):
            if wipeSeed { wipeMasterSeedPreservingTricks() }
            enterBrickedState()
        case .reboot(let wipeSeed):
            if wipeSeed { wipeMasterSeedPreservingTricks() }
            lock()
        case .wipeLockup:
            wipeMasterSeedPreservingTricks()
            lock()
            showStory(title: "", body: FirmwareCopy.trickWipedLockup)
        case .login(let session):
            applyTrickLoginSession(session)
        }
    }

    private func applyTrickLoginSession(_ session: TrickLoginSession) {
        if session.wipeSeed { wipeMasterSeedPreservingTricks() }
        if session.spendingPolicyUnlock {
            handleBypassPINLogin()
            return
        }
        if let minutes = session.countdownMinutes {
            trickBrickAfterCountdown = session.brickAfterCountdown
            loginCountdownOverrideMinutes = minutes
            awaitingPostCountdownPIN = true
            startLoginCountdown()
            return
        }
        if session.deltaMode {
            deltaModeActive = true
            blankWalletSession = false
            guard let record else { return }
            completeMainPINUnlock(record: record)
            return
        }
        switch session.wallet {
        case .blankAppearance:
            blankWalletSession = true
            deltaModeActive = false
            clearActiveKeys()
            finishUnlockedSession(home: false)
        case .words(let entropy):
            do {
                let mnemonic = try BIP39Mnemonic(entropy: entropy)
                pendingMnemonic = mnemonic
                pendingExtendedKey = nil
                ephemeralOrigin = "Duress"
                try applyEphemeralSeed(offerVault: false)
            } catch { present(error) }
        case .xprv(let chainCode, let privateKey):
            do {
                let key = try HDKey.master(privateKey: privateKey, chainCode: chainCode, network: network)
                pendingExtendedKey = try key.serializePrivate()
                pendingMnemonic = nil
                ephemeralOrigin = "Mk3 Duress"
                try applyEphemeralSeed(offerVault: false)
            } catch { present(error) }
        case .realSeed:
            guard let record else { return }
            completeMainPINUnlock(record: record)
        }
    }

    private func wipeMasterSeedPreservingTricks() {
        guard var record else { return }
        let tricks = record.trickPins
        record.mnemonic = ""
        record.extendedPrivateKey = nil
        record.notes = []
        record.settingsXFP = nil
        record.trickPins = tricks
        commitWalletRecord(record)
        clearActiveKeys()
        ephemeralPhrase = nil
        ephemeralXPRV = nil
        pendingMnemonic = nil
        pendingExtendedKey = nil
        activePassphrase = ""
    }

    private func showWrongPINStory() {
        pinInput = ""
        pinPrefix = ""
        unlockPhase = .prefix
        let left = SimulatorStore.maxPINAttempts - failedPINAttempts
        showStory(title: "WRONG PIN", body: "\(left) attempts left\n\nPlease check all digits carefully, and that prefix versus suffix break point is correct.\n\n\(failedPINAttempts) failure\(failedPINAttempts == 1 ? "" : "s")")
    }
}

import Foundation
import UniformTypeIdentifiers
import ColdcardCore

extension SimulatorStore {
    func openSSSP() {
        editingCCCPolicy = false
        if hobbledMode == .testdrive {
            hobbledMode = .off
            openMenu(.ssspConfig)
            return
        }
        if preferences.sssp != nil {
            openMenu(.ssspConfig)
            return
        }
        showStory(title: FirmwareCopy.ssspTitle, body: FirmwareCopy.ssspIntro, onConfirm: .ssspEnable)
    }

    func openCCC() {
        if preferences.ccc != nil {
            if cccKeyCIsInVault {
                showStory(title: FirmwareCopy.reminderTitle, body: FirmwareCopy.cccVaultBypass,
                          onConfirm: .cccEnable)
                return
            }
            showStory(title: FirmwareCopy.cccEnabledTitle, body: FirmwareCopy.cccEnabledChallenge,
                      onConfirm: .cccEnable)
            return
        }
        showStory(title: FirmwareCopy.cccStoryTitle, body: FirmwareCopy.cccIntro, onConfirm: .cccEnable)
    }

    func confirmSpendingStory(_ action: StoryConfirmAction) -> Bool {
        switch action {
        case .ssspEnable:
            back()
            beginSSSPBypassPINSetup()
        case .ssspActivate:
            back()
            activateSSSP()
        case .ssspTestDrive:
            back()
            startSSSPTestDrive()
        case .ssspRemove:
            back()
            removeSSSP()
        case .ssspToggleWords:
            back()
            toggleSSSPFlag(\.wordCheck)
        case .ssspToggleNotes:
            back()
            toggleSSSPFlag(\.allowNotes)
        case .ssspToggleRelatedKeys:
            back()
            toggleSSSPFlag(\.relatedKeys)
        case .cccEnable:
            back()
            if preferences.ccc != nil {
                if cccKeyCIsInVault {
                    openMenu(.cccConfig)
                } else {
                    beginCCCKeyCChallenge()
                }
            } else {
                presentCCCKeyCChooser()
            }
        case .cccGenerateKeyC:
            back()
            startCCCGenerateKeyC()
        case .cccImportKeyC12:
            back()
            beginWordEntry(purpose: .cccKeyC, wordCount: 12)
        case .cccImportKeyC24:
            back()
            beginWordEntry(purpose: .cccKeyC, wordCount: 24)
        case .cccImportKeyCVault:
            back()
            pendingCCCPickFromVault = true
            openMenu(.seedVault)
        case .cccRemove:
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.cccRemoveFunds,
                      onConfirm: .cccRemoveFunds, confirmCode: "4")
        case .cccRemoveFunds:
            back()
            removeCCC()
        case .disableWeb2FA:
            back()
            mutateActivePolicy { $0.web2fa = "" }
            showStory(title: FirmwareCopy.web2FATitle, body: FirmwareCopy.web2FADisabled)
        case .enableWeb2FA:
            back()
            beginWeb2FAEnroll()
        case .enableNFCFor2FA:
            preferences.nfcSharingEnabled = true
            persistPreferencesQuietly()
            back()
            beginWeb2FAEnroll()
        case .cccProceedWithoutSignature:
            back()
            pendingCCCCouldSign = false
            pendingSignNeedsCCC2FA = false
            completePSBTSigning()
        case .cccLoadKeyC:
            back()
            loadCCCKeyCAsTemporarySeed()
        case .cccBuild2ofN:
            back()
            beginCCCKeyBImport()
        case .cccVaultReminder:
            suppressCCCVaultReminder = true
            back()
            back()
            suppressCCCVaultReminder = false
        default:
            return false
        }
        return true
    }

    func performSpendingCommand(_ command: SimulatorCommand) -> Bool {
        switch command {
        case .openSSSP: openSSSP()
        case .openCCC: openCCC()
        case .ssspEditPolicy:
            if currentMenu == .cccConfig { editingCCCPolicy = true }
            else if currentMenu == .ssspConfig { editingCCCPolicy = false }
            openMenu(.spendingPolicyEdit)
        case .ssspWordCheck:
            confirmSSSPToggle(title: "Word Check", body: FirmwareCopy.ssspWordCheckStory,
                              enabled: preferences.sssp?.wordCheck ?? false, action: .ssspToggleWords)
        case .ssspAllowNotes:
            confirmSSSPToggle(title: "Allow Notes", body: FirmwareCopy.ssspAllowNotesStory,
                              enabled: preferences.sssp?.allowNotes ?? false, action: .ssspToggleNotes)
        case .ssspRelatedKeys:
            confirmSSSPToggle(title: "Related Keys", body: FirmwareCopy.ssspRelatedKeysStory,
                              enabled: preferences.sssp?.relatedKeys ?? false, action: .ssspToggleRelatedKeys)
        case .ssspLastViolation: presentSSSPLastViolation()
        case .ssspRemovePolicy:
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.ssspRemoveConfirm, onConfirm: .ssspRemove)
        case .ssspTestDrive:
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.ssspTestDriveConfirm, onConfirm: .ssspTestDrive)
        case .ssspActivate: presentSSSPActivateConfirm()
        case .exitTestDrive:
            hobbledMode = .off
            openMenu(.ssspConfig)
        case .setSpendingMagnitude:
            accountPromptPurpose = .spendingMagnitude
            let mag = activePolicy.mag ?? 0
            accountPromptValue = mag == 0 ? "" : String(mag)
            navigate(to: .accountNumber)
        case .setSpendingVelocity: beginSetVelocity()
        case .pickSpendingVelocity(let blocks):
            mutateActivePolicy { $0.vel = blocks == 0 ? nil : blocks }
            back()
        case .openSpendingWhitelist: openMenu(.spendingPolicyWhitelist)
        case .scanWhitelistQR:
            pendingWhitelistScan = true
            showScanner = true
        case .importWhitelistFile:
            importPurpose = .spendingWhitelist
            showFileImporter = true
        case .clearSpendingWhitelist:
            pendingWhitelistInspectAddress = "__clear_all__"
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.whitelistClearConfirm)
        case .inspectWhitelistAddress(let address):
            pendingWhitelistInspectAddress = address
            showStory(title: "", body: "Spends to this address will be permitted:\n\n\(address)\n\nPress (4) to delete.")
        case .deleteWhitelistAddress(let address):
            mutateActivePolicy { $0.addresses.removeAll { $0 == address } }
        case .toggleSpendingWeb2FA: toggleWeb2FA()
        case .testSpending2FA:
            pendingWeb2FA = .test
            promptWeb2FACode()
        case .enrollMore2FA:
            pendingWeb2FA = .enrollMore
            pendingTOTPSecret = activePolicy.web2fa
            presentWeb2FASecret()
        case .cccShowIdent: presentCCCIdent()
        case .cccExportXPUBs: exportCCCXPUBs()
        case .cccBuild2ofN:
            showStory(title: FirmwareCopy.cccStoryTitle, body: FirmwareCopy.cccBuild2ofNStory,
                      onConfirm: .cccBuild2ofN)
        case .cccLoadKeyC:
            showStory(title: "", body: FirmwareCopy.cccLoadKeyCStory, onConfirm: .cccLoadKeyC)
        case .cccRemove:
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.cccRemoveConfirm, onConfirm: .cccRemove)
        case .cccLastViolation: presentCCCLastViolation()
        case .cccResetBlockHeight:
            mutateActivePolicy { $0.blockH = network.cccMinBlock }
        default:
            return false
        }
        return true
    }

    func handleSpendingStoryKey(_ value: String) -> Bool {
        if story.onConfirm == .cccGenerateKeyC {
            if value == "1" { story.onConfirm = .cccImportKeyC12; confirmStory(); return true }
            if value == "2" { story.onConfirm = .cccImportKeyC24; confirmStory(); return true }
            if value == "6", preferences.seedVaultEnabled, !preferences.vaultedSeeds.isEmpty {
                story.onConfirm = .cccImportKeyCVault
                confirmStory()
                return true
            }
            return false
        }
        if pendingWhitelistInspectAddress != nil, value == "4" {
            let address = pendingWhitelistInspectAddress
            pendingWhitelistInspectAddress = nil
            story.onConfirm = nil
            if address == "__clear_all__" {
                mutateActivePolicy { $0.addresses = [] }
            } else if let address {
                mutateActivePolicy { $0.addresses.removeAll { $0 == address } }
            }
            back()
            return true
        }
        if value == "4", preferences.spendingLastFail != nil,
           (currentMenu == .ssspConfig || currentMenu == .cccConfig || screen == .story) {
            if story.body.contains("policy check failed") {
                preferences.spendingLastFail = nil
                persistPreferencesQuietly()
                back()
                return true
            }
        }
        if value == "1", story.body.contains("Press (1) to clear block height") {
            mutateActivePolicy { $0.blockH = network.cccMinBlock }
            back()
            return true
        }
        return false
    }

    func beginSSSPBypassPINSetup() {
        pinSetupPurpose = .ssspBypass
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

    func finishSSSPBypassPIN(_ pin: String) {
        guard isLikelyPIN(pin) else {
            errorMessage = SimulatorInputError.invalidPIN.localizedDescription
            return
        }
        if pinConflicts(pin) {
            pinPrefix = ""
            pinInput = ""
            pinSetupPhase = .prefix
            showStory(title: "Failure", body: FirmwareCopy.pinAlreadyInUse(pin))
            return
        }
        do {
            let salt = try SecureRandom.bytes(count: 16)
            var settings = SSSPSettings()
            settings.bypassPINSalt = salt
            settings.bypassPINHash = SHA2.sha256(salt + Data(pin.utf8))
            preferences.sssp = settings
            if var record {
                var table = TrickPinTable(slots: record.trickPins)
                if table.slot(forPIN: pin) == nil {
                    try? table.add(pin: pin, flags: .firmwareDefined, arg: TrickPins.spendingPolicyUnlockArg)
                    record.trickPins = table.slots
                    self.record = record
                }
            }
            persistPreferencesQuietly()
            pinSetupPurpose = .wallet
            history.removeAll()
            menuStack.removeAll()
            openMenu(.ssspConfig, remember: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func matchesBypassPIN(_ pin: String) -> Bool {
        if let sssp = preferences.sssp, let salt = sssp.bypassPINSalt, let hash = sssp.bypassPINHash {
            if SHA2.sha256(salt + Data(pin.utf8)) == hash { return true }
        }
        if let record, let slot = record.trickPins.first(where: { $0.pin == pin && $0.isSpendingPolicyUnlock }) {
            return slot.pin == pin
        }
        return false
    }

    func handleBypassPINLogin() {
        awaitingMainPINAfterBypass = true
        pinInput = ""
        pinPrefix = ""
        unlockPhase = .prefix
        showStory(title: "", body: FirmwareCopy.spendingPolicyUnlockNext)
    }

    func completeBypassUnlockAfterMainPIN() {
        awaitingMainPINAfterBypass = false
        if preferences.sssp?.wordCheck == true, wordBasedSeed {
            beginWordEntry(purpose: .ssspFirstLast, wordCount: 2)
            return
        }
        disableSSSPAfterSuccessfulBypass()
        if let record { completeMainPINUnlock(record: record) }
    }

    func applyHobbledAfterUnlock() {
        if preferences.sssp?.enabled == true {
            hobbledMode = .active
        }
    }

    func finishSSSPWordChallenge(words: [String]) {
        let want = (activeMnemonic?.words.first).map { [$0, activeMnemonic?.words.last ?? ""] } ?? []
        if words == want {
            ssspWordCheckFails = 0
            disableSSSPAfterSuccessfulBypass()
            if let record { completeMainPINUnlock(record: record) }
            return
        }
        ssspWordCheckFails += 1
        showStory(title: "", body: FirmwareCopy.ssspWrongWords)
        if ssspWordCheckFails >= 2 {
            ssspWordCheckFails = 0
            lock()
        }
    }

    func finishCCCWordEntry(words: [String], purpose: WordEntryPurpose) {
        switch purpose {
        case .cccKeyC:
            guard let mnemonic = try? BIP39Mnemonic(phrase: words.joined(separator: " ")) else {
                errorMessage = "Invalid seed."
                return
            }
            initCCC(from: mnemonic)
        case .cccChallenge:
            verifyCCCKeyC(words: words)
        default:
            break
        }
    }

    func initCCC(from mnemonic: BIP39Mnemonic) {
        do {
            beginWorking(.wait)
            let key = try HDKey(seed: mnemonic.seed(passphrase: ""), network: network)
            let xpub = try key.neutered().serializePublic()
            preferences.ccc = CCCSettings(
                mnemonic: mnemonic.phrase,
                xfp: key.fingerprintHex,
                xpub: xpub,
                policy: .cccDefault(minBlock: network.cccMinBlock)
            )
            persistPreferencesQuietly()
            pendingCCCSetup = false
            pendingMnemonic = nil
            seedAcknowledged = false
            wordQuiz = nil
            editingCCCPolicy = true
            endWorking()
            history.removeAll { [.seedWords, .wordQuiz, .story, .entropyCollect, .wordEntry, .menu].contains($0) }
            openMenu(.cccConfig, remember: false)
        } catch {
            endWorking()
            errorMessage = error.localizedDescription
        }
    }

    func maybeInitCCCAfterSeedAcknowledgement() -> Bool {
        guard pendingCCCSetup, let mnemonic = pendingMnemonic else { return false }
        initCCC(from: mnemonic)
        return true
    }

    func interceptVaultSeedForCCC(_ seed: VaultedSeed) -> Bool {
        guard pendingCCCPickFromVault else { return false }
        pendingCCCPickFromVault = false
        guard let mnemonic = try? BIP39Mnemonic(phrase: seed.mnemonic) else { return false }
        initCCC(from: mnemonic)
        return true
    }

    func submitSpendingMagnitude(_ value: UInt32) {
        let clamped = min(value, 100_000_000)
        let was = UInt32(activePolicy.mag ?? 0)
        let hadVelocity = (activePolicy.vel ?? 0) != 0
        let msg: String
        if clamped == 0 {
            msg = FirmwareCopy.txMagnitudeCleared + (hadVelocity ? FirmwareCopy.txMagnitudeClearedVelocity : "")
        } else if clamped == was {
            msg = FirmwareCopy.txMagnitudeUnchanged
        } else {
            msg = FirmwareCopy.txMagnitudeSet(SpendingPolicyLimits.renderMagnitude(Int(clamped)))
        }
        mutateActivePolicy { policy in
            if clamped == 0 {
                policy.mag = nil
                if hadVelocity { policy.vel = nil }
            } else {
                policy.mag = Int(clamped)
            }
        }
        back()
        showStory(title: FirmwareCopy.txMagnitudeTitle, body: msg)
    }

    func submitWeb2FACode(_ raw: String) {
        let secretText: String
        switch pendingWeb2FA {
        case .enroll: secretText = pendingTOTPSecret
        case .enrollMore, .test, .ssspSign, .cccSign: secretText = activePolicy.web2fa
        case nil: back(); return
        }
        guard let secret = try? TOTP.secretFromBase32(secretText),
              TOTP.verify(raw, secret: secret) else {
            back()
            handleWeb2FAFailure()
            return
        }
        back()
        handleWeb2FASuccess()
    }

    func importWhitelist(from data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        addWhitelistAddresses(from: text)
    }

    func handleWhitelistScan(_ text: String) -> Bool {
        guard pendingWhitelistScan || pendingCCCKeyBImport else { return false }
        if pendingCCCKeyBImport {
            pendingCCCKeyBImport = false
            ingestCCCKeyB(from: text)
            return true
        }
        pendingWhitelistScan = false
        addWhitelistAddresses(from: text)
        return true
    }

    func applySpendingPolicy(to review: inout PSBTReview, psbt: PSBT) -> Bool {
        pendingSignNeedsSSSP2FA = false
        pendingSignNeedsCCC2FA = false
        pendingCCCCouldSign = false
        let tx = review.spendingTransaction()
        let minBlock = network.cccMinBlock

        var couldCCC = false
        var cccNeeds2FA = false
        if let ccc = preferences.ccc, psbt.involvesMasterFingerprint(ccc.xfp) {
            do {
                let decision = try ccc.policy.evaluate(tx, minBlock: minBlock)
                couldCCC = true
                cccNeeds2FA = decision.needsWeb2FA
            } catch {
                preferences.spendingLastFail = (error as? SpendPolicyViolation)?.firmwareReason ?? "\(error)"
                persistPreferencesQuietly()
                review.warnings.append(FirmwareCopy.cccPolicyWarning)
            }
        }
        pendingCCCCouldSign = couldCCC
        pendingSignNeedsCCC2FA = cccNeeds2FA

        if ssspIsEnabled {
            do {
                let decision = try (preferences.sssp?.policy ?? SpendingPolicyLimits()).evaluate(tx, minBlock: minBlock)
                pendingSignNeedsSSSP2FA = decision.needsWeb2FA
            } catch {
                preferences.spendingLastFail = (error as? SpendPolicyViolation)?.firmwareReason ?? "\(error)"
                persistPreferencesQuietly()
                if !couldCCC {
                    showStory(title: "Failure", body: FirmwareCopy.spendingPolicyViolation)
                    currentPSBT = nil
                    psbtReview = nil
                    return false
                }
            }
        } else if preferences.sssp != nil {
            review.warnings.append(FirmwareCopy.spendingPolicyDisabledWarning)
        }
        return true
    }

    func gatePSBTSigning() -> Bool {
        if pendingSignNeedsCCC2FA, pendingCCCCouldSign {
            pendingWeb2FA = .cccSign
            promptWeb2FACode()
            return false
        }
        if pendingSignNeedsSSSP2FA {
            pendingWeb2FA = .ssspSign
            promptWeb2FACode()
            return false
        }
        return true
    }

    func completePSBTSigning(writeToLowerSlot: Bool = false) {
        guard let root = rootKey, let psbt = currentPSBT else { return }
        let sighashChecks = !preferences.sighashWarnOnly
        let includeCCC = pendingCCCCouldSign
        let cccMnemonic = preferences.ccc?.mnemonic
        let network = self.network
        let deltaMode = deltaModeActive
        let isBIP322 = psbtReview?.bip322Message != nil
        let storedWIF = wifKeys
        let changeIndexes = psbtReview?.outputs.filter(\.isChange).map(\.index) ?? []
        beginWorking(.wait)
        Task {
            let first = await Task.detached(priority: .userInitiated) {
                psbt.signed(using: root, sighashChecks: sighashChecks, deltaMode: deltaMode, wifKeys: storedWIF)
            }.value
            var data = first.data
            var signed = first.psbt
            var results = first.inputs
            if includeCCC, let phrase = cccMnemonic,
               let mnemonic = try? BIP39Mnemonic(phrase: phrase),
               let cccRoot = try? HDKey(seed: mnemonic.seed(passphrase: ""), network: network) {
                let extra = await Task.detached(priority: .userInitiated) {
                    signed.signed(using: cccRoot, sighashChecks: sighashChecks)
                }.value
                data = extra.data
                signed = extra.psbt
                results.append(contentsOf: extra.inputs)
            }
            endWorking()
            signedPSBTData = data
            signedPSBT = signed
            signingResults = results
            finalizedTransaction = isBIP322 ? nil : (try? signed.extractedTransaction())
            if let tx = finalizedTransaction {
                var cache = OutptValueCache(entries: preferences.ovc)
                cache.addFinalizedSegwitChange(
                    txidHash: tx.txidHash,
                    outputs: psbt.segwitChangeOutputs(markedChange: changeIndexes)
                )
                preferences.ovc = cache.persistedEntries
                persistPreferencesQuietly()
            }
            noteSpendingPolicySuccess(lockTime: psbtReview?.lockTime ?? 0)
            if writeToLowerSlot {
                writeSignedPSBTToLowerSlot(data: data, finalized: finalizedTransaction)
            }
            tryPushTxAfterSign()
        }
    }

    /// Firmware `done_signing(..., slot_b=True)` — lower MicroSD slot is Documents/MicroSD.
    private func writeSignedPSBTToLowerSlot(data: Data, finalized: BitcoinTransaction?) {
        let base = DoneSigning.baseName(from: psbtFileBasename)
        do {
            if let transaction = finalized {
                let name = "\(base)-final.txn"
                _ = try writeCardStandin(Data(transaction.serialize().hexString.utf8), named: name, to: .microSD)
            } else {
                let isComplete = (try? signedPSBT?.extractedTransaction()) != nil
                let name = isComplete ? "\(base)-signed.psbt" : "\(base)-part.psbt"
                _ = try writeCardStandin(data, named: name, to: .microSD)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func noteSpendingPolicySuccess(lockTime: UInt32) {
        if var sssp = preferences.sssp {
            sssp.policy.noteSuccessfulSign(lockTime: lockTime)
            preferences.sssp = sssp
        }
        if var ccc = preferences.ccc, pendingCCCCouldSign {
            ccc.policy.noteSuccessfulSign(lockTime: lockTime)
            preferences.ccc = ccc
            preferences.spendingLastFail = nil
        }
        persistPreferencesQuietly()
        pendingSignNeedsSSSP2FA = false
        pendingSignNeedsCCC2FA = false
        pendingCCCCouldSign = false
    }

    func clearSpendingPolicyOnDestroySeed() {
        if var record {
            record.trickPins.removeAll { $0.isSpendingPolicyUnlock && $0.flags == .firmwareDefined }
            self.record = record
        }
        preferences.sssp = nil
        preferences.ccc = nil
        preferences.spendingLastFail = nil
        hobbledMode = .off
        persistPreferencesQuietly()
    }

    func resetSpendingSessionOnLock() {
        hobbledMode = .off
        awaitingMainPINAfterBypass = false
        pendingCCCSetup = false
        pendingWhitelistScan = false
        pendingWeb2FA = nil
        pendingCCCPickFromVault = false
        pendingCCCKeyBImport = false
        pendingSignNeedsSSSP2FA = false
        pendingSignNeedsCCC2FA = false
        pendingCCCCouldSign = false
        editingCCCPolicy = false
    }

    func maybeRemindCCCVaultOnBack() -> Bool {
        guard screen == .menu, currentMenu == .cccConfig, !suppressCCCVaultReminder, cccKeyCIsInVault else {
            return false
        }
        showStory(title: FirmwareCopy.reminderTitle, body: FirmwareCopy.cccVaultLeaveReminder,
                  onConfirm: .cccVaultReminder)
        return true
    }

    var spendingBypassSubtitle: String? {
        pinSetupPurpose == .ssspBypass ? "Spending Policy Unlock" : nil
    }

    private var activePolicy: SpendingPolicyLimits {
        editingCCCPolicy ? (preferences.ccc?.policy ?? SpendingPolicyLimits())
            : (preferences.sssp?.policy ?? SpendingPolicyLimits())
    }

    private var cccKeyCIsInVault: Bool {
        guard let phrase = preferences.ccc?.mnemonic else { return false }
        return preferences.vaultedSeeds.contains { $0.mnemonic == phrase }
    }

    private var displayedBypassPIN: String? {
        record?.trickPins.first { $0.isSpendingPolicyUnlock && $0.flags == .firmwareDefined }?.pin
    }

    private func mutateActivePolicy(_ body: (inout SpendingPolicyLimits) -> Void) {
        if editingCCCPolicy {
            guard var ccc = preferences.ccc else { return }
            body(&ccc.policy)
            preferences.ccc = ccc
        } else {
            guard var sssp = preferences.sssp else { return }
            body(&sssp.policy)
            preferences.sssp = sssp
        }
        persistPreferencesQuietly()
    }

    private func confirmSSSPToggle(title: String, body: String, enabled: Bool, action: StoryConfirmAction) {
        let suffix = enabled ? "Disable?" : "Enable?"
        showStory(title: title, body: body + "\n\n" + suffix, onConfirm: action)
    }

    private func toggleSSSPFlag(_ keyPath: WritableKeyPath<SSSPSettings, Bool>) {
        guard var sssp = preferences.sssp else { return }
        sssp[keyPath: keyPath].toggle()
        preferences.sssp = sssp
        persistPreferencesQuietly()
    }

    private func presentSSSPActivateConfirm() {
        let pin = displayedBypassPIN
        let body: String
        if let pin {
            body = FirmwareCopy.ssspActivateWithPIN(pin, wordCheck: preferences.sssp?.wordCheck ?? false)
        } else {
            body = FirmwareCopy.ssspNoBypassPIN
        }
        showStory(title: "CONTINUE?", body: body, onConfirm: .ssspActivate)
    }

    private func activateSSSP() {
        guard var sssp = preferences.sssp else { return }
        sssp.enabled = true
        preferences.sssp = sssp
        persistPreferencesQuietly()
        hobbledMode = .active
        history.removeAll()
        menuStack.removeAll()
        openMenu(.home, remember: false)
    }

    private func startSSSPTestDrive() {
        hobbledMode = .testdrive
        history.removeAll()
        menuStack.removeAll()
        openMenu(.home, remember: false)
    }

    private func removeSSSP() {
        if var record {
            record.trickPins.removeAll { $0.isSpendingPolicyUnlock && $0.flags == .firmwareDefined }
            self.record = record
        }
        preferences.sssp = nil
        persistPreferencesQuietly()
        hobbledMode = .off
        back()
    }

    private func disableSSSPAfterSuccessfulBypass() {
        if var sssp = preferences.sssp {
            sssp.enabled = false
            preferences.sssp = sssp
            persistPreferencesQuietly()
        }
        hobbledMode = .off
    }

    private func presentSSSPLastViolation() {
        let reason = preferences.spendingLastFail ?? ""
        showStory(title: "Last Violation",
                  body: FirmwareCopy.ssspLastViolation(height: preferences.sssp?.policy.blockH, reason: reason))
    }

    private func presentCCCLastViolation() {
        let reason = preferences.spendingLastFail ?? ""
        showStory(title: "Last Violation",
                  body: FirmwareCopy.cccLastViolation(height: preferences.ccc?.policy.blockH,
                                                      defaultHeight: network.cccMinBlock,
                                                      reason: reason))
    }

    private func beginSetVelocity() {
        if (activePolicy.mag ?? 0) == 0 {
            mutateActivePolicy { $0.mag = 1 }
            showStory(title: "", body: FirmwareCopy.velocityRequiresMagnitude)
            pendingOpenVelocity = true
            return
        }
        openMenu(.spendingPolicyVelocity)
    }

    func openVelocityAfterStoryIfNeeded() {
        guard pendingOpenVelocity else { return }
        pendingOpenVelocity = false
        openMenu(.spendingPolicyVelocity)
    }

    private func toggleWeb2FA() {
        if !activePolicy.web2fa.isEmpty {
            showStory(title: FirmwareCopy.web2FATitle, body: FirmwareCopy.disableWeb2FAConfirm,
                      onConfirm: .disableWeb2FA)
            return
        }
        showStory(title: FirmwareCopy.web2FATitle, body: FirmwareCopy.web2FAStory, onConfirm: .enableWeb2FA)
    }

    private func beginWeb2FAEnroll() {
        if !preferences.nfcSharingEnabled {
            showStory(title: FirmwareCopy.web2FATitle, body: FirmwareCopy.nfcRequiredFor2FA,
                      onConfirm: .enableNFCFor2FA)
            return
        }
        do {
            let raw = try SecureRandom.bytes(count: 20)
            pendingTOTPSecret = Base32.encode(raw)
            pendingWeb2FA = .enroll
            presentWeb2FASecret()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func presentWeb2FASecret() {
        let url = TOTP.otpauthURL(secretBase32: pendingTOTPSecret)
        promptWeb2FACode()
        qrPresentation = QRPresentation(title: FirmwareCopy.web2FATitle, payload: url, sensitive: true)
    }

    private func promptWeb2FACode() {
        accountPromptPurpose = .web2FACode
        accountPromptValue = ""
        if screen != .accountNumber { navigate(to: .accountNumber) }
    }

    private func handleWeb2FASuccess() {
        switch pendingWeb2FA {
        case .enroll:
            mutateActivePolicy { $0.web2fa = pendingTOTPSecret }
            pendingTOTPSecret = ""
            showStory(title: FirmwareCopy.web2FATitle, body: FirmwareCopy.web2FACorrect)
        case .enrollMore, .test:
            showStory(title: FirmwareCopy.web2FATitle, body: FirmwareCopy.web2FACorrect)
        case .ssspSign:
            pendingSignNeedsSSSP2FA = false
            completePSBTSigning()
        case .cccSign:
            pendingSignNeedsCCC2FA = false
            completePSBTSigning()
        case nil:
            break
        }
        pendingWeb2FA = nil
    }

    private func handleWeb2FAFailure() {
        switch pendingWeb2FA {
        case .ssspSign:
            pendingWeb2FA = nil
            showStory(title: "Failure", body: FirmwareCopy.twoFAFailed)
        case .cccSign:
            pendingWeb2FA = nil
            showStory(title: "", body: FirmwareCopy.cccProceedAnyway, onConfirm: .cccProceedWithoutSignature)
        default:
            pendingWeb2FA = nil
            pendingTOTPSecret = ""
            showStory(title: FirmwareCopy.web2FATitle, body: FirmwareCopy.web2FAFailed)
        }
    }

    private func presentCCCKeyCChooser() {
        let body = (preferences.seedVaultEnabled && !preferences.vaultedSeeds.isEmpty)
            ? FirmwareCopy.cccKeyCStoryWithVault : FirmwareCopy.cccKeyCStory
        showStory(title: FirmwareCopy.cccStoryTitle, body: body, onConfirm: .cccGenerateKeyC)
    }

    private func startCCCGenerateKeyC() {
        pendingCCCSetup = true
        createNewSeed(wordCount: 12)
    }

    private func beginCCCKeyCChallenge() {
        let count = preferences.ccc?.mnemonic.split(separator: " ").count ?? 12
        cccChallengeFails = 0
        beginWordEntry(purpose: .cccChallenge, wordCount: count)
    }

    private func verifyCCCKeyC(words: [String]) {
        let got = words.joined(separator: " ")
        if got == preferences.ccc?.mnemonic {
            cccChallengeFails = 0
            openMenu(.cccConfig)
            return
        }
        cccChallengeFails += 1
        showStory(title: "", body: FirmwareCopy.cccWrongWords)
        if cccChallengeFails >= 3 {
            cccChallengeFails = 0
            lock()
        }
    }

    private func presentCCCIdent() {
        let xfp = preferences.ccc?.xfp ?? "--------"
        let xpub = preferences.ccc?.xpub ?? ""
        showStory(title: "", body: FirmwareCopy.cccIdent(xfp: xfp, xpub: xpub))
    }

    private func exportCCCXPUBs() {
        guard let phrase = preferences.ccc?.mnemonic,
              let mnemonic = try? BIP39Mnemonic(phrase: phrase),
              let root = try? HDKey(seed: mnemonic.seed(passphrase: ""), network: network),
              let data = try? WalletExporter.genericJSON(root: root) else { return }
        prepareExport(data: data, filename: "ccc-export.json", type: .json)
    }

    private func loadCCCKeyCAsTemporarySeed() {
        guard let phrase = preferences.ccc?.mnemonic,
              let mnemonic = try? BIP39Mnemonic(phrase: phrase) else { return }
        pendingMnemonic = mnemonic
        pendingEphemeral = true
        ephemeralOrigin = "Key C from CCC"
        do { try applyEphemeralSeed() }
        catch { errorMessage = error.localizedDescription }
    }

    private func beginCCCKeyBImport() {
        pendingCCCKeyBImport = true
        showScanner = true
    }

    private func ingestCCCKeyB(from text: String) {
        let token = text.split(whereSeparator: \.isWhitespace).map(String.init)
            .first { (try? HDKey(extendedKey: $0)) != nil }
        guard let token, let key = try? HDKey(extendedKey: token) else {
            errorMessage = "Need an XPUB from key B."
            return
        }
        let wallet = CCCRelatedWallet(
            name: "CCC",
            requiredSignatures: 2,
            totalSigners: 3,
            keyBXFP: key.fingerprintHex,
            keyBXPUB: token
        )
        if var ccc = preferences.ccc {
            ccc.relatedWallets.append(wallet)
            preferences.ccc = ccc
            persistPreferencesQuietly()
        }
        showStory(title: FirmwareCopy.cccStoryTitle, body: "[\(wallet.keyBXFP)] added as key B.")
    }

    private func removeCCC() {
        preferences.ccc = nil
        persistPreferencesQuietly()
        editingCCCPolicy = false
        back()
    }

    private func addWhitelistAddresses(from text: String) {
        var existing = activePolicy.addresses
        if existing.count >= SpendingPolicyLimits.maxWhitelist {
            showStory(title: "", body: FirmwareCopy.whitelistMaxed)
            return
        }
        let parts = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var added: [String] = []
        var already: [String] = []
        for part in parts where part.count >= 4 {
            guard existing.count < SpendingPolicyLimits.maxWhitelist else { break }
            guard let addr = SpendingPolicyLimits.cleanupPaymentAddress(part) else { continue }
            if existing.contains(addr) {
                already.append(addr)
                continue
            }
            existing.append(addr)
            added.append(addr)
        }
        if !added.isEmpty {
            mutateActivePolicy { $0.addresses = existing }
            showStory(title: "", body: FirmwareCopy.whitelistAdded(added))
        } else if !already.isEmpty {
            showStory(title: "", body: FirmwareCopy.alreadyInWhitelistPrefix + already.joined(separator: "\n"))
        }
    }

    private func pinConflicts(_ pin: String) -> Bool {
        if let record, SHA2.sha256(record.pinSalt + Data(pin.utf8)) == record.pinHash { return true }
        if record?.trickPins.contains(where: { $0.pin == pin }) == true { return true }
        return false
    }

    private func isLikelyPIN(_ pin: String) -> Bool {
        let parts = pin.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { (2...6).contains($0.count) && $0.allSatisfy(\.isNumber) }
    }

    }

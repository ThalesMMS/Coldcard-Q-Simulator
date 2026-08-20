import Foundation
import Observation
import UniformTypeIdentifiers
import UIKit
import ColdcardCore

@MainActor
@Observable
final class SimulatorStore {
    static let officialSimulatorMnemonic = "wife shiver author away frog air rough vanish fantasy frozen noodle athlete pioneer citizen symptom firm much faith extend rare axis garment kiwi clarify"
    static let maxPINAttempts = 13
    static let maxBIP32Index: UInt32 = (1 << 31) - 1

    static func clampPINPart(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        if digits.count <= 6 { return String(digits) }
        return String(digits.prefix(5)) + String(digits.suffix(1))
    }

    var screen: SimulatorScreen = .menu
    var history: [SimulatorScreen] = []
    var selectedMenuIndex = 0
    /// Firmware `MenuSystem.ypos` — first visible menu row (D012).
    var menuYPos = 0
    var currentMenu: FirmwareMenu = .virgin
    var menuStack: [FirmwareMenu] = []

    var errorMessage: String?
    var statusMessage: String?
    var isWorking = false
    /// Firmware fullscreen busy title while `isWorking` (LCD overlay).
    var busyTitle = ""
    /// `nil` = GPU `busy_bar` stripes; `0...1` = `ux_dramatic_pause` fill.
    var busyProgress: Double?

    var pinInput = ""
    var pinPrefix = ""
    var setupPIN = ""
    var confirmPIN = ""
    var failedPINAttempts = 0
    var unlockPhase: UnlockPhase = .prefix
    var pinSetupPhase: PINSetupPhase = .warning
    var pinSetupIsChange = false
    var pinSetupCollectingOld = false
    var pinSetupPurpose: PINSetupPurpose = .wallet
    var selectedTrickPIN: String?
    var proposedTrickPIN = ""
    var proposedTrickWrongCount = 1
    var trickWipeThenWallet = false
    var sessionPIN = ""
    var deltaModeActive = false
    var blankWalletSession = false
    var trickBrickAfterCountdown = false
    var loginCountdownOverrideMinutes: Int?
    var pendingTrickLabel = ""
    var pendingTrickFlags = TrickPinFlags()
    var pendingTrickArg: UInt16 = 0
    var pendingRestoreTrickPins: [TrickPinSlot] = []
    var firstPINValue = ""
    var importSeedText = ""
    var seedWordCount = 24
    var pendingMnemonic: BIP39Mnemonic?
    var pendingNotes: [SecureNote] = []
    var pendingWIFKeys: [WIFStoreItem]?
    var pendingEphemeral = false
    var pendingExtendedKey: String?
    var ephemeralOrigin = "unknown origin"
    var ephemeralPhrase: String?
    var pendingBaseSeed = Data()
    var seedAcknowledged = false
    var wordQuiz: WordQuizRound?
    var quizWrongPause = false
    var throwAwayRestartsQuiz = false
    var quizIsBackupPassword = false
    var diceRolls = ""
    var diceWordCount = 12
    var diceMixesWithTRNG = false
    var diceForPaperWallet = false
    var paperWalletIsSegwit = false
    var paperWalletTemplate: (name: String, data: Data)?
    var paperWalletTemplateFiles: [ListedDiskFile] = []
    var pendingPaperWalletBundle: PaperWalletBundle?
    var lastPaperWalletQR: (address: String, wif: String, isSegwit: Bool)?
    var wordEntryPurpose: WordEntryPurpose = .importSeed
    var wordEntryWords: [String] = []
    var wordEntryPrefix = ""
    var wordEntryHint = ""
    var wordEntryHasChecksum = true
    var wordEntryLastWords: [String] = []
    var entropyKind: EntropyCollectKind = .mash
    var entropyWordCount = 24
    var mashCount = 0
    var mashDigest = Data()
    var mashLastTicks: UInt32 = 0
    var coinFlips = ""
    var renamingVaultSeedID: UUID?
    var pendingVaultDeleteID: UUID?
    var pendingVaultDeleteIsActive = false
    var pendingEphemeralSummarizeUX = true
    var pendingPassphraseAwaitingVault = false
    var pendingPassphraseSaveToKeychain = false
    var psbtExploreKind: PSBTExploreKind = .inputs
    var psbtExploreOffset = 0

    var record: StoredWalletRecord?
    private(set) var activeMnemonic: BIP39Mnemonic?
    private(set) var rootKey: HDKey?

    func clearActiveKeys() {
        rootKey = nil
        activeMnemonic = nil
    }

    var activePassphrase = ""
    var passphraseInput = ""
    var pendingPassphraseXFP = ""
    var pendingPassphraseParentXFP = "--------"
    var textEntryIsNickname = false
    var textEntryIsPushtxURL = false
    var pickingPushTxn = false
    var textEntryIsKeyboardTest = false
    var textEntryIsWIF = false
    var selectedWIFIndex: Int?
    var wifAddressPicker: WIFAddressPickerPurpose?
    var wifSignPrivateKey: Data?
    var pendingVisualizedWIF: String?
    var textEntryIsBKPWOverride = false
    var teleportTextKind: TeleportTextKind = .none
    var teleportReceiverPubkey: Data?
    var teleportPendingQR: KeyTeleportPendingQR?
    var teleportRxEncrypted: Data?
    var teleportSessionKey: Data?
    var teleportWrappedBody: Data?
    var teleportSenderLabel: String?
    var teleportIsPSBTIncoming = false
    var teleportPSBTData: Data?
    var teleportPendingStash: Data?
    var teleportCosignerRows: [KeyTeleportCosignerRow] = []
    var teleportMyPSBTPath: DerivationPath?
    var teleportPSBTXpubs: [PSBTGlobalXpub] = []
    /// Firmware `version.is_devmode`. This unofficial simulator is not a debug-signed firmware image.
    var isDevMode = false
    /// Firmware `ckcc.vcp_enabled` plus the in-app serial REPL stand-in.
    var serialREPL = SerialREPLSession()
    var serialREPLInput = ""
    /// Binding helper so LCD/iPhone toggles update the nested REPL session.
    var serialREPLVCPEnabled: Bool {
        get { serialREPL.vcpEnabled }
        set { _ = serialREPL.setVCPEnabled(newValue) }
    }
    /// Firmware GPU co-processor version (`gpu.get_version` / `gpu_binary.VERSION`).
    var gpuVersion = DeveloperDebug.gpuBundledVersion

    var addressType: AddressType = .nativeSegwit
    var addressAccount: UInt32 = 0
    var addressChange = false
    var addressStartIndex: UInt32 = 0
    /// Firmware pages with a local variable; the menu's "Start Idx" must not change while browsing.
    var addressPageStart: UInt32 = 0
    /// Custom-path result: firmware shows exactly one address, no change toggle, no paging.
    var customSingleAddress = false
    /// Applications (Samourai/Wasabi) pass the account inside the path; explorer state is untouched.
    var addressOverrideAccount: UInt32?
    var derivedAddresses: [DerivedAddress] = []
    var selectedAddress: DerivedAddress?
    var addressPreviews: [AddressType: String] = [:]
    var customPathText = "m/84h/1h/0h/0/0"
    var keypathAtRoot = true
    var keypathCPath = "m"
    var keypathLeaf: UInt32 = 0
    var keypathRanged = true
    var keypathPendingDeeper = ""
    /// Custom path `{idx}` template; nil means a single fully-specified path.
    var addressPathTemplate: String?
    var addressAllowChange = true
    var pendingDetachedSig: (Data, String)?
    var xorEntropyParts: [Data] = []
    var xorWordLists: [[String]] = []
    var xorDesiredWordCount = 24
    var xorForceTemporary = false
    var xorPendingPartCount = 2
    var xorQuizzingSplit = false
    var xorQuizPartIndex = 0
    var xorUsedRNG = false
    var xorChecksumWord = ""
    var xorCanIncludeCurrent = false
    var xorVaultCandidates: [(index: Int, fingerprint: String, entropy: Data)] = []
    var xorVaultSelected: Set<Int> = []
    var pendingBIP85Result: BIP85Result?
    var pendingSiblingChecks: [(digest: String, filename: String)] = []
    var pendingBIP85Kind: BIP85Kind = .words12
    var bip85JustPick = false
    var typePasswordIndexText = ""
    var typePasswordValue: String?
    var typePasswordPath: String?
    var typePasswordCachedIndex: UInt32?
    var typePasswordDidSend = false
    var scrambleDigitMap: [Character: Character] = [:]
    var loginCountdownRemaining = 0
    private var loginCountdownTickSeconds = 1
    var awaitingPostCountdownPIN = false
    var lastUserActivity = Date()
    var scanExpectSecret = false
    var restoreAsEphemeral = false
    var ephemeralXPRV: String?
    private var pendingToggleMenu: FirmwareMenu?
    private var pendingMicroSD2FACheck = false
    private var pendingMicroSD2FALogin = false
    private var pendingMicroSD2FARemoveNonce: String?
    private static let termsAcceptedDefaultsKey = "terms_ok"
    /// Firmware `PRELOGIN_SETTINGS` (`nvstore.py`): available before PIN, including `kbtn`.
    private static let preloginKillKeyDefaultsKey = "kbtn"
    private static let preloginScrambleDefaultsKey = "rngk"
    private static let preloginCountdownDefaultsKey = "lgto"

    var walletExportText = ""
    var walletExportTitle = "Generic Wallet Export"
    var walletExportAddressType: AddressType = .nativeSegwit
    var pendingExport: WalletExportKind?
    var exportAccount: UInt32 = 0
    var exportAddressTypes: [AddressType] = AddressType.singlesigExportOrder
    var descriptorCombined = true
    var pendingKeyExpression = false
    var accountPromptValue = ""
    var accountPromptPurpose: AccountNumberPurpose = .addressExplorer
    var selectedMultisigIndex: Int?
    var exploringMultisigIndex: Int?
    var renamingMultisigIndex: Int?
    var skipMultisigChecks = false
    var pendingMultisigWallet: ImportedMultisigWallet?
    var pendingMultisigPrettyExport = false
    var createAirgappedQR = false
    var createAirgappedFormat: MultisigAddressFormat = .p2wsh
    var createAirgappedCosigners: [MultisigCosigner] = []
    var createAirgappedMineCount = 0
    var lastAddressExplorerLabel: String?

    var currentPSBT: PSBT?
    var psbtReview: PSBTReview?
    var signedPSBTData: Data?
    var signedPSBT: PSBT?
    var finalizedTransaction: BitcoinTransaction?
    var psbtSourceName = ""
    var loadedPSBTSHA: Data?
    var loadedPSBTURL: URL?
    /// Firmware `ApproveTransaction.input_method` (`sd` enables `(B)` write to the lower slot).
    var psbtInputMethod = "usb"
    var signingResults: [PSBTInputSigningResult] = []
    var psbtSourceURL: URL?
    var psbtInputChannel: PSBTInputChannel = .other
    var psbtSignedTitle = DoneSigning.signedTitle
    var psbtSignedPriorMessage: String?
    var psbtSignedFirstPass = true
    var teleportFromSignedPSBT = false
    var teleportRemainingSigs = 0

    var messageText = ""
    var messageAccount: UInt32 = 0
    var messageChange = false
    var messageIndex: UInt32 = 0
    var messageAddressType: AddressType = .legacy
    var messagePath = "m/44'/1'/0'/0/0"
    var signedMessage: SignedBitcoinMessage?
    var messageSourceFilename = "msg_sign.txt"
    var messagePathLocked = false
    /// Own-address / keyboard: 100. File, QR, USB, notes: `MSG_SIGNING_MAX_LENGTH` 240.
    var messageMaxLength = BitcoinMessageSigner.uxInputMaximumLength
    var messageSignDoneMode: MessageSignDoneMode = .exportPrompt
    var messageAllowTabNewline = false

    var noteTitle = ""
    var noteUsername = ""
    var notePassword = ""
    var noteSite = ""
    var noteBody = ""
    var noteEditorMode: NoteEditorMode = .createNote
    var selectedNoteID: UUID?
    var selectedSavedPassphraseID: UUID?
    var selectedVaultSeedID: UUID?
    var pendingNoteDelete = false
    var pendingNoteExportAll = false
    var selectedNoteGroup: String?
    var noteGroupDraft = ""
    var pendingNoteQuickCreate = false
    var pendingNotesFileExport = false
    var pendingNotesJSON: Data?
    var pendingNotesFilename = "cc-notes.json"
    var pendingNotesSignature: Data?
    var pendingEncryptedNotesData: Data?
    var pendingNotesExportDestination: AddressExportDestination = .sdCard
    var listedFilesAreNotesImport = false
    var textEntryIsNotesImportPassword = false
    var textEntryIsNoteGroup = false
    var keyboardShift = false
    var isBricked = false
    var keyboardSymbol = false
    /// Firmware `caps_lock` (SYM+SHIFT). LCD `aA` glyph should bind this.
    var keyboardCaps = false
    /// Firmware `ux.py` story `top` line offset. LCD paging visuals bind this (D011).
    var storyTop = 0
    /// Wrapped story line count including title/EOT (set by the LCD story view).
    var storyLineCount = 2
    var lcdPowerUnknown = true
    var lcdPowerCharging = false
    var lcdPowerLevel: Float = -1
    /// Q lamp / torch while held (`keyboard.py` KEY_LAMP). Tap flashes the device overlay.
    var torchOn = false
    var customPathIsKeyExpression = false
    var pendingCacheBackupPassword = false
    var exportSLIP132 = false

    var settingsNickname = ""
    var settingsNetwork: BitcoinNetwork = .testnet
    var preferences = SimulatorPreferences()

    var backupPassword = ""
    var backupConfirmPassword = ""
    var backupPasswordWords: [String] = []
    var textEntryIsCustomBackupPassword = false
    var restoreBackupAllowsCleartext = false
    var pendingBackupRestoreData: Data?
    var pendingBackupRestoreFilename = ""
    var pendingBackupExportData: Data?
    var pendingBackupExportFilename = BackupFile.encryptedFilename
    var pendingBackupExportType: UTType = .sevenZip
    var backupCopyIndex = 0
    var backupAllowCopies = true
    var hexEntryText = ""
    var cloneSessionPrivateKey: Data?
    var clonePeerPubkey: Data?
    var cloneIngestTriedCard = false
    var pendingCloneIngestAfterExport = false
    var pendingTapsignerCiphertext: Data?
    var pendingTapsignerOrigin = ""
    var importPurpose: ImportPurpose = .psbt
    var batchQueue: [BatchPSBTItem] = []
    var pendingBatchItem: BatchPSBTItem?
    /// `history.count` under the `_batch_sign` per-file story, so skip/export/refuse
    /// return to the same caller (File Management or Ready To Sign).
    private var batchSignCallerDepth: Int?
    var pendingExportSuccessStory: (title: String, body: String)?
    var pendingRestorePayload: WalletBackupPayload?
    var importAllowsMultiple: Bool { importPurpose == .batchPSBT || importPurpose == .siblingHashes }
    var fileImporterContentTypes: [UTType] {
        switch importPurpose {
        case .backup:
            if restoreBackupAllowsCleartext {
                return [.sevenZip, .plainText, .data, .coldcardSimulatorBackup]
            }
            return [.sevenZip, .data, .coldcardSimulatorBackup]
        case .verifyBackup:
            return [.sevenZip, .data, .coldcardSimulatorBackup]
        default:
            return [.psbt, .data, .plainText, .json, .coldcardSimulatorBackup, .sevenZip]
        }
    }
    var showFileImporter = false
    var showNFCStandIn = false
    var nfcStandInKind: NFCStandInKind = .psbt
    var listedFilesAreNFCShare = false
    var nfcReceiveNeedsStandIn = false
    var textEntryIsNFCSeed = false
    var textEntryIsNFCTools = false
    var nfcAwaitingQRStandIn = false
    var nfcReadGeneration = 0
    var pendingNFCShownAddress: DerivedAddress?
    var pendingNFCShownAddressType: AddressType = .nativeSegwit
    var pendingOwnershipCanSign = false
    var pendingNFCMultisig: ImportedMultisigWallet?
    var pendingNFCMultisigDuplicate = false
    var pendingNFCMultisigShowingXPUBs = false
    var showFileExporter = false
    var exportDocument = DataDocument()
    var exportContentType: UTType = .data
    var exportFilename = "coldcard-export"

    var showScanner = false
    /// `q1.scan_and_bag` is waiting for a bag barcode.
    var pendingBagScan = false
    var qrPresentation: QRPresentation?
    private var bbqrCollector = BBQrCollector()
    /// Firmware `draw_bbqr_progress` while a multi-part BBQr is arriving.
    var bbqrScanProgress: BBQrScanProgress?
    var story = StoryPresentation(title: "", body: "")

    var selftestFill: SelftestFill?
    var selftestLED: QSelftest.LED = .off
    var selftestExpectedKey: String?
    var selftestExpectedKeyLabel: String {
        guard let key = selftestExpectedKey else { return "" }
        return QSelftest.keyboardLabel(for: key)
    }
    /// Firmware `NFCHandler.selftest` / `share_start(allow_enter=False)`.
    var selftestAwaitingNFCShare = false
    private var selftestQueue: [QSelftest.Step] = []
    private var selftestInProgress = false
    var selftestAllowsSkip = false
    private var selftestAllowsEnter = true
    private var selftestAbortReason = QSelftest.confirmAbortReason
    var calculatorExpression = ""
    var calculatorLines: [String] = CalculatorLogin.exampleLines
    var calculatorResult = "0"
    /// GPU `busy_bar` without a fullscreen `Wait...` overlay (`calc.py` / `login.py`).
    var gpuBusyBar = false
    var identityText = ""
    var scannerPrompt: String {
        if importPurpose == .xprv { return FirmwareCopy.scanXPRVPrompt }
        if pendingBagScan { return FirmwareCopy.scanBagBarcodePrompt }
        return scanExpectSecret ? FirmwareCopy.scanSecretQRPrompt : FirmwareCopy.scanAnyQRPrompt
    }
    /// Firmware `scan_text` / `expect_text=True` (notes, passphrase, keyboard text).
    var scanExpectsText: Bool {
        pendingNoteQuickCreate || screen == .noteEditor || screen == .passphrase
    }
    var showsBBQrProgressBar: Bool {
        guard let progress = bbqrScanProgress else { return false }
        return !progress.skipsProgressUI
    }
    var loginCountdownMustWait: String { LoginUX.countdownMustWait }
    var loginCountdownDelayText: String { LoginUX.countdownDelayText(seconds: loginCountdownRemaining) }
    var entropyCollectLine2: String {
        SeedCreation.entropyLine2(kind: seedEntropyKind, count: entropyEventCount)
    }
    var entropyCollectLine3: String {
        SeedCreation.entropyLine3(kind: seedEntropyKind, count: entropyEventCount)
    }
    private var seedEntropyKind: SeedEntropyKind {
        switch entropyKind {
        case .mash: .mash
        case .coin: .coin
        case .diceMix: .diceMix
        }
    }
    private var entropyEventCount: Int {
        switch entropyKind {
        case .mash: mashCount
        case .coin: coinFlips.count
        case .diceMix: diceRolls.count
        }
    }
    var seedWordEntryKind: SeedWordEntryKind {
        switch wordEntryPurpose {
        case .importSeed: pendingEphemeral ? .importEphemeral : .importMaster
        case .backupPassword, .notesImportPassword: .backupPassword
        case .xorPart: .xorPart(index: xorEntropyParts.count)
        case .ssspFirstLast: .ssspFirstLast
        case .cccKeyC: .cccKeyC
        case .cccChallenge: .cccChallenge
        }
    }
    var wordEntryCursor: PINCursor { SeedCreation.cursor(prefixLength: wordEntryPrefix.count) }
    var passphraseConfirmBody: String {
        let parent = BIP39Passphrase.parentSeedLabel(
            tmpActive: tmpSeedActive,
            parentXFP: pendingPassphraseParentXFP
        )
        return """
        Above is the master key fingerprint of the new wallet created by adding passphrase to \(parent).

        Scroll down to view and verify your passphrase.


        Passphrase: \(passphraseInput)

        \(BIP39Passphrase.applyFooter)

        \(BIP39Passphrase.keychainStandIn)
        """
    }

    var listedDiskFiles: [ListedDiskFile] = []
    var selectedListedFile: ListedDiskFile?
    private let virtDiskMonitor = VirtDiskAutoMonitor()

    var isScreenExpanded = false
    var interfaceMode: InterfaceMode = .device {
        didSet { UserDefaults.standard.set(interfaceMode.rawValue, forKey: Self.interfaceModeDefaultsKey) }
    }
    private static let interfaceModeDefaultsKey = "interfaceMode"

    /// Firmware bootrom `pairing_secret` analogue; independent of PIN salt and seed.
    var pairingSecret = Data()

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.interfaceModeDefaultsKey),
           let mode = InterfaceMode(rawValue: raw) {
            interfaceMode = mode
        }
        do {
            pairingSecret = try Self.loadOrCreatePairingSecret()
        } catch {
            errorMessage = "Unable to read the pairing secret: \(error.localizedDescription)"
        }
        do {
            if let data = try KeychainStore.load() {
                record = try JSONDecoder().decode(StoredWalletRecord.self, from: data)
                settingsNickname = record?.nickname ?? ""
                settingsNetwork = record?.network ?? .testnet
                preferences = record?.preferences ?? SimulatorPreferences()
                applyPreloginSettingsOverlay()
                failedPINAttempts = record?.failedPINAttempts ?? 0
                isBricked = record?.isBricked == true || failedPINAttempts >= Self.maxPINAttempts
                if isBricked {
                    enterBrickedState()
                } else {
                    goToLockedRoot()
                }
            } else {
                applyPreloginSettingsOverlay()
                presentFirstBoot()
            }
        } catch {
            errorMessage = "Unable to read the Keychain record: \(error.localizedDescription)"
            presentFirstBoot()
        }
        SimulatorCardStandin.ensureDirectories()
        virtDiskMonitor.onNewPSBT = { [weak self] url in
            self?.handleAutoVirtualDiskPSBT(url)
        }
        refreshLCDPower()
    }

    var isUnlocked: Bool { rootKey != nil || blankWalletSession }
    var nickname: String { record?.nickname ?? settingsNickname }
    var network: BitcoinNetwork { rootKey?.network ?? record?.network ?? settingsNetwork }
    var fingerprint: String {
        bracketedHomeXFP ?? "--------"
    }
    var notes: [SecureNote] { record?.notes ?? [] }
    var mnemonicWords: [String] {
        if xorQuizzingSplit, screen == .seedWords, xorWordLists.indices.contains(xorQuizPartIndex) {
            return xorWordLists[xorQuizPartIndex]
        }
        return (pendingMnemonic ?? activeMnemonic)?.words ?? []
    }
    var canExportPSBT: Bool { signedPSBTData != nil || currentPSBT != nil }
    var hasSeed: Bool { !blankWalletSession && record?.hasSeed == true }
    var hasPIN: Bool { record != nil }
    var displayUnits: DisplayUnits { preferences.displayUnits }
    var menuItems: [SimulatorMenuItem] {
        if currentMenu == .xorVaultPick { return xorVaultMenuItems }
        if let rows = keyTeleportMenuItems() { return rows }
        return FirmwareMenuCatalog.items(
            menu: currentMenu, secnapEnabled: preferences.secnapEnabled && !deltaModeActive, hasSeed: hasSeed,
            notes: notes, selectedNote: selectedNote,
            savedPassphrases: preferences.savedPassphrases,
            selectedSavedPassphrase: selectedSavedPassphrase,
            addressPreviews: addressPreviews,
            accountNumber: addressAccount, startIndex: addressStartIndex,
            aeStartIndexEnabled: preferences.aeStartIndexEnabled,
            displayUnits: preferences.displayUnits, maxFee: preferences.maxNetworkFee,
            deletePSBTs: preferences.deletePSBTs, menuWrapping: preferences.menuWrapping,
            calculatorLogin: preferences.calculatorLogin, alwaysShowHomeXFP: preferences.alwaysShowHomeXFP,
            sighashWarnOnly: preferences.sighashWarnOnly,
            network: network,
            seedVaultEnabled: preferences.seedVaultEnabled && !deltaModeActive,
            ephemeralActive: ephemeralPhrase != nil || ephemeralXPRV != nil,
            vaultedSeeds: preferences.vaultedSeeds,
            selectedVaultSeed: selectedVaultSeed,
            exportAddressTypes: exportAddressTypes,
            selectedNoteGroup: selectedNoteGroup,
            homeXFP: bracketedHomeXFP,
            tmpSeedActive: tmpSeedActive,
            wordBasedSeed: wordBasedSeed,
            hasPassphrase: !activePassphrase.isEmpty,
            keypathAtRoot: keypathAtRoot,
            keypathCPath: keypathCPath,
            keypathLeaf: keypathLeaf,
            keypathRanged: keypathRanged,
            scrambleKeys: preferences.scrambleKeys,
            killKey: preferences.killKey,
            loginCountdownMinutes: preferences.loginCountdownMinutes,
            b85Unlimited: preferences.b85Unlimited,
            idleTimeoutSeconds: preferences.idleTimeoutSeconds,
            idleTimeoutBatterySeconds: preferences.idleTimeoutBatterySeconds,
            nfcSharingEnabled: preferences.nfcSharingEnabled,
            usbPortEnabled: preferences.usbPortEnabled,
            virtualDiskMode: preferences.virtualDiskMode,
            keyboardEmuEnabled: preferences.keyboardEmuEnabled,
            hasPushtxURL: hasPushtxURL,
            ptxurl: preferences.ptxurl,
            listedFiles: listedDiskFiles,
            spending: spendingPolicySnapshot,
            sd2faNonces: preferences.sd2faNonces,
            wifKeys: wifKeys,
            selectedWIFIndex: selectedWIFIndex,
            trickTable: trickTable,
            selectedTrickPIN: selectedTrickPIN,
            proposedTrickPIN: proposedTrickPIN,
            proposedTrickWrongCount: proposedTrickWrongCount,
            sessionPIN: sessionPIN,
            masterWordCount: (record?.mnemonic ?? "").split(whereSeparator: \.isWhitespace).count == 12 ? 12 : 24,
            paperWalletIsSegwit: paperWalletIsSegwit,
            paperWalletMakingPDF: paperWalletTemplate != nil,
            paperWalletTemplates: paperWalletTemplateFiles,
            multisig: multisigMenuSnapshot
        )
    }

    var hobbledMode: HobbledMode = .off
    var pendingCCCSetup = false
    var editingCCCPolicy = false
    var awaitingMainPINAfterBypass = false
    var pendingWhitelistScan = false
    var pendingWeb2FA: SpendingWeb2FAPending?
    var cccChallengeFails = 0
    var ssspWordCheckFails = 0
    var pendingCCCPickFromVault = false
    var pendingCCCKeyBImport = false
    var pendingSignNeedsSSSP2FA = false
    var pendingSignNeedsCCC2FA = false
    var pendingCCCCouldSign = false
    var pendingWhitelistInspectAddress: String?
    var pendingTOTPSecret = ""
    var suppressCCCVaultReminder = false
    var pendingOpenVelocity = false

    var spendingPolicySnapshot: SpendingPolicyMenuSnapshot {
        let sssp = preferences.sssp
        let policy = editingCCCPolicy ? (preferences.ccc?.policy ?? SpendingPolicyLimits()) : (sssp?.policy ?? SpendingPolicyLimits())
        return SpendingPolicyMenuSnapshot(
            hobbled: hobbledMode,
            ssspDefined: sssp != nil,
            wordCheck: sssp?.wordCheck ?? false,
            allowNotes: sssp?.allowNotes ?? false,
            relatedKeys: sssp?.relatedKeys ?? false,
            cccDefined: preferences.ccc != nil,
            cccXFP: preferences.ccc?.xfp,
            cccRelated: preferences.ccc?.relatedWallets ?? [],
            lastViolation: preferences.spendingLastFail,
            policy: policy,
            notesReadOnly: hobbledMode.isHobbled
        )
    }

    var ssspIsEnabled: Bool { hobbledMode == .testdrive || preferences.sssp?.enabled == true }
    /// Word-based BIP-39 seed (firmware `word_based_seed`), including an active ephemeral mnemonic.
    var wordBasedSeed: Bool {
        if ephemeralXPRV != nil { return false }
        let phrase = ephemeralPhrase ?? activeMnemonic?.phrase ?? record?.mnemonic ?? ""
        return phrase.split(whereSeparator: \.isWhitespace).count >= 12
    }
    /// A temporary seed is active: RAM ephemeral seed or BIP-39 passphrase wallet.
    var tmpSeedActive: Bool { ephemeralPhrase != nil || ephemeralXPRV != nil || !activePassphrase.isEmpty }
    /// Firmware `glob.VD is not None` — Virtual Disk Enable or Enable & Auto.
    var virtualDiskEnabled: Bool { preferences.virtualDiskMode != 0 }
    /// Firmware `ready2sign` empty story (`import_export_prompt` + `_import_prompt_builder`).
    var psbtEmptyStory: String {
        ReadyToSign.emptyStory(
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: preferences.nfcSharingEnabled
        )
    }
    /// Firmware brackets: `[XFP]` for temporary seeds, `<XFP>` for the master seed (flow.py).
    var bracketedHomeXFP: String? {
        guard isUnlocked, let xfp = rootKey?.fingerprintHex else { return nil }
        if tmpSeedActive { return "[\(xfp)]" }
        if preferences.alwaysShowHomeXFP { return "<\(xfp)>" }
        return nil
    }
    /// Firmware `draw_status` XFP: settings value, including the locked/PIN screens.
    var lcdXFPGlyphs: String? {
        let raw = rootKey?.fingerprintHex ?? record?.settingsXFP
        guard LCDStatus.showsXFP(raw) else { return nil }
        return LCDStatus.xfpGlyphs(raw ?? "")
    }
    var lcdPowerIcon: LCDPowerIcon {
        LCDStatus.powerIcon(level: lcdPowerLevel, isCharging: lcdPowerCharging, isUnknown: lcdPowerUnknown)
    }

    func refreshLCDPower() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        let level = UIDevice.current.batteryLevel
        lcdPowerCharging = state == .charging || state == .full
        #if targetEnvironment(simulator)
        // iOS Simulator has no battery ADC; default to a mid battery so the icon is not always a plug.
        if state == .unknown && !lcdPowerCharging {
            lcdPowerUnknown = false
            lcdPowerLevel = level >= 0 ? level : 0.55
            return
        }
        #endif
        lcdPowerUnknown = state == .unknown
        lcdPowerLevel = level
    }
    var selectedNote: SecureNote? { notes.first { $0.id == selectedNoteID } }
    var selectedSavedPassphrase: SavedPassphrase? {
        preferences.savedPassphrases.first { $0.id == selectedSavedPassphraseID }
    }
    var selectedVaultSeed: VaultedSeed? {
        preferences.vaultedSeeds.first { $0.id == selectedVaultSeedID }
    }
    var diceRunningHash: String {
        guard SeedCreation.showsRunningHash(mixWithTRNG: diceMixesWithTRNG) else { return "" }
        return SeedCreation.diceRunningHashHex(rolls: diceRolls)
    }
    var diceRunningHashLines: (top: String, bottom: String) {
        SeedCreation.diceRunningHashLines(hex: diceRunningHash)
    }
    var screenTitle: String {
        switch screen {
        case .menu:
            if currentMenu == .noteGroup, let group = selectedNoteGroup, !group.isEmpty {
                return "↳ \(group)"
            }
            if currentMenu == .noteActions, let note = selectedNote,
               let index = notes.firstIndex(where: { $0.id == note.id }) {
                return NoteMenuCopy.parentRowLabel(index: index, title: note.title)
            }
            if currentMenu == .savedPassphraseActions, let selected = selectedSavedPassphrase {
                let phrases = preferences.savedPassphrases.map(\.phrase)
                if let idx = preferences.savedPassphrases.firstIndex(where: { $0.id == selected.id }) {
                    return FirmwareMenuCatalog.maskedPassphrases(phrases)[idx]
                }
            }
            if currentMenu == .seedVaultActions, let seed = selectedVaultSeed,
               let index = preferences.vaultedSeeds.firstIndex(where: { $0.id == seed.id }) {
                return SeedVaultMenuCopy.parentRowLabel(
                    index: index,
                    label: SeedVaultMenuCopy.storedLabel(custom: seed.label, fingerprint: seed.fingerprint)
                )
            }
            return FirmwareMenuCatalog.title(for: currentMenu)
        case .unlock:
            switch unlockPhase {
            case .prefix: return FirmwareCopy.pinPrefixPrompt
            default: return FirmwareCopy.pinSuffixPrompt
            }
        case .pinSetup: return pinSetupTitle
        case .seedWords:
            if mnemonicWords.isEmpty { return "Seed Words" }
            if xorQuizzingSplit {
                return "Record these \(mnemonicWords.count) secret words!"
            }
            return pendingMnemonic == nil ? "Seed words (\(mnemonicWords.count)):" : "Record these \(mnemonicWords.count) secret words!"
        case .wordQuiz:
            if xorQuizzingSplit, let quiz = wordQuiz {
                return SeedXORStories.quizTitle(partIndex: xorQuizPartIndex, wordNumber: quiz.wordIndex + 1)
            }
            return wordQuiz.map { "Word \($0.wordIndex + 1) is?" } ?? "Word Quiz"
        case .diceRoll: return SeedCreation.diceOnlyScreenTitle
        case .importSeed: return "Enter Seed Words"
        case .passphrase:
            if renamingVaultSeedID != nil { return "Rename" }
            if renamingMultisigIndex != nil { return "Rename" }
            if textEntryIsNickname { return LoginUX.nicknamePrompt }
            if textEntryIsPushtxURL { return FirmwareCopy.enterPushtxURL }
            if textEntryIsNoteGroup { return "Group" }
            if textEntryIsKeyboardTest { return DeveloperDebug.keyboardTestPrompt }
            if textEntryIsBKPWOverride { return DeveloperDebug.bkpwPasswordPrompt }
            if textEntryIsNotesImportPassword { return "Your Backup Password" }
            if textEntryIsCustomBackupPassword { return BackupFile.backupPasswordPrompt }
            if textEntryIsWIF { return "Enter WIF" }
            if textEntryIsNFCSeed { return "Import via NFC" }
            if textEntryIsNFCTools { return nfcStandInTitle }
            if let prompt = teleportPassphrasePrompt { return prompt }
            return "Your BIP-39 Passphrase"
        case .passphraseConfirm: return pendingPassphraseXFP.isEmpty ? "Passphrase" : "[\(pendingPassphraseXFP)]"
        case .addresses: return "Address Explorer"
        case .addressDetail: return "Payment Address"
        case .accountNumber:
            switch accountPromptPurpose {
            case .addressStartIndex: return "Start index:"
            case .psbtExploreIndex:
                let maxIdx = max(0, psbtExplorerMax - 1)
                return DoneSigning.startIdxPrompt(maxIndex: maxIdx)
            case .keypathIndex: return "\(keypathPendingDeeper)/"
            case .bip85Index: return pendingBIP85Kind == .password ? "Password Index?" : "Index Number?"
            case .messageIndex: return "Index Number:"
            case .spendingMagnitude: return "Transaction Max:"
            case .web2FACode: return "2FA Code:"
            case .trickWrongCount: return FirmwareCopy.trickWrongAttemptsTitle
            case .multisigCreateM: return "How many need to sign?(M)"
            default: return "Account Number:"
            }
        case .psbt:
            if psbtReview == nil {
                // Firmware `ready2sign`: tmp seed titles the empty story `[XFP]`;
                // master uses `title=None` (no invert title).
                return ReadyToSign.emptyTitle(temporarySeed: tmpSeedActive, xfp: rootKey?.fingerprintHex)
            }
            return PSBT.approvalTitle(isBIP322: psbtReview?.bip322Message != nil)
        case .psbtSigned: return psbtSignedTitle
        case .walletExport: return walletExportTitle
        case .messageSigning: return "Sign Message"
        case .noteEditor: return noteEditorTitle
        case .backupPassword: return "Backup System"
        case .verifyBackup: return importPurpose == .backup ? "Restore Backup" : pendingEncryptedNotesData != nil ? "Data Import" : "Verify Backup"
        case .hexEntry: return FirmwareCopy.tapsignerKeyPrompt
        case .calculator: return " ECC Calculator "
        case .story: return story.title
        case .viewIdentity: return "View Identity"
        case .brick: return "I Am Brick!"
        case .wordEntry:
            if wordEntryPurpose == .notesImportPassword { return "Enter Password:" }
            return SeedCreation.wordEntryTitle(seedWordEntryKind)
        case .entropyCollect:
            switch entropyKind {
            case .mash: return "Mash Keys"
            case .coin: return "Coin Flips"
            case .diceMix: return "Dice Rolls"
            }
        case .psbtExplorer:
            if psbtExploreKind == .inputs { return "Input \(psbtExploreOffset)" }
            let end = min(psbtExploreOffset + 10, psbtExplorerMax)
            return DoneSigning.outputTitle(offset: psbtExploreOffset, endExclusive: end)
        case .loginCountdown: return FirmwareCopy.loginCountdownTitle
        case .nicknameSplash: return nickname
        case .typePasswordIndex: return "Password Index?"
        case .typePasswordConfirm: return typePasswordDidSend ? "Sent." : ""
        case .listedFileRename: return FirmwareCopy.uxInputTextPrompt
        case .serialREPL: return "Serial REPL"
        case .nfcReceive: return ""
        case .factoryBagged: return displayedBagNumber ?? FirmwareCopy.unbaggedTitle
        case .factoryDFU: return FirmwareCopy.enterBootloaderDFU
        case .poweredOff: return ""
        }
    }

    /// Firmware `send_keystrokes` story, then clipboard stand-in confirmation.
    var typePasswordConfirmBody: String {
        guard let password = typePasswordValue, let path = typePasswordPath else { return "" }
        if typePasswordDidSend {
            return TypePasswords.sentConfirmation(password: password)
        }
        return TypePasswords.sendPrompt(okKey: FirmwareCopy.okKey, password: password, path: path)
    }

    var showsBack: Bool {
        switch screen {
        case .brick, .loginCountdown, .nicknameSplash, .factoryBagged, .factoryDFU, .poweredOff: false
        case .unlock: true
        case .menu: switch currentMenu {
            case .virgin, .factory, .emptyWallet, .home: false
            default: true
            }
        case .calculator: isUnlocked
        default: true
        }
    }

    private var pinSetupTitle: String {
        if pinSetupPurpose == .trickNew || pinSetupPurpose == .trickChange { return "New Trick PIN" }
        if pinSetupPurpose == .ssspBypass { return "Spending Policy Unlock" }
        if pinSetupCollectingOld { return "Old Main PIN" }
        switch pinSetupPhase {
        case .warning: return "Choose PIN"
        case .proveRead: return "WARNING"
        case .prefix, .confirmPrefix:
            return LoginUX.pinEntryTitle(
                isConfirmation: pinSetupPhase == .confirmPrefix,
                subtitle: pinSetupIsChange ? "New Main PIN" : nil,
                editingPrefix: true
            )
        case .suffix, .confirmSuffix:
            return LoginUX.pinEntryTitle(
                isConfirmation: pinSetupPhase == .confirmSuffix,
                subtitle: pinSetupIsChange ? "New Main PIN" : nil,
                editingPrefix: false
            )
        }
    }

    private var noteEditorTitle: String {
        switch noteEditorMode {
        case .createNote: "New Note"
        case .createPassword: "New Password"
        case .editNote: "Edit"
        case .editPasswordMetadata: "Edit Metadata"
        case .changePassword: "Change Password"
        }
    }

    var isXPUBOnlyExport: Bool {
        switch pendingExport {
        case .xpubSegwit, .xpubClassic, .xpubWrapped, .xpubMaster, .xpubXFP: true
        default: false
        }
    }

    func formatAmount(_ value: UInt64?) -> String {
        guard let value else { return "? \(preferences.displayUnits.menuTitle)" }
        return preferences.displayUnits.format(value, network: network)
    }

    func navigate(to destination: SimulatorScreen, remember: Bool = true) {
        noteUserActivity()
        if remember { history.append(screen) }
        screen = destination
        selectedMenuIndex = 0
        menuYPos = 0
        storyTop = 0
        errorMessage = nil
        statusMessage = nil
        if destination == .addresses { loadAddresses() }
        if destination == .walletExport && walletExportText.isEmpty { generateGenericWalletExport() }
    }

    func openMenu(_ menu: FirmwareMenu, remember: Bool = true) {
        if menu == .notes, !notes.isEmpty, wipeIfDeltaMode() { return }
        if (menu == .seedVault || menu == .seedVaultActions), !preferences.vaultedSeeds.isEmpty,
           wipeIfDeltaMode() { return }
        if remember {
            history.append(screen)
            if screen == .menu { menuStack.append(currentMenu) }
        }
        currentMenu = menu
        screen = .menu
        selectedMenuIndex = FirmwareMenuCatalog.chooserIndex(
            menu: menu, displayUnits: preferences.displayUnits, maxFee: preferences.maxNetworkFee,
            deletePSBTs: preferences.deletePSBTs, calculatorLogin: preferences.calculatorLogin,
            alwaysShowHomeXFP: preferences.alwaysShowHomeXFP, menuWrapping: preferences.menuWrapping,
            sighashWarnOnly: preferences.sighashWarnOnly, network: network,
            seedVaultEnabled: preferences.seedVaultEnabled,
            aeStartIndexEnabled: preferences.aeStartIndexEnabled,
            keyboardEmuEnabled: preferences.keyboardEmuEnabled,
            b85Unlimited: preferences.b85Unlimited,
            usbPortEnabled: preferences.usbPortEnabled,
            nfcSharingEnabled: preferences.nfcSharingEnabled,
            virtualDiskMode: preferences.virtualDiskMode,
            ptxurl: preferences.ptxurl,
            noteGroupCurrent: selectedNoteGroup,
            noteGroups: notes.map(\.group),
            multisig: multisigMenuSnapshot
        ) ?? 0
        jumpMenu(to: selectedMenuIndex)
        errorMessage = nil
        statusMessage = nil
        if menu == .addressExplorer {
            customSingleAddress = false
            addressOverrideAccount = nil
            addressPathTemplate = nil
            addressChange = false
            addressAllowChange = true
            addressPageStart = addressStartIndex
            exploringMultisigIndex = nil
            refreshAddressPreviews()
            restoreAddressExplorerSelection()
        }
    }

    func back() {
        errorMessage = nil
        statusMessage = nil
        if selftestInProgress {
            failSelftest(selftestExpectedKey != nil ? QSelftest.keyboardAbortReason : selftestAbortReason)
            return
        }
        if screen == .factoryBagged || screen == .factoryDFU { return }
        textEntryIsNickname = false
        textEntryIsPushtxURL = false
        if screen == .menu, currentMenu == .listedFiles { pickingPushTxn = false }
        textEntryIsNoteGroup = false
        textEntryIsKeyboardTest = false
        textEntryIsBKPWOverride = false
        textEntryIsNotesImportPassword = false
        textEntryIsCustomBackupPassword = false
        textEntryIsWIF = false
        textEntryIsNFCSeed = false
        textEntryIsNFCTools = false
        nfcReadGeneration += 1
        teleportTextKind = .none
        if screen == .menu, currentMenu == .listedFiles { listedFilesAreNFCShare = false; listedFilesAreNotesImport = false }
        if screen == .menu, currentMenu == .readyToSignFiles { listedDiskFiles = [] }
        if screen == .nfcReceive { nfcReceiveNeedsStandIn = false }
        renamingVaultSeedID = nil
        if renamingMultisigIndex != nil, screen == .passphrase { renamingMultisigIndex = nil }
        if screen == .poweredOff { return }
        if maybeRemindCCCVaultOnBack() { return }
        if screen == .story, story.onConfirm == .listedFileRestoreDetail {
            presentListedFileDetail()
            return
        }
        if screen == .nicknameSplash {
            dismissNicknameSplash()
            return
        }
        if screen == .typePasswordConfirm {
            cancelTypePasswordConfirm()
            return
        }
        if screen == .typePasswordIndex {
            clearTypePasswordState()
        }
        if screen == .wordEntry, SeedCreation.confirmAbortWordEntry(filledCount: wordEntryFilledCount) {
            let action: StoryConfirmAction = wordEntryPurpose == .xorPart ? .xorAbortRestore : .abortWordEntry
            showStory(title: SeedCreation.confirmTitle, body: SeedCreation.wordEntryAbort, onConfirm: action)
            return
        }
        if screen == .wordEntry, wordEntryPurpose == .xorPart, !xorEntropyParts.isEmpty {
            presentXORPartStatus()
            return
        }
        if screen == .unlock {
            applyUnlockPINCancel()
            return
        }
        if screen == .entropyCollect {
            returnToEntropyMethodMenu()
            return
        }
        if screen == .diceRoll {
            if SeedCreation.diceOnlyCancelExits(count: diceRolls.count) {
                if diceForPaperWallet {
                    returnToPaperWalletsMenu(selecting: 2)
                } else {
                    abortPendingSeedFlow()
                }
            }
            return
        }
        if handlePaperWalletBack() { return }
        if screen == .story, story.onConfirm == .entropyBiasRetry {
            returnToEntropyMethodMenu()
            return
        }
        if screen == .story, story.onConfirm == .abortDice {
            abortPendingSeedFlow()
            return
        }
        if screen == .story, story.onConfirm == .throwAwayWords, throwAwayRestartsQuiz {
            story.onConfirm = nil
            wordQuiz = nil
            throwAwayRestartsQuiz = false
            if history.last == .story { _ = history.popLast() }
            if history.last == .wordQuiz { _ = history.popLast() }
            screen = .seedWords
            selectedMenuIndex = 0
            return
        }
        if screen == .wordQuiz, xorQuizzingSplit {
            wordQuiz = nil
            xorQuizzingSplit = false
            xorQuizPartIndex = 0
            presentXORSplitParts(checksum: xorChecksumWord)
            return
        }
        if screen == .story, story.onConfirm == .xorStopForgetSplit {
            presentXORSplitParts(checksum: xorChecksumWord)
            return
        }
        if screen == .story, story.onConfirm == .xorAbortRestore {
            if xorEntropyParts.isEmpty {
                leaveXORFlowToMenu()
            } else {
                presentXORPartStatus()
            }
            return
        }
        if screen == .story, story.onConfirm == .xorShowParts {
            if xorUsedRNG {
                showStory(title: "Are you SURE ?!?", body: SeedXORStories.stopAndForget, onConfirm: .xorStopForgetSplit)
                return
            }
            leaveXORFlowToMenu()
            return
        }
        if screen == .story, story.onConfirm == .xorRestoreMore, !xorEntropyParts.isEmpty {
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.throwAwayWords, onConfirm: .xorAbortRestore)
            return
        }
        if screen == .menu, currentMenu == .xorVaultPick {
            cancelXORVaultPick()
            return
        }
        if screen == .wordQuiz, pendingMnemonic != nil {
            throwAwayRestartsQuiz = true
            showStory(title: SeedCreation.confirmTitle, body: FirmwareCopy.throwAwayQuiz, onConfirm: .throwAwayWords)
            return
        }
        if screen == .seedWords, pendingMnemonic != nil {
            throwAwayRestartsQuiz = false
            showStory(title: SeedCreation.confirmTitle, body: FirmwareCopy.throwAwayWords, onConfirm: .throwAwayWords)
            return
        }
        if screen == .story, story.onConfirm == .continueRiskyPIN {
            // Firmware logs out when the risky-attempt warning is cancelled (`login.py` `show_logout`).
            story.onConfirm = nil
            pinInput = ""
            pinPrefix = ""
            unlockPhase = .prefix
            powerOffFromLogin()
            return
        }
        if screen == .story, story.onConfirm == .continueToggleChooser {
            // Firmware `ToggleMenuItem.activate`: X returns before the chooser opens.
            pendingToggleMenu = nil
            story.onConfirm = nil
            if let previous = history.popLast() { screen = previous }
            selectedMenuIndex = 0
            return
        }
        if screen == .story, story.onConfirm == .continuePushtxSetup
            || story.onConfirm == .enableNFCForFeature {
            story.onConfirm = nil
            if let previous = history.popLast() { screen = previous }
            selectedMenuIndex = 0
            return
        }
        if screen == .story, story.onConfirm == .confirmNoteEdits {
            // Firmware: refusing the save-changes confirmation aborts the edit (notes.py).
            story.onConfirm = nil
            if let previous = history.popLast() { screen = previous }
            statusMessage = "Not saved. Change aborted."
            return
        }
        if screen == .story, story.onConfirm == .deleteNote {
            // Cancelling the delete confirmation must clear the pending flag ("Aborted.", notes.py).
            story.onConfirm = nil
            pendingNoteDelete = false
            popStoryAndPauseAborted(seconds: FirmwareBusyTitle.abortedLongSeconds)
            return
        }
        if screen == .story, story.onConfirm == .confirmRestoreBackup {
            story.onConfirm = nil
            pendingRestorePayload = nil
            pendingBackupRestoreData = nil
            popStoryAndPauseAborted(seconds: FirmwareBusyTitle.abortedSeconds)
            return
        }
        if screen == .story, story.onConfirm == .lockDownSeed
            || story.onConfirm == .destroySeed
            || story.onConfirm == .destroySeedAgain {
            story.onConfirm = nil
            popStoryAndPauseAborted(seconds: FirmwareBusyTitle.abortedSeconds)
            return
        }
        if screen == .story, story.onConfirm == .cccRemoveFunds {
            story.onConfirm = nil
            popStoryAndPauseAborted(seconds: FirmwareBusyTitle.abortedSeconds)
            return
        }
        if screen == .story, story.onConfirm == .confirmDeleteMultisig {
            story.onConfirm = nil
            popStoryAndPauseAborted(seconds: FirmwareBusyTitle.abortedLongSeconds)
            return
        }
        if screen == .story, story.onConfirm == .cloneIngestPickFile {
            abortCloneIngest()
        }
        if screen == .story, story.onConfirm == .tapsignerImportSource || story.onConfirm == .tapsignerHaveCard {
            pendingTapsignerCiphertext = nil
            pendingTapsignerOrigin = ""
        }
        if screen == .hexEntry {
            pendingTapsignerCiphertext = nil
            pendingTapsignerOrigin = ""
            hexEntryText = ""
        }
        if screen == .story, story.onConfirm == .uxAborted {
            abortWithFirmwarePause()
            return
        }
        if screen == .story, story.onConfirm == .deleteVaultSeedConfirm {
            pendingVaultDeleteID = nil
            pendingVaultDeleteIsActive = false
        }
        if screen == .story, story.onConfirm == .backupFirstCopyWritten || story.onConfirm == .backupMoreCopies {
            clearPendingBackupExport()
        }
        if screen == .story, story.onConfirm == .notesCustomPassword {
            pendingEncryptedNotesData = nil
        }
        if screen == .story, story.onConfirm == .batchSignConfirm {
            // Firmware `_batch_sign`: CANCEL (`ch == "x"`) breaks the loop and returns.
            quitBatchSign()
            return
        }
        if screen == .story, story.onConfirm == .batchSignAfterExport {
            // Firmware `done_signing`: CANCEL on the filename prompt returns to `_batch_sign`,
            // which shows the next `ux_show_story` in the same loop.
            continueBatchAfterSignedExport()
            return
        }
        if screen == .psbtSigned {
            if batchSignCallerDepth != nil {
                continueBatchAfterSignedExport()
            } else {
                resetPSBTFlow()
            }
            return
        }
        if screen == .story, story.onConfirm == .keyTeleportShowPayload, teleportFromSignedPSBT {
            noteSignedTeleportResult(success: true, remaining: teleportRemainingSigs)
            return
        }
        if screen == .story, story.onConfirm == .reuseBackupPassword {
            // Declining the cached backup password falls through to a fresh one, as in firmware.
            story.onConfirm = nil
            if let previous = history.popLast() { screen = previous }
            generateNewBackupPassword()
            return
        }
        if screen == .story, story.onConfirm == .continueDiceRolling {
            // CANCEL on the low-entropy dice story exits the whole dice flow (`seed.py`).
            story.onConfirm = nil
            if diceForPaperWallet {
                returnToPaperWalletsMenu(selecting: 2)
                return
            }
            while let previous = history.popLast() {
                if previous == .diceRoll { continue }
                if previous == .menu {
                    currentMenu = menuStack.popLast() ?? rootMenu
                    screen = .menu
                } else {
                    screen = previous
                }
                selectedMenuIndex = 0
                return
            }
            openMenu(rootMenu, remember: false)
            return
        }
        if screen == .menu, currentMenu == .noteGroupPicker {
            // Firmware `GroupPickerMenu.pick`: CANCEL leaves the previous group and continues save.
            pickNoteGroup(noteGroupDraft)
            return
        }
        if let previous = history.popLast() {
            if previous == .menu {
                currentMenu = menuStack.popLast() ?? rootMenu
                screen = .menu
            } else {
                screen = previous
            }
        } else if isUnlocked {
            openMenu(.home, remember: false)
        } else {
            goToLockedRoot()
        }
        selectedMenuIndex = 0
    }

    var rootMenu: FirmwareMenu {
        if isFactoryMode { return .factory }
        if isUnlocked { return .home }
        if hasSeed { return .home }
        if hasPIN { return .emptyWallet }
        return .virgin
    }

    func goToLockedRoot(showNickname: Bool = true) {
        history.removeAll()
        menuStack.removeAll()
        if record == nil {
            presentFirstBoot()
            return
        }
        if isBricked {
            enterBrickedState()
            return
        }
        if LoginUX.bootShowsNickname(beforeCalculatorLogin: preferences.calculatorLogin, nickname: nickname),
           showNickname {
            screen = .nicknameSplash
            return
        }
        if preferences.calculatorLogin {
            resetCalculatorDisplay()
            screen = .calculator
        } else {
            screen = .unlock
            unlockPhase = .prefix
            pinPrefix = ""
            pinInput = ""
            if LoginUX.shouldShuffleKeypad(
                randomize: preferences.scrambleKeys, startingInteract: true, acceptedPrefix: false, isQwerty: true
            ) {
                refreshScrambleMap()
            } else {
                scrambleDigitMap = [:]
            }
        }
    }

    func presentFirstBoot() {
        applyFactoryStandInFromDefaults()
        history.removeAll()
        menuStack.removeAll()
        if isFactoryMode {
            currentMenu = .factory
            screen = .menu
            selectedMenuIndex = 0
            if !preferences.tested {
                runSelfTests()
            }
            return
        }
        currentMenu = .virgin
        if UserDefaults.standard.bool(forKey: Self.termsAcceptedDefaultsKey) {
            screen = .menu
            return
        }
        story = StoryPresentation(title: "", body: FirmwareCopy.termsOfSale, onConfirm: .acceptTerms)
        screen = .story
    }

    func dismissNicknameSplash() {
        goToLockedRoot(showNickname: false)
    }

    /// Q `show_logout` / `clean_shutdown` default: power down until the power key.
    func powerOffFromLogin() {
        history.removeAll()
        menuStack.removeAll()
        screen = .poweredOff
        selectedMenuIndex = 0
    }

    /// Firmware `login_now` / `clean_shutdown(2)`: wipe RAM and reboot into login.
    func testLoginNow() {
        lock()
    }

    func createOfficialDemoWallet() {
        do {
            let mnemonic = try BIP39Mnemonic(phrase: Self.officialSimulatorMnemonic)
            pendingMnemonic = mnemonic
            pendingNotes = []
            settingsNickname = ""
            settingsNetwork = .testnet
            try commitPendingWallet(pin: "12-12")
            if applyFirstTimeUXHardwareDefaultsIfNeeded() {
                persistPreferencesQuietly()
            }
            showStory(title: "Demo Wallet Ready", body: "The official simulator's deterministic wallet is loaded on Bitcoin Testnet 4. PIN: 12-12. This item does not exist on a real Coldcard. Never send real funds to this public wallet.")
        } catch { present(error) }
    }

    func createNewSeed(wordCount: Int, ephemeral: Bool = false) {
        do {
            pendingEphemeral = ephemeral
            entropyWordCount = wordCount
            pendingBaseSeed = try SecureRandom.bytes(count: 32)
            ephemeralOrigin = SeedCreation.ephemeralOrigin(diceOnly: false)
            Task { @MainActor in
                await dramaticPause(SeedCreation.generatingPauseTitle, seconds: SeedCreation.generatingPauseSeconds)
                openMenu(.userEntropy)
            }
        } catch { present(error) }
    }

    func startDice(wordCount: Int, ephemeral: Bool = false, mixWithTRNG: Bool = false) {
        pendingEphemeral = ephemeral
        diceMixesWithTRNG = mixWithTRNG
        diceWordCount = wordCount
        entropyWordCount = wordCount
        diceRolls = ""
        if !mixWithTRNG {
            ephemeralOrigin = SeedCreation.ephemeralOrigin(diceOnly: true)
        }
        if mixWithTRNG, pendingBaseSeed.isEmpty {
            pendingBaseSeed = (try? SecureRandom.bytes(count: 32)) ?? Data()
        }
        let warning = FirmwareCopy.diceEntropyWarning(mixWithTRNG: mixWithTRNG)
        showStory(title: warning.title, body: warning.body, onConfirm: .continueDice)
    }

    func addDiceRoll(_ digit: Character) {
        guard "123456".contains(digit) else { return }
        diceRolls.append(digit)
    }

    func finishDiceRolls() {
        if diceForPaperWallet {
            if diceRolls.isEmpty {
                returnToPaperWalletsMenu(selecting: 2)
                return
            }
            finishPaperWalletDice()
            return
        }
        if diceMixesWithTRNG {
            guard SeedCreation.canFinishDiceMix(count: diceRolls.count) else { return }
            if SeedCreation.diceRollsAreBiased(diceRolls) {
                presentMixBias(SeedCreation.badDiceMessage)
                return
            }
            Task { @MainActor in
                await dramaticPause(SeedCreation.waitPauseTitle, seconds: SeedCreation.waitPauseSeconds)
                commitDiceSeed()
            }
            return
        }
        if diceRolls.isEmpty {
            abortPendingSeedFlow()
            return
        }
        let needed = diceWordCount == 24 ? 99 : 50
        let bits = diceWordCount == 24 ? 256 : 128
        guard diceRolls.count >= needed else {
            showStory(
                title: "",
                body: SeedCreation.diceOnlyNotEnough(
                    count: diceRolls.count, bits: bits, words: diceWordCount, needed: needed
                ),
                onConfirm: .continueDiceRolling
            )
            return
        }
        if SeedCreation.diceRollsAreBiased(diceRolls) {
            showStory(title: SeedCreation.biasStoryTitle, body: SeedCreation.badDiceMessage, onConfirm: .abortDice)
            return
        }
        commitDiceSeed()
    }

    private func presentMixBias(_ body: String) {
        showStory(title: SeedCreation.biasStoryTitle, body: body, onConfirm: .entropyBiasRetry)
    }

    private func returnToEntropyMethodMenu() {
        diceRolls = ""
        coinFlips = ""
        mashCount = 0
        mashDigest = Data()
        history.removeAll { $0 == .entropyCollect || $0 == .story }
        openMenu(.userEntropy, remember: false)
    }

    private func commitDiceSeed() {
        do {
            let extra = SHA2.sha256(Self.entropyDomain("D") + Data(diceRolls.utf8))
            let entropy: Data
            if diceMixesWithTRNG {
                entropy = try mixedEntropy(method: Data("D".utf8), extra: extra)
            } else {
                entropy = Data(SHA2.sha256(Data(diceRolls.utf8)).prefix(diceWordCount == 24 ? 32 : 16))
            }
            pendingMnemonic = try BIP39Mnemonic(entropy: entropy)
            pendingNotes = record?.notes ?? []
            seedAcknowledged = false
            navigate(to: .seedWords)
        } catch { present(error) }
    }

    private static func entropyDomain(_ method: String) -> Data {
        Data("CC".utf8) + Data([0x01]) + Data(method.utf8)
    }

    private func mixedEntropy(method: Data, extra: Data) throws -> Data {
        if pendingBaseSeed.isEmpty { pendingBaseSeed = try SecureRandom.bytes(count: 32) }
        var mix = Self.entropyDomain("S")
        mix.append(pendingEphemeral ? 0x54 : 0x4D) // T / M
        mix.append(method)
        mix.append(pendingBaseSeed)
        mix.append(extra)
        let digest = SHA2.doubleSHA256(mix)
        let byteCount = entropyWordCount == 24 ? 32 : 16
        return Data(digest.prefix(byteCount))
    }

    func beginMashCollect() {
        mashCount = 0
        mashDigest = Data()
        mashLastTicks = mashTicks()
        entropyKind = .mash
        navigate(to: .entropyCollect)
    }

    func beginCoinCollect() {
        coinFlips = ""
        entropyKind = .coin
        navigate(to: .entropyCollect)
    }

    func mashKey(_ value: String) {
        guard screen == .entropyCollect, entropyKind == .mash else { return }
        guard let scalar = value.unicodeScalars.first, scalar.value < 256 else { return }
        let now = mashTicks()
        let gap = now &- mashLastTicks
        mashLastTicks = now
        var packed = Data()
        packed.append(contentsOf: withUnsafeBytes(of: UInt32(mashCount).littleEndian) { Data($0) })
        packed.append(contentsOf: withUnsafeBytes(of: gap.littleEndian) { Data($0) })
        packed.append(UInt8(truncatingIfNeeded: scalar.value))
        if mashDigest.isEmpty {
            mashDigest = Self.entropyDomain("M")
        }
        mashDigest.append(packed)
        mashCount += 1
        errorMessage = nil
        statusMessage = nil
    }

    func finishMashIfReady() {
        guard SeedCreation.canFinishMash(count: mashCount) else { return }
        Task { @MainActor in
            await dramaticPause(SeedCreation.waitPauseTitle, seconds: SeedCreation.waitPauseSeconds)
            do {
                let extra = SHA2.sha256(mashDigest)
                let entropy = try mixedEntropy(method: Data("M".utf8), extra: extra)
                pendingMnemonic = try BIP39Mnemonic(entropy: entropy)
                pendingNotes = record?.notes ?? []
                seedAcknowledged = false
                navigate(to: .seedWords)
            } catch { present(error) }
        }
    }

    func addCoinFlip(_ value: String) {
        guard value == "0" || value == "1" else { return }
        coinFlips.append(value)
        errorMessage = nil
        statusMessage = nil
    }

    func finishCoinIfReady() {
        guard SeedCreation.canFinishCoin(count: coinFlips.count) else { return }
        if SeedCreation.coinFlipsAreBiased(coinFlips) {
            presentMixBias(SeedCreation.badCoinMessage)
            return
        }
        Task { @MainActor in
            await dramaticPause(SeedCreation.waitPauseTitle, seconds: SeedCreation.waitPauseSeconds)
            do {
                let extra = SHA2.sha256(Self.entropyDomain("C") + Data(coinFlips.utf8))
                let entropy = try mixedEntropy(method: Data("C".utf8), extra: extra)
                pendingMnemonic = try BIP39Mnemonic(entropy: entropy)
                pendingNotes = record?.notes ?? []
                seedAcknowledged = false
                navigate(to: .seedWords)
            } catch { present(error) }
        }
    }

    private func mashTicks() -> UInt32 {
        UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1_000))
    }

    func continueAfterSeedWords() {
        if xorQuizzingSplit, wordQuiz != nil {
            navigate(to: .wordQuiz)
            return
        }
        guard pendingMnemonic != nil else { return }
        if wordQuiz != nil {
            navigate(to: .wordQuiz)
            return
        }
        startWordQuiz(words: pendingMnemonic!.words)
    }

    func reviewSeedWordsFromQuiz() {
        guard wordQuiz != nil else { return }
        navigate(to: .seedWords)
    }

    func requestSkipSeedQuiz() {
        guard pendingMnemonic != nil, !xorQuizzingSplit else { return }
        showStory(title: SeedCreation.confirmTitle, body: FirmwareCopy.skipQuizConfirm, onConfirm: .skipQuiz)
    }

    func skipSeedQuiz() {
        guard pendingMnemonic != nil else { return }
        wordQuiz = nil
        quizWrongPause = false
        seedAcknowledged = true
        finishSeedAcknowledgement()
    }

    func abortPendingSeedFlow() {
        pendingMnemonic = nil
        pendingExtendedKey = nil
        pendingEphemeral = false
        pendingCCCSetup = false
        pendingBaseSeed = Data()
        diceRolls = ""
        wordQuiz = nil
        quizWrongPause = false
        throwAwayRestartsQuiz = false
        seedAcknowledged = false
        history.removeAll { [.seedWords, .wordQuiz, .diceRoll, .story, .entropyCollect, .wordEntry].contains($0) }
        openMenu(rootMenu, remember: false)
    }

    func startWordQuiz(words: [String], backupPassword: Bool = false) {
        quizIsBackupPassword = backupPassword
        var order: [Int]
        if backupPassword, words.count >= 4 {
            var pool = Array(0..<(words.count - 1))
            pool.shuffle()
            order = Array(pool.prefix(3))
            order.append(words.count - 1)
            order.shuffle()
        } else {
            order = Array(words.indices)
            order.shuffle()
        }
        wordQuiz = makeQuizRound(words: words, remaining: order)
        navigate(to: .wordQuiz)
    }

    func answerWordQuiz(_ choice: String) {
        guard let quiz = wordQuiz else { return }
        let words: [String]
        if xorQuizzingSplit, xorWordLists.indices.contains(xorQuizPartIndex) {
            words = xorWordLists[xorQuizPartIndex]
        } else if quizIsBackupPassword {
            words = backupPasswordWords
        } else {
            words = (pendingMnemonic ?? activeMnemonic)?.words ?? []
        }
        guard words.indices.contains(quiz.wordIndex) else { return }
        guard choice == words[quiz.wordIndex] else {
            quizWrongPause = true
            errorMessage = nil
            var shuffled = quiz.choices
            shuffled.shuffle()
            let index = quiz.wordIndex
            let leftover = quiz.remaining
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.quizWrongPause = false
                self.wordQuiz = WordQuizRound(wordIndex: index, choices: shuffled, remaining: leftover)
            }
            return
        }
        let remaining = quiz.remaining
        if remaining.isEmpty {
            wordQuiz = nil
            if xorQuizzingSplit {
                xorQuizPartIndex += 1
                if xorQuizPartIndex < xorWordLists.count {
                    startWordQuiz(words: xorWordLists[xorQuizPartIndex])
                    return
                }
                xorQuizzingSplit = false
                showStory(title: "", body: SeedXORStories.quizPassed)
                return
            }
            seedAcknowledged = true
            finishSeedAcknowledgement()
            return
        }
        wordQuiz = makeQuizRound(words: words, remaining: remaining)
        errorMessage = nil
    }

    private func makeQuizRound(words: [String], remaining: [Int]) -> WordQuizRound {
        var leftover = remaining
        let index = leftover.removeFirst()
        let right = words[index]
        var choices = [right]
        while choices.count < 2 {
            if let other = words.randomElement(), !choices.contains(other) { choices.append(other) }
        }
        while choices.count < 3 {
            if let random = BIP39EnglishWords.all.randomElement(), !choices.contains(random) { choices.append(random) }
        }
        choices.shuffle()
        return WordQuizRound(wordIndex: index, choices: choices, remaining: leftover)
    }

    func finishSeedAcknowledgement() {
        if maybeInitCCCAfterSeedAcknowledgement() { return }
        if quizIsBackupPassword {
            quizIsBackupPassword = false
            showStory(title: "Backup System", body: FirmwareCopy.cacheBackupPassword, onConfirm: .skipBackupCache)
            return
        }
        if pendingEphemeral {
            do { try applyEphemeralSeed() }
            catch { present(error) }
            return
        }
        if pinSetupIsChange {
            navigate(to: .pinSetup)
            return
        }
        if hasPIN, record?.hasSeed == false {
            do { try commitSeedOntoExistingPIN() }
            catch { present(error) }
            return
        }
        if hasSeed, pendingMnemonic == nil {
            back()
            return
        }
        if !hasPIN {
            beginPINSetup(isChange: false)
            return
        }
        do { try commitSeedOntoExistingPIN() }
        catch { present(error) }
    }

    func beginImport(wordCount: Int, ephemeral: Bool = false) {
        pendingEphemeral = ephemeral
        seedWordCount = wordCount
        importSeedText = ""
        ephemeralOrigin = SeedCreation.importedOrigin
        beginWordEntry(purpose: .importSeed, wordCount: wordCount)
    }

    func beginWordEntry(purpose: WordEntryPurpose, wordCount: Int) {
        wordEntryPurpose = purpose
        wordEntryWords = Array(repeating: "", count: wordCount)
        wordEntryPrefix = ""
        wordEntryLastWords = []
        wordEntryHasChecksum = SeedCreation.hasChecksum(seedWordEntryKind)
        wordEntryHint = ""
        errorMessage = nil
        navigate(to: .wordEntry)
    }

    func beginBackupPasswordEntry() {
        beginWordEntry(purpose: .backupPassword, wordCount: 12)
    }

    var wordEntryFilledCount: Int { wordEntryWords.filter { !$0.isEmpty }.count }

    var wordEntryComplete: Bool { wordEntryFilledCount == wordEntryWords.count && wordEntryWords.allSatisfy { !$0.isEmpty } }

    func typeWordEntry(_ value: String) {
        let letter = value.lowercased().filter(\.isLetter)
        guard !letter.isEmpty else {
            if value == " " { commitWordEntry(); return }
            return
        }
        if wordEntryComplete { return }
        let room = SeedCreation.maxWordLength - wordEntryPrefix.count
        guard room > 0 else { return }
        wordEntryPrefix.append(contentsOf: letter.prefix(room))
        tryCompleteCurrentWord(commit: false)
    }

    func setWordEntryPrefixFromField(_ value: String) {
        let clamped = SeedCreation.clampPrefix(value.lowercased())
        if wordEntryPrefix != clamped {
            wordEntryPrefix = clamped
        }
        tryCompleteCurrentWord(commit: false)
    }

    func commitWordEntry() {
        if wordEntryComplete {
            finishWordEntry()
            return
        }
        tryCompleteCurrentWord(commit: true)
    }

    func deleteWordEntryCharacter() {
        if !wordEntryPrefix.isEmpty {
            wordEntryPrefix.removeLast()
            tryCompleteCurrentWord(commit: false)
            return
        }
        if let lastFilled = wordEntryWords.lastIndex(where: { !$0.isEmpty }) {
            wordEntryWords[lastFilled] = ""
            wordEntryHint = ""
            errorMessage = nil
        }
    }

    private func tryCompleteCurrentWord(commit: Bool) {
        guard let index = wordEntryWords.firstIndex(where: \.isEmpty) else {
            setWordEntryBottomLine(error: nil)
            return
        }
        if wordEntryHasChecksum, index == wordEntryWords.count - 1, !wordEntryLastWords.isEmpty,
           !wordEntryPrefix.isEmpty || commit {
            handleLastChecksumWord(index: index)
            return
        }
        if wordEntryPrefix.count >= 2 {
            let prediction = BIP39Mnemonic.predict(prefix: wordEntryPrefix)
            if let completed = prediction.completedWord, prediction.nextCharacters.isEmpty {
                acceptWordEntry(completed, at: index)
                return
            }
            if commit, let exact = prediction.completedWord {
                acceptWordEntry(exact, at: index)
                return
            }
            if prediction.nextCharacters.isEmpty, prediction.completedWord == nil {
                setWordEntryBottomLine(error: "Not a BIP-39 word: \(wordEntryPrefix)")
                wordEntryPrefix = String(wordEntryPrefix.prefix(3))
                return
            }
            setWordEntryBottomLine(error: "Next key: \(prediction.nextCharacters)")
            return
        }
        if commit, wordEntryPrefix.count >= 3 {
            let matches = BIP39EnglishWords.all.filter { $0.hasPrefix(wordEntryPrefix) }
            if matches.count == 1 {
                acceptWordEntry(matches[0], at: index)
                return
            }
            if matches.contains(wordEntryPrefix) {
                acceptWordEntry(wordEntryPrefix, at: index)
                return
            }
        }
        setWordEntryBottomLine(error: nil)
    }

    private func handleLastChecksumWord(index: Int) {
        let value = wordEntryPrefix
        if wordEntryLastWords.contains(value) {
            acceptWordEntry(value, at: index)
            return
        }
        let maybe = wordEntryLastWords.filter { $0.hasPrefix(value) }
        if maybe.count == 1 {
            acceptWordEntry(maybe[0], at: index)
            return
        }
        if maybe.isEmpty {
            setWordEntryBottomLine(error: SeedCreation.finalWordError(prefix: value, candidates: wordEntryLastWords))
            if !wordEntryPrefix.isEmpty { wordEntryPrefix.removeLast() }
            return
        }
        setWordEntryBottomLine(error: SeedCreation.nextKeyHint(matches: maybe, prefix: value))
    }

    private func acceptWordEntry(_ word: String, at index: Int) {
        wordEntryWords[index] = word
        wordEntryPrefix = ""
        if wordEntryHasChecksum, index == wordEntryWords.count - 2 {
            wordEntryLastWords = BIP39Mnemonic.checksumCandidates(
                precedingWords: Array(wordEntryWords.dropLast())
            )
        }
        setWordEntryBottomLine(error: nil)
    }

    private func setWordEntryBottomLine(error: String?) {
        wordEntryHint = SeedCreation.bottomLine(
            complete: wordEntryComplete,
            hasChecksum: wordEntryHasChecksum,
            error: error
        )
        errorMessage = nil
    }

    func refreshWordEntryHint() {
        tryCompleteCurrentWord(commit: false)
    }

    private func finishWordEntry() {
        let words = wordEntryWords.filter { !$0.isEmpty }
        switch wordEntryPurpose {
        case .importSeed:
            importSeedText = words.joined(separator: " ")
            validateImportedSeed()
        case .backupPassword:
            backupPasswordWords = words
            backupPassword = words.joined(separator: " ")
            backupConfirmPassword = backupPassword
            if pendingEncryptedNotesData != nil {
                decryptAndImportNotes()
            } else if pendingBackupRestoreData != nil {
                decryptPendingRestore()
            } else {
                showFileImporter = true
            }
        case .notesImportPassword:
            backupPassword = words.joined(separator: " ")
            decryptAndImportNotes()
        case .xorPart:
            finishXORPart(words: words)
        case .ssspFirstLast:
            finishSSSPWordChallenge(words: words)
        case .cccKeyC, .cccChallenge:
            finishCCCWordEntry(words: words, purpose: wordEntryPurpose)
        }
    }

    func validateImportedSeed() {
        do {
            let trimmed = importSeedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let mnemonic: BIP39Mnemonic
            if trimmed.allSatisfy(\.isNumber) { mnemonic = try BIP39Mnemonic.fromSeedQR(trimmed) }
            else { mnemonic = try BIP39Mnemonic(phrase: trimmed) }
            guard [12, 18, 24].contains(mnemonic.words.count) else {
                errorMessage = "Firmware import offers 12, 18, or 24 words."
                return
            }
            if seedWordCount > 0, mnemonic.words.count != seedWordCount {
                errorMessage = "Must be seed of length \(seedWordCount), not \(mnemonic.words.count)"
                return
            }
            pendingMnemonic = mnemonic
            pendingNotes = record?.notes ?? []
            seedAcknowledged = true
            if pendingEphemeral {
                try applyEphemeralSeed()
            } else if hasPIN { try commitSeedOntoExistingPIN() }
            else { beginPINSetup(isChange: false) }
        } catch { errorMessage = "Invalid seed: \(error.localizedDescription)" }
    }

    func beginPINSetup(isChange: Bool) {
        pinSetupPurpose = isChange ? .changeMain : .wallet
        pinSetupIsChange = isChange
        pinSetupCollectingOld = false
        pinSetupPhase = .warning
        pinPrefix = ""
        pinInput = ""
        setupPIN = ""
        confirmPIN = ""
        firstPINValue = ""
        if isChange {
            showStory(title: "Main PIN", body: FirmwareCopy.changeMainPIN, onConfirm: .beginChangePINOld)
        } else {
            showStory(title: "Choose PIN", body: FirmwareCopy.choosePIN, onConfirm: .continuePINWarning)
        }
    }

    func advancePINSetup() {
        switch pinSetupPhase {
        case .warning:
            pinSetupPhase = .proveRead
            errorMessage = nil
        case .proveRead:
            return
        case .prefix:
            // Firmware silently ignores too-short parts (login.py).
            guard (2...6).contains(pinPrefix.count), pinPrefix.allSatisfy(\.isNumber) else { return }
            pinSetupPhase = .suffix
            pinInput = ""
        case .suffix:
            guard (2...6).contains(pinInput.count), pinInput.allSatisfy(\.isNumber) else { return }
            if pinSetupCollectingOld {
                verifyOldPINForChange()
                return
            }
            firstPINValue = pinPrefix + "-" + pinInput
            pinPrefix = ""
            pinInput = ""
            pinSetupPhase = .confirmPrefix
        case .confirmPrefix:
            guard (2...6).contains(pinPrefix.count) else { return }
            pinSetupPhase = .confirmSuffix
            pinInput = ""
        case .confirmSuffix:
            let repeated = pinPrefix + "-" + pinInput
            guard repeated == firstPINValue else {
                showStory(title: "PIN Mismatch", body: FirmwareCopy.pinMismatch, onConfirm: .retryPINConfirm, confirmCode: "2")
                return
            }
            completePINSetup(pin: repeated)
        }
    }

    func completePINSetup(pin: String? = nil) {
        let value = pin ?? setupPIN
        do {
            if pinSetupPurpose == .ssspBypass {
                finishSSSPBypassPIN(value)
                return
            }
            if pinSetupPurpose == .trickNew {
                finishProposedTrickPIN(value)
                return
            }
            if pinSetupPurpose == .trickChange {
                finishChangeTrickPIN(value)
                return
            }
            if pinSetupIsChange {
                guard isValidPIN(value) else { throw SimulatorInputError.invalidPIN }
                if presentMainPINTrickConflictIfNeeded(value) { return }
                try updatePIN(value)
                noteMainPINChanged(value)
                history.removeAll()
                openMenu(.loginSettings, remember: false)
                statusMessage = "Main PIN changed."
                return
            }
            // Firmware `goto_top_menu(first_time=True)` only after a first seed, not PIN-only.
            if pendingMnemonic != nil {
                try commitPendingWallet(pin: value)
            } else if pendingExtendedKey != nil {
                try commitPendingXPRV(pin: value)
            } else {
                try commitPINOnly(pin: value)
            }
            sessionPIN = value
            restorePendingTrickPinsIfNeeded()
            presentFirstTimeUXIfNeeded()
        } catch { present(error) }
    }

    /// Firmware `ftux.FirstTimeUX` on hardware: if `du` is unset, set `du=1` (USB off),
    /// then NFC/VD off. The unix simulator skipping `du=1` is not the Q device.
    @discardableResult
    private func applyFirstTimeUXHardwareDefaultsIfNeeded() -> Bool {
        let current = FirstTimeUX.HardwarePorts(
            du: preferences.du,
            usbEnabled: preferences.usbPortEnabled,
            nfcEnabled: preferences.nfcSharingEnabled,
            virtualDiskMode: preferences.virtualDiskMode
        )
        guard let next = FirstTimeUX.applyHardwareDefaultsIfNeeded(current) else { return false }
        preferences.du = next.du
        preferences.usbPortEnabled = next.usbEnabled
        preferences.nfcSharingEnabled = next.nfcEnabled
        preferences.virtualDiskMode = next.virtualDiskMode
        return true
    }

    private func presentFirstTimeUXIfNeeded() {
        guard FirstTimeUX.shouldPresent(hasSeed: record?.hasSeed == true, du: preferences.du) else { return }
        guard applyFirstTimeUXHardwareDefaultsIfNeeded() else { return }
        persistPreferencesQuietly()
        showStory(title: FirstTimeUX.welcomeTitle, body: FirstTimeUX.story)
    }

    func confirmPINWarningRead() {
        guard pinSetupPhase == .proveRead else { return }
        pinSetupPhase = .prefix
    }

    private func verifyOldPINForChange() {
        let pin = pinPrefix + "-" + pinInput
        guard let record, SHA2.sha256(record.pinSalt + Data(pin.utf8)) == record.pinHash else {
            // Firmware aborts the whole change flow on a wrong existing PIN (actions.py incorrect_pin).
            pinPrefix = ""
            pinInput = ""
            pinSetupCollectingOld = false
            pinSetupIsChange = false
            pinSetupPhase = .warning
            history.removeAll()
            menuStack.removeAll()
            openMenu(.loginSettings, remember: false)
            showStory(title: "Wrong PIN", body: FirmwareCopy.wrongOldPIN)
            return
        }
        pinSetupCollectingOld = false
        pinPrefix = ""
        pinInput = ""
        pinSetupPhase = .prefix
        errorMessage = nil
        statusMessage = nil
    }

    func enterBrickedState() {
        let alreadyBricked = isBricked
        isBricked = true
        persistPINAttempts()
        errorMessage = nil
        resetCalculatorDisplay()
        calculatorResult = FirmwareCopy.brickCalculator
        // Boot / already-bricked: `pa.enforce_brick` goes straight to the calculator REPL.
        // Fresh brick: `we_are_ewaste` story, then any key except (6) enters the REPL.
        if alreadyBricked {
            screen = .calculator
        } else {
            screen = .brick
        }
    }

    func openBrickedCalculator() {
        resetCalculatorDisplay()
        calculatorResult = FirmwareCopy.brickCalculator
        screen = .calculator
    }

    func unlock() {
        guard record != nil else { openMenu(.virgin, remember: false); return }
        switch unlockPhase {
        case .prefix:
            // Firmware silently ignores too-short parts (login.py).
            guard (2...6).contains(pinInput.count), pinInput.allSatisfy(\.isNumber) else { return }
            pinPrefix = pinInput
            pinInput = ""
            beginGPUBusyBar()
            _ = antiPhishingWords(for: pinPrefix)
            endWorking()
            unlockPhase = .suffix
            if LoginUX.shouldShuffleKeypad(
                randomize: preferences.scrambleKeys, startingInteract: false, acceptedPrefix: true, isQwerty: true
            ) {
                refreshScrambleMap()
            }
        case .suffix:
            let pin = pinPrefix + "-" + pinInput
            if failedPINAttempts > 3 {
                story = StoryPresentation(
                    title: "WARNING",
                    body: """
                    You have \(Self.maxPINAttempts - failedPINAttempts) attempts left before this Coldcard BRICKS ITSELF FOREVER.

                    Check and double-check your entry:

                      \(pin)

                    Maybe even take a break and come back later.

                    Press ENTER to continue, CANCEL to stop for now.
                    """,
                    onConfirm: .continueRiskyPIN
                )
                unlockPhase = .confirmRiskyAttempt
                navigate(to: .story)
                return
            }
            attemptUnlock(pin: pin)
        case .confirmRiskyAttempt:
            attemptUnlock(pin: pinPrefix + "-" + pinInput)
        }
    }

    func attemptUnlock(pin: String) {
        if isBricked {
            enterBrickedState()
            return
        }
        guard let record else { return }
        let enteredHash = SHA2.sha256(record.pinSalt + Data(pin.utf8))
        if awaitingMainPINAfterBypass {
            guard enteredHash == record.pinHash else {
                failUnlockPIN()
                return
            }
            completeBypassUnlockAfterMainPIN()
            return
        }
        if enteredHash == record.pinHash {
            sessionPIN = pin
            deltaModeActive = false
            blankWalletSession = false
            completeMainPINUnlock(record: record)
            return
        }
        if applyNamedTrickLogin(pin: pin) { return }
        if matchesBypassPIN(pin) {
            handleBypassPINLogin()
            return
        }
        failUnlockPIN()
    }

    func completeMainPINUnlock(record: StoredWalletRecord) {
        do {
            pinInput = ""; pinPrefix = ""
            failedPINAttempts = 0
            persistPINAttempts()
            unlockPhase = .prefix
            if preferences.loginCountdownMinutes > 0, !awaitingPostCountdownPIN {
                awaitingPostCountdownPIN = true
                startLoginCountdown()
                return
            }
            awaitingPostCountdownPIN = false
            if record.hasSeed {
                if !record.mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    activeMnemonic = try BIP39Mnemonic(phrase: record.mnemonic)
                } else {
                    activeMnemonic = nil
                }
                activePassphrase = ""
                passphraseInput = ""
                try rebuildRoot()
                if gateMicroSD2FALogin() { return }
                finishUnlockedSession(home: true)
            } else {
                finishUnlockedSession(home: false)
            }
            syncVirtualDiskMonitor()
        } catch { present(error) }
    }

    func failUnlockPIN(applyCatchall: Bool = true) {
        failedPINAttempts += 1
        persistPINAttempts()
        pinInput = ""
        pinPrefix = ""
        unlockPhase = .prefix
        if LoginUX.shouldShuffleKeypad(
            randomize: preferences.scrambleKeys, startingInteract: true, acceptedPrefix: false, isQwerty: true
        ) {
            refreshScrambleMap()
        }
        if failedPINAttempts >= Self.maxPINAttempts {
            enterBrickedState()
            return
        }
        if applyCatchall, applyWrongPINCatchall() { return }
        let left = Self.maxPINAttempts - failedPINAttempts
        showStory(title: "WRONG PIN", body: "\(left) attempts left\n\nPlease check all digits carefully, and that prefix versus suffix break point is correct.\n\n\(failedPINAttempts) failure\(failedPINAttempts == 1 ? "" : "s")")
    }

    private func gateMicroSD2FALogin() -> Bool {
        if preferences.sd2faNonces.isEmpty { return false }
        if authorizedMicroSD2FAPresent() { return false }
        if hasMicroSD2FAFileOnDisk() {
            wipeSeedForMicroSD2FA()
            return true
        }
        pendingMicroSD2FALogin = true
        importPurpose = .microSD2FA
        showFileImporter = true
        return true
    }

    func finishUnlockedSession(home: Bool) {
        history.removeAll()
        menuStack.removeAll()
        if isFactoryMode {
            openMenu(.factory, remember: false)
        } else if home {
            openMenu(.home, remember: false)
            applyHobbledAfterUnlock()
            presentFirstTimeUXIfNeeded()
        } else {
            openMenu(.emptyWallet, remember: false)
        }
        startIdleWatch()
        syncVirtualDiskMonitor()
    }

    func handleFileImporterFailure(_ error: Error) {
        let gated = pendingMicroSD2FALogin || pendingMicroSD2FACheck
        noteFileImporterDismissed()
        if gated { return }
        if error is CancellationError { return }
        let cocoa = error as NSError
        if cocoa.domain == NSCocoaErrorDomain, cocoa.code == NSUserCancelledError { return }
        errorMessage = error.localizedDescription
    }

    func noteFileImporterDismissed() {
        // Yield so a successful pick in the same turn can clear the pending flags first.
        Task { @MainActor in
            await Task.yield()
            guard !showFileImporter else { return }
            if pendingMicroSD2FALogin {
                pendingMicroSD2FALogin = false
                wipeSeedForMicroSD2FA()
                return
            }
            if pendingMicroSD2FACheck {
                pendingMicroSD2FACheck = false
                showStory(title: MicroSD2FA.checkFailTitle, body: MicroSD2FA.checkFail)
            }
        }
    }

    private func beginMicroSD2FAEnroll() {
        let count = preferences.sd2faNonces.count
        if count > 0, authorizedMicroSD2FAPresent() {
            showStory(title: "", body: MicroSD2FA.alreadyEnrolled)
            return
        }
        showStory(title: "", body: MicroSD2FA.enrollConfirm(existingCount: count), onConfirm: .enrollMicroSD2FA)
    }

    private func enrollMicroSD2FACard() {
        do {
            let key = try microSD2FAKey()
            let nonce = MicroSD2FA.nonceHex(from: try SecureRandom.bytes(count: 8))
            let token = try MicroSD2FA.sealToken(nonce: nonce, key: key)
            try writeMicroSD2FAToken(token)
            preferences.sd2faNonces.append(nonce)
            persistPreferencesQuietly()
            statusMessage = MicroSD2FA.saved
        } catch {
            showStory(title: "", body: MicroSD2FA.needsCard)
        }
    }

    private func checkMicroSD2FACard() {
        if authorizedMicroSD2FAPresent() {
            showStory(title: MicroSD2FA.checkPassTitle, body: MicroSD2FA.checkPass)
            return
        }
        if hasMicroSD2FAFileOnDisk() {
            showStory(title: MicroSD2FA.checkFailTitle, body: MicroSD2FA.checkFail)
            return
        }
        pendingMicroSD2FACheck = true
        importPurpose = .microSD2FA
        showFileImporter = true
    }

    private func removePendingMicroSD2FACard() {
        guard let nonce = pendingMicroSD2FARemoveNonce else { return }
        pendingMicroSD2FARemoveNonce = nil
        preferences.sd2faNonces = MicroSD2FA.removing(nonce, from: preferences.sd2faNonces)
        persistPreferencesQuietly()
    }

    private func handleMicroSD2FAPickedFile(_ data: Data) {
        if pendingMicroSD2FALogin {
            pendingMicroSD2FALogin = false
            do {
                let key = try microSD2FAKey()
                if MicroSD2FA.authorizedCardPresent(fileData: data, enrolledNonces: preferences.sd2faNonces, key: key) {
                    try? writeMicroSD2FAToken(data)
                    finishUnlockedSession(home: record?.hasSeed == true)
                    return
                }
            } catch { }
            wipeSeedForMicroSD2FA()
            return
        }
        if pendingMicroSD2FACheck {
            pendingMicroSD2FACheck = false
            let ok = (try? microSD2FAKey()).map {
                MicroSD2FA.authorizedCardPresent(fileData: data, enrolledNonces: preferences.sd2faNonces, key: $0)
            } ?? false
            if ok {
                showStory(title: MicroSD2FA.checkPassTitle, body: MicroSD2FA.checkPass)
            } else {
                showStory(title: MicroSD2FA.checkFailTitle, body: MicroSD2FA.checkFail)
            }
        }
    }

    private func wipeSeedForMicroSD2FA() {
        preferences.sd2faNonces = []
        if var record {
            record.mnemonic = ""
            record.extendedPrivateKey = nil
            record.notes = []
            self.record = record
        }
        rootKey = nil
        activeMnemonic = nil
        ephemeralPhrase = nil
        ephemeralXPRV = nil
        pendingEphemeral = false
        pendingExtendedKey = nil
        activePassphrase = ""
        try? persistRecord()
        goToLockedRoot(showNickname: false)
        showStory(title: MicroSD2FA.seedWipedTitle, body: MicroSD2FA.seedWipedBody + "\n\n" + FirmwareCopy.microSD2FASimulatorNote)
    }

    private func microSD2FAKey() throws -> Data {
        try MicroSD2FA.encryptionKey(root: masterHDKeyForMicroSD2FA(), salt: MicroSD2FA.documentsCardSalt)
    }

    private func masterHDKeyForMicroSD2FA() throws -> HDKey {
        guard let record else { throw SimulatorInputError.missingSeed }
        if let xprv = record.extendedPrivateKey, !xprv.isEmpty {
            return try Self.hdKey(fromExtendedPrivate: xprv, network: record.network)
        }
        let mnemonic = try BIP39Mnemonic(phrase: record.mnemonic)
        return try HDKey(seed: mnemonic.seed(), network: record.network)
    }

    private func microSD2FASearchDirectories() -> [URL] {
        SimulatorCardStandin.ensureDirectories()
        return [
            SimulatorCardStandin.directory(for: .microSD),
            SimulatorCardStandin.documentsRoot()
        ]
    }

    private func microSD2FACandidateURLs() -> [URL] {
        var urls: [URL] = []
        for directory in microSD2FASearchDirectories() {
            urls.append(directory.appendingPathComponent(MicroSD2FA.tokenFilename()))
            urls.append(directory.appendingPathComponent(MicroSD2FA.visibleTokenFilename()))
            if let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                urls.append(contentsOf: items.filter { MicroSD2FA.looksLikeTokenFilename($0.lastPathComponent) })
            }
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0.standardizedFileURL).inserted }
    }

    private func hasMicroSD2FAFileOnDisk() -> Bool {
        microSD2FACandidateURLs().contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func authorizedMicroSD2FAPresent() -> Bool {
        guard let key = try? microSD2FAKey() else { return false }
        for url in microSD2FACandidateURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            if MicroSD2FA.authorizedCardPresent(fileData: data, enrolledNonces: preferences.sd2faNonces, key: key) {
                return true
            }
        }
        return false
    }

    private func writeMicroSD2FAToken(_ data: Data) throws {
        SimulatorCardStandin.ensureDirectories()
        let directory = SimulatorCardStandin.directory(for: .microSD)
        try data.write(to: directory.appendingPathComponent(MicroSD2FA.tokenFilename()), options: .atomic)
        try data.write(to: directory.appendingPathComponent(MicroSD2FA.visibleTokenFilename()), options: .atomic)
    }

    var unlockFooter: String {
        if failedPINAttempts == 0 { return "" }
        return "\(failedPINAttempts) failures, \(Self.maxPINAttempts - failedPINAttempts) tries left"
    }

    func lock() {
        rootKey = nil
        activeMnemonic = nil
        ephemeralPhrase = nil
        ephemeralXPRV = nil
        pendingEphemeral = false
        pendingMnemonic = nil
        pendingExtendedKey = nil
        activePassphrase = ""
        passphraseInput = ""
        currentPSBT = nil
        psbtReview = nil
        signedPSBTData = nil
        signedPSBT = nil
        finalizedTransaction = nil
        psbtSignedPriorMessage = nil
        psbtSignedFirstPass = true
        psbtSourceURL = nil
        pendingBatchItem = nil
        batchSignCallerDepth = nil
        derivedAddresses = []
        unlockPhase = .prefix
        pinInput = ""; pinPrefix = ""
        textEntryIsNickname = false
        textEntryIsPushtxURL = false
        pickingPushTxn = false
        textEntryIsNoteGroup = false
        textEntryIsKeyboardTest = false
        textEntryIsBKPWOverride = false
        textEntryIsNotesImportPassword = false
        textEntryIsCustomBackupPassword = false
        textEntryIsWIF = false
        textEntryIsNFCSeed = false
        textEntryIsNFCTools = false
        listedFilesAreNFCShare = false
        listedFilesAreNotesImport = false
        nfcReceiveNeedsStandIn = false
        nfcReadGeneration += 1
        wifSignPrivateKey = nil
        wifAddressPicker = nil
        pendingVisualizedWIF = nil
        serialREPL = SerialREPLSession()
        serialREPLInput = ""
        goToLockedRoot()
        stopVirtualDiskMonitor()
        resetSpendingSessionOnLock()
        resetTrickSessionOnLock()
        skipMultisigChecks = false
        selectedMultisigIndex = nil
        exploringMultisigIndex = nil
        renamingMultisigIndex = nil
        pendingMultisigWallet = nil
        createAirgappedCosigners = []
        createAirgappedMineCount = 0
    }

    /// Firmware `reset_self` / `machine.soft_reset` — RAM session gone; Keychain settings remain.
    func warmReset() {
        lock()
    }

    var storedBackupPassword: String? {
        DeveloperDebug.storedBackupPassword(bkpw: preferences.bkpw, lastWords: preferences.lastBackupPassword)
    }

    func wipeSimulator() {
        do { try KeychainStore.delete() }
        catch { present(error); return }
        record = nil
        rootKey = nil
        activeMnemonic = nil
        ephemeralPhrase = nil
        ephemeralXPRV = nil
        pendingEphemeral = false
        pendingMnemonic = nil
        pendingExtendedKey = nil
        pendingNotes = []
        preferences = SimulatorPreferences()
        history.removeAll()
        menuStack.removeAll()
        currentMenu = .virgin
        presentFirstBoot()
        errorMessage = nil
        statusMessage = "Local record removed."
        isBricked = false
        failedPINAttempts = 0
        UserDefaults.standard.removeObject(forKey: Self.termsAcceptedDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.preloginKillKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.preloginScrambleDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.preloginCountdownDefaultsKey)
    }

    func antiPhishingWords(for prefix: String) -> String {
        PinPrefixWords.displayString(pairingSecret: pairingSecret, pinPrefix: prefix)
    }

    private static func loadOrCreatePairingSecret() throws -> Data {
        if let existing = try KeychainStore.loadPairingSecret(),
           existing.count == PinPrefixWords.pairingSecretLength {
            return existing
        }
        let secret = try SecureRandom.bytes(count: PinPrefixWords.pairingSecretLength)
        try KeychainStore.savePairingSecret(secret)
        return secret
    }

    func startPassphraseFlow() {
        if !preferences.skipPassphraseIntro {
            showStory(title: "", body: """
            You may add a passphrase to your BIP-39 seed words. This creates an entirely new wallet, for every possible passphrase.

            By default, the Coldcard uses an empty string as the passphrase.

            Please write down the fingerprint of all your wallets, so you can confirm when you've got the right passphrase. (If you are writing down the passphrase as well, it's okay to put them together.) There is no way for the Coldcard to know if your entry is correct, and if you have it wrong, you will be looking at an empty wallet.

            Limitations: 100 characters max length, ASCII characters 32-126 (0x20-0x7e) only.

            ENTER to continue or press (2) to hide this message forever.
            """, onConfirm: .continuePassphrase)
            return
        }
        beginPassphraseEntry()
    }

    func beginPassphraseEntry() {
        // Q with no saved-passphrase file skips the menu and goes to text input (`seed.py`).
        if preferences.savedPassphrases.isEmpty {
            passphraseInput = activePassphrase
            navigate(to: .passphrase)
        } else {
            openMenu(.passphrase)
        }
    }

    var passphraseCompletionHint: String {
        guard !textEntryIsNickname, !textEntryIsPushtxURL, renamingVaultSeedID == nil,
              renamingMultisigIndex == nil else {
            return textEntryIsPushtxURL ? "QR to scan. ENTER when done." : ""
        }
        if textEntryIsKeyboardTest {
            return DeveloperDebug.keyboardTestPlaceholder
        }
        if textEntryIsBKPWOverride || textEntryIsCustomBackupPassword {
            return "Min \(DeveloperDebug.bkpwMinLength) characters. QR to scan."
        }
        if textEntryIsNotesImportPassword {
            return "Min \(SecureNotes.customPasswordMinLength) characters. QR to scan."
        }
        if textEntryIsWIF { return "Compressed WIF, 52 characters. QR to scan." }
        if textEntryIsNFCSeed { return "Paste 12, 18, or 24 seed words. ENTER when done." }
        if textEntryIsNFCTools { return "ENTER when done. QR to scan." }
        switch teleportTextKind {
        case .numericPassword: return "8 digits. ENTER when done."
        case .paranoidPassword: return "8 characters. ENTER when done."
        case .quickNote: return BIP39Passphrase.inputHint
        case .none: break
        }
        return BIP39Passphrase.inputHint
    }

    func completePassphraseBIP39() {
        let parts = passphraseInput.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last, last.count >= 2 else { return }
        let prediction = BIP39Mnemonic.predict(prefix: last.lowercased())
        let word: String?
        if let completed = prediction.completedWord, prediction.nextCharacters.isEmpty {
            word = completed
        } else if last.count >= 3 {
            let matches = BIP39EnglishWords.all.filter { $0.hasPrefix(last.lowercased()) }
            word = matches.count == 1 ? matches[0] : (matches.contains(last.lowercased()) ? last.lowercased() : nil)
        } else {
            word = nil
        }
        guard let word else { return }
        var next = parts
        next[next.count - 1] = word
        passphraseInput = next.joined(separator: " ") + " "
    }

    func applyPassphrasePreview() {
        passphraseInput = BIP39Passphrase.sanitized(passphraseInput)
        guard let mnemonic = activeMnemonic else { return }
        // Firmware: an empty passphrase entry is a no-op (`seed.py`: `if not pp: return`).
        guard !passphraseInput.isEmpty else { back(); return }
        do {
            let key = try HDKey(seed: mnemonic.seed(passphrase: passphraseInput), network: network)
            pendingPassphraseXFP = key.fingerprintHex
            pendingPassphraseParentXFP = rootKey?.fingerprintHex ?? "--------"
            showStory(title: "[\(pendingPassphraseXFP)]", body: passphraseConfirmBody, onConfirm: .confirmPassphrase)
        } catch { present(error) }
    }

    func confirmPassphrase(save: Bool) {
        activePassphrase = passphraseInput
        ephemeralOrigin = BIP39Passphrase.origin(parentXFP: pendingPassphraseParentXFP)
        pendingPassphraseSaveToKeychain = save
        do {
            try rebuildRoot()
            pendingEphemeralSummarizeUX = false
            if shouldOfferVaultForCurrentSecret() {
                pendingPassphraseAwaitingVault = true
                showStory(title: "", body: SeedVaultMenuCopy.offer, onConfirm: .skipVaultSave)
                return
            }
            persistPassphraseIfRequested()
            finishPassphraseWallet()
        } catch { present(error) }
    }

    private func persistPassphraseIfRequested() {
        guard pendingPassphraseSaveToKeychain, let xfp = rootKey?.fingerprintHex else { return }
        preferences.savedPassphrases.removeAll { $0.fingerprint == xfp }
        preferences.savedPassphrases.append(SavedPassphrase(fingerprint: xfp, phrase: passphraseInput))
        persistPreferencesQuietly()
        pendingPassphraseSaveToKeychain = false
    }

    private func finishPassphraseWallet() {
        persistPassphraseIfRequested()
        pendingPassphraseAwaitingVault = false
        pendingPassphraseSaveToKeychain = false
        history.removeAll()
        menuStack.removeAll()
        openMenu(.home, remember: false)
    }

    func restoreSavedPassphrase(_ id: UUID) {
        guard let saved = preferences.savedPassphrases.first(where: { $0.id == id }) else { return }
        passphraseInput = saved.phrase
        activePassphrase = saved.phrase
        do {
            try rebuildRoot()
            let xfp = rootKey?.fingerprintHex ?? "--------"
            history.removeAll()
            menuStack.removeAll()
            openMenu(.home, remember: false)
            // Firmware verifies the restored XFP against the saved record (pwsave.py).
            if xfp != saved.fingerprint {
                showStory(title: "", body: "XFP verification failed. Restored wallet XFP [\(xfp)] does not match expected XFP [\(saved.fingerprint)] from saved passphrase file.")
            } else {
                showStory(title: "[\(xfp)]", body: "Passphrase restored.")
            }
        } catch { present(error) }
    }

    func performRestoreMaster() {
        ephemeralPhrase = nil
        ephemeralXPRV = nil
        pendingEphemeral = false
        pendingExtendedKey = nil
        activePassphrase = ""
        passphraseInput = ""
        do {
            try rebuildRoot()
            history.removeAll()
            menuStack.removeAll()
            openMenu(.home, remember: false)
            statusMessage = "Master seed restored."
        } catch { present(error) }
    }

    func performDeleteSavedPassphrase() {
        guard let id = selectedSavedPassphraseID else { return }
        preferences.savedPassphrases.removeAll { $0.id == id }
        persistPreferencesQuietly()
        selectedSavedPassphraseID = nil
        openMenu(.passphrase, remember: false)
        statusMessage = "Deleted."
    }

    func loadAddresses() {
        if exploringMultisigIndex != nil {
            loadMultisigAddresses()
            return
        }
        guard let root = rootKey else { return }
        if customSingleAddress { return }
        beginWorking(.wait)
        errorMessage = nil
        let type = addressType
        let account = addressOverrideAccount ?? addressAccount
        let change = addressChange
        let start = addressPageStart
        let template = addressPathTemplate
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([DerivedAddress]?, String?) in
                do {
                    var addresses: [DerivedAddress] = []
                    let count = Int(AddressExplorer.visibleCount(start: start))
                    for offset in 0..<count {
                        let index = start + UInt32(offset)
                        if let template, template.contains("{idx}") {
                            let expanded = Self.expandPathTemplate(template, idx: index, change: change ? 1 : 0, account: account)
                            let base = try DerivationPath(expanded)
                            let child = try root.derived(path: base)
                            let address = try BitcoinAddress.address(publicKey: child.publicKey, type: type, network: root.network)
                            let script = try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: type)
                            addresses.append(DerivedAddress(index: index, change: change, path: base.description, address: address,
                                                            publicKeyHex: child.publicKey.hexString, scriptPubKeyHex: script.hexString))
                        } else {
                            addresses.append(try BitcoinAddress.derive(root: root, type: type, account: account, change: change, index: index))
                        }
                    }
                    return (addresses, nil)
                } catch { return (nil, error.localizedDescription) }
            }.value
            endWorking()
            if let addresses = result.0 {
                derivedAddresses = addresses
                storyTop = 0
            } else { errorMessage = result.1 ?? "Unable to derive addresses." }
        }
    }

    func refreshAddressPreviews() {
        guard let root = rootKey else { return }
        let account = addressAccount
        let start = addressStartIndex
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> [AddressType: String] in
                var previews: [AddressType: String] = [:]
                for type in AddressType.explorerCases {
                    if let derived = try? BitcoinAddress.derive(root: root, type: type, account: account, index: start) {
                        previews[type] = derived.address
                    }
                }
                return previews
            }.value
            addressPreviews = result
        }
    }

    func selectAddress(_ address: DerivedAddress) {
        selectedAddress = address
        preferences.lastAddressType = addressType
        preferences.lastAddressIndex = address.index
        persistPreferencesQuietly()
        // Firmware keeps the address story on screen (`show_n_addresses`); ENTER is a no-op.
    }

    func showSelectedAddressQR() {
        guard let selectedAddress else { return }
        qrPresentation = QRPresentation(title: selectedAddress.path, payload: selectedAddress.address, sensitive: false)
    }

    /// Firmware `show_qr_codes(addrs, …)` on the address story.
    func showAddressListQR() {
        guard addressQRAllowed else { return }
        let payloads = derivedAddresses.map(\.address)
        guard !payloads.isEmpty else { return }
        qrPresentation = QRPresentation(title: "Addresses", payloads: payloads, sensitive: false)
    }

    /// Firmware `NFC.share_text` of the currently displayed addresses.
    func shareAddressListNFC() {
        guard preferences.nfcSharingEnabled else { return }
        let text = derivedAddresses.map(\.address).joined(separator: "\n")
        guard !text.isEmpty else { return }
        SimulatorNFCWriter.shared.shareText(text) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                self.showStory(title: "", body: error.localizedDescription)
            }
        }
    }

    var addressExportPrompt: String {
        ExportPromptBuilder.prompt(
            whatItIs: "address summary file",
            dualSDSlots: true,
            virtualDiskEnabled: preferences.virtualDiskMode != 0,
            nfcEnabled: preferences.nfcSharingEnabled,
            qrEnabled: addressQRAllowed,
            qwerty: true,
            key0: AddressExplorer.changeKeyLabel(allowChange: addressAllowChange && !customSingleAddress,
                                                 showingChange: addressChange),
            forcePrompt: true
        ) ?? ""
    }

    var addressQRAllowed: Bool {
        AddressExplorer.allowQR(isMultisig: exploringMultisigIndex != nil,
                                showFull: preferences.fullMultisigAddressView)
    }

    var addressListStory: String {
        AddressExplorer.story(
            isSingle: customSingleAddress,
            pageStart: addressPageStart,
            startIndex: addressStartIndex,
            rows: derivedAddresses.map { ($0.path, Self.chunkAddress($0.address)) },
            exportPrompt: addressExportPrompt
        )
    }

    func showCustomPathWarning() {
        if customPathIsKeyExpression {
            exportKeyExpressionCustomPath()
            return
        }
        // Firmware inlines the path right after the first sentence (address_explorer.py).
        showStory(title: "MUCH DANGER",
                  body: "Now you will see the address for custom derivation path:\n\n\(customPathText)\n\n" +
                        FirmwareCopy.muchDangerCustomPathBody,
                  onConfirm: .continueCustomPath, confirmCode: "3")
    }

    func loadCustomPathAddresses(type explicitType: AddressType? = nil) {
        guard let root = rootKey else { return }
        beginWorking(.wait)
        let pathText = customPathText
        let template = addressPathTemplate
        let type = explicitType ?? addressType
        let start = addressStartIndex
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([DerivedAddress]?, Bool, String?) in
                do {
                    if AddressExplorer.listCount(path: pathText) != nil, let template, template.contains("{idx}") {
                        var addresses: [DerivedAddress] = []
                        let count = Int(AddressExplorer.visibleCount(start: start))
                        for offset in 0..<count {
                            let idx = start + UInt32(offset)
                            let expanded = Self.expandPathTemplate(template, idx: idx, change: 0, account: 0)
                            let base = try DerivationPath(expanded)
                            let child = try root.derived(path: base)
                            let address = try BitcoinAddress.address(publicKey: child.publicKey, type: type, network: root.network)
                            let script = try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: type)
                            addresses.append(DerivedAddress(index: idx, change: false, path: base.description, address: address,
                                                            publicKeyHex: child.publicKey.hexString, scriptPubKeyHex: script.hexString))
                        }
                        return (addresses, false, nil)
                    }
                    let base = try DerivationPath(pathText)
                    let child = try root.derived(path: base)
                    let address = try BitcoinAddress.address(publicKey: child.publicKey, type: type, network: root.network)
                    let script = try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: type)
                    let derived = DerivedAddress(index: 0, change: false, path: base.description, address: address,
                                                 publicKeyHex: child.publicKey.hexString, scriptPubKeyHex: script.hexString)
                    return ([derived], true, nil)
                } catch { return (nil, true, error.localizedDescription) }
            }.value
            endWorking()
            if let addresses = result.0 {
                derivedAddresses = addresses
                addressType = type
                customSingleAddress = result.1
                addressAllowChange = false
                addressChange = false
                addressPageStart = start
                addressOverrideAccount = nil
                exploringMultisigIndex = nil
                navigate(to: .addresses)
            } else { errorMessage = result.2 }
        }
    }

    nonisolated static func expandPathTemplate(_ template: String, idx: UInt32, change: UInt32, account: UInt32) -> String {
        template
            .replacingOccurrences(of: "{idx}", with: String(idx))
            .replacingOccurrences(of: "{change}", with: String(change))
            .replacingOccurrences(of: "{account}", with: String(account))
    }

    /// Firmware `ApplicationsMenu` / `SamouraiAppMenu` — honors Start Idx (`show_n_addresses` `start = self.start`).
    func startApplicationAddresses(_ kind: AddressExplorer.Application) {
        addressType = .nativeSegwit
        customSingleAddress = false
        addressAllowChange = true
        addressChange = false
        exploringMultisigIndex = nil
        addressPathTemplate = AddressExplorer.applicationPath(kind, coinType: network.coinType)
        switch kind {
        case .wasabi: addressOverrideAccount = 0
        case .samouraiPostmix: addressOverrideAccount = 2_147_483_646
        case .samouraiPremix: addressOverrideAccount = 2_147_483_645
        }
        addressPageStart = addressStartIndex
        navigate(to: .addresses)
    }

    func generateGenericWalletExport() {
        guard let root = rootKey else { return }
        runExport(title: "Generic JSON", filenameHint: "coldcard-export.json") {
            try WalletExporter.genericJSON(root: root, account: self.exportAccount)
        }
    }

    func generateDescriptorExport() {
        guard let root = rootKey else { return }
        let type = walletExportAddressType == .taproot ? AddressType.nativeSegwit : walletExportAddressType
        runExport(title: "\(type.displayName) Descriptor", filenameHint: "descriptor.txt") {
            Data(try WalletExporter.descriptor(root: root, type: type, account: self.exportAccount).utf8)
        }
    }

    func performWalletExport(_ kind: WalletExportKind) {
        pendingExport = kind
        exportSLIP132 = false
        descriptorCombined = true
        pendingKeyExpression = false
        if kind == .bullBitcoin {
            // Firmware exports Bull Bitcoin straight to a QR (`direct_way=KEY_QR`, flow.py).
            walletExportAddressType = .nativeSegwit
            presentBullBitcoinQR()
            return
        }
        if [.xpubSegwit, .xpubClassic, .xpubWrapped, .xpubMaster].contains(kind) {
            exportAccount = 0
            showXPUBExportStory()
            return
        }
        showStory(title: kind.firmwareIntroTitle, body: kind.firmwareIntroStory, onConfirm: .continueExport)
    }

    func continueNamedExport(account: UInt32) {
        exportAccount = account
        guard let kind = pendingExport else { return }
        if kind == .descriptor {
            showStory(title: "", body: FirmwareCopy.descriptorIntExt, onConfirm: .descriptorIntExt)
            return
        }
        if kind.needsAddressTypeMenu {
            exportAddressTypes = kind == .zeus ? [.nativeSegwit, .wrappedSegwit] : AddressType.singlesigExportOrder
            openMenu(.exportAddressType)
            return
        }
        finishWalletExport(kind, account: account)
    }

    func promptMessageIndex() {
        if screen == .story { back() }
        accountPromptPurpose = .messageIndex
        accountPromptValue = "0"
        if screen != .accountNumber { navigate(to: .accountNumber) }
    }

    func presentSignedMessageSignatureQR() {
        guard let signedMessage else { return }
        qrPresentation = QRPresentation(title: "Signature", payload: signedMessage.signatureBase64, sensitive: false)
    }

    func presentSignedMessageRFCQR() {
        guard let signedMessage else { return }
        presentBBQr(title: "Armored MSG", data: Data(signedMessage.armored.utf8), fileType: .unicode)
    }

    func pickExportAddressType(_ type: AddressType) {
        walletExportAddressType = type
        if let kind = pendingExport {
            finishWalletExport(kind, account: exportAccount)
        }
    }

    func pickMessageAddressType(_ type: AddressType) {
        if wifAddressPicker != nil {
            pickWIFAddressType(type)
            return
        }
        messageAddressType = type
        accountPromptPurpose = .messageSigning
        accountPromptValue = "0"
        navigate(to: .accountNumber)
    }

    func beginKeyExpressionExport() {
        pendingKeyExpression = true
        pendingExport = nil
        exportAccount = 0
        showStory(title: "",
                  body: FirmwareCopy.keyExpressionIntro + "\n\n" + FirmwareCopy.pickAccount + "\n\n" + FirmwareCopy.sensitiveNotSecret,
                  onConfirm: .openKeyExpressionMenu)
    }

    func submitAccountNumber() {
        let value = UInt32(accountPromptValue) ?? 0
        switch accountPromptPurpose {
        case .addressExplorer:
            addressAccount = value
            refreshAddressPreviews()
            back()
        case .addressStartIndex:
            addressStartIndex = value
            addressPageStart = value
            refreshAddressPreviews()
            back()
        case .messageSigning:
            messageAccount = value
            showStory(title: "Change?", body: FirmwareCopy.messageChange, onConfirm: .messageChange)
        case .messageIndex:
            messageIndex = value
            messagePath = defaultMessagePath()
            messagePathLocked = true
            back()
            signMessage()
        case .walletExport:
            exportAccount = value
            if pendingKeyExpression {
                openMenu(.exportKeyExpression)
            } else if let kind = pendingExport,
                      [.xpubSegwit, .xpubClassic, .xpubWrapped, .xpubMaster].contains(kind) {
                back()
                showXPUBExportStory()
            } else {
                continueNamedExport(account: value)
            }
        case .psbtExploreIndex:
            pagePSBTExplorer(to: Int(value))
            back()
        case .keypathIndex:
            keypathAtRoot = false
            keypathCPath = keypathPendingDeeper
            keypathLeaf = value
            back()
            openMenu(.keypath, remember: false)
        case .bip85Index:
            var index = value
            if !preferences.b85Unlimited { index = min(index, 9999) }
            back()
            revealBIP85(index: index)
        case .spendingMagnitude:
            submitSpendingMagnitude(value)
        case .web2FACode:
            submitWeb2FACode(accountPromptValue)
        case .trickWrongCount:
            submitTrickWrongCount(value)
        case .multisigXPUB:
            back()
            exportMultisigXPUB(account: value)
        case .multisigCreateAccount:
            back()
            addOwnAirgappedKey(account: value)
        case .multisigCreateM:
            back()
            completeCreateAirgapped(mValue: value)
        }
    }

    /// Firmware `export_xpub` story loop (actions.py): ENTER shows the QR, (1) picks the
    /// account, (2) toggles SLIP-132 with the concrete prefix in the copy.
    func showXPUBExportStory() {
        guard let root = rootKey, let kind = pendingExport else { return }
        let pathText: String
        let type: AddressType?
        switch kind {
        case .xpubMaster:
            pathText = "m"
            type = nil
        case .xpubSegwit, .xpubClassic, .xpubWrapped:
            let resolved: AddressType = kind == .xpubSegwit ? .nativeSegwit : kind == .xpubClassic ? .legacy : .wrappedSegwit
            type = resolved
            pathText = DerivationPath.account(type: resolved, network: root.network, account: exportAccount).description
        default:
            return
        }
        var msg = "Show QR of the XPUB for path:\n\n\(pathText)\n\n"
        if pathText != "m" {
            msg += "Press (1) to select account other than \(exportAccount == 0 ? "zero" : String(exportAccount))."
            if kind != .xpubClassic, let type {
                let slip = Self.firmwareSLIP132PubPrefix(type: type, network: root.network)
                let bip32 = root.network == .mainnet ? "xpub" : "tpub"
                let target = exportSLIP132 ? bip32 : slip
                msg += " Press (2) to show \(target) \(exportSLIP132 ? "(BIP-32)" : "(SLIP-132)")."
            }
        }
        if preferences.nfcSharingEnabled {
            msg += " Press NFC to share via NFC. "
        }
        if screen == .story {
            story = StoryPresentation(
                title: "", body: msg, confirmCode: nil, onConfirm: .showXPUBQR,
                hintQR: true, hintNFC: preferences.nfcSharingEnabled
            )
        } else {
            showStory(title: "", body: msg, onConfirm: .showXPUBQR,
                      hintQR: true, hintNFC: preferences.nfcSharingEnabled)
        }
    }

    func presentXPUBQR() {
        guard let root = rootKey, let kind = pendingExport else { return }
        do {
            switch kind {
            case .xpubMaster:
                qrPresentation = QRPresentation(title: "Master XPUB", payload: try root.neutered().serializePublic(), sensitive: false)
            case .xpubSegwit, .xpubClassic, .xpubWrapped:
                let type: AddressType = kind == .xpubSegwit ? .nativeSegwit : kind == .xpubClassic ? .legacy : .wrappedSegwit
                let path = DerivationPath.account(type: type, network: root.network, account: exportAccount)
                let node = try root.derived(path: path).neutered()
                let xpub = (exportSLIP132 && kind != .xpubClassic) ? node.serializePublic(addressType: type) : node.serializePublic()
                qrPresentation = QRPresentation(title: kind.menuTitle, payload: xpub, sensitive: false)
            default: break
            }
        } catch { present(error) }
    }

    /// Firmware `chains.slip132[AF_*].hint + "pub"` for the Export XPUB (2) toggle.
    private static func firmwareSLIP132PubPrefix(type: AddressType, network: BitcoinNetwork) -> String {
        let main = network == .mainnet
        switch type {
        case .nativeSegwit: return main ? "zpub" : "vpub"
        case .wrappedSegwit: return main ? "ypub" : "upub"
        default: return main ? "xpub" : "tpub"
        }
    }

    private func xpubExportText() throws -> String? {
        guard let root = rootKey, let kind = pendingExport else { return nil }
        switch kind {
        case .xpubMaster:
            return try root.neutered().serializePublic()
        case .xpubSegwit, .xpubClassic, .xpubWrapped:
            let type: AddressType = kind == .xpubSegwit ? .nativeSegwit : kind == .xpubClassic ? .legacy : .wrappedSegwit
            let path = DerivationPath.account(type: type, network: root.network, account: exportAccount)
            let node = try root.derived(path: path).neutered()
            return (exportSLIP132 && kind != .xpubClassic) ? node.serializePublic(addressType: type) : node.serializePublic()
        default:
            return nil
        }
    }

    /// Firmware `NFC.share_text(xpub)` from the Export XPUB story (`KEY_NFC`).
    func shareXPUBNFC() {
        guard preferences.nfcSharingEnabled else { return }
        do {
            guard let text = try xpubExportText() else { return }
            SimulatorNFCWriter.shared.shareText(text) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result {
                    self.showStory(title: "", body: error.localizedDescription)
                }
            }
        } catch { present(error) }
    }

    func presentBullBitcoinQR() {
        guard let root = rootKey else { return }
        beginWorking(.generating)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (String?, String?) in
                do {
                    let text = try WalletExporter.descriptor(root: root, type: .nativeSegwit, account: 0)
                    return (text, nil)
                } catch { return (nil, error.localizedDescription) }
            }.value
            endWorking()
            if let text = result.0 {
                qrPresentation = QRPresentation(title: "Bull Bitcoin", payload: text, sensitive: false)
            } else { errorMessage = result.1 }
        }
    }

    func finishWalletExport(_ kind: WalletExportKind, account: UInt32) {
        guard let root = rootKey else { return }
        exportAccount = account
        switch kind {
        case .xpubXFP:
            qrPresentation = QRPresentation(title: "Current XFP", payload: root.fingerprintHex, sensitive: false)
            return
        case .xpubMaster, .xpubSegwit, .xpubClassic, .xpubWrapped:
            showXPUBExportStory()
            return
        default:
            break
        }
        let title = WalletExportKind.keyExpressionKinds.contains(kind) ? "Key Expression" : kind.menuTitle
        let type = walletExportAddressType
        let combined = descriptorCombined
        let wallets = preferences.importedMultisigWallets
        runExport(title: title, filenameHint: filename(for: kind, xfp: root.fingerprintHex)) {
            try exportWalletData(kind: kind, root: root, account: account, addressType: type,
                                 descriptorCombined: combined, wallets: wallets)
        }
    }

    private func filename(for kind: WalletExportKind, xfp: String) -> String {
        switch kind {
        case .sparrow: "sparrow-export.json"
        case .cove: "cove-export.json"
        case .bitcoinCore: "bitcoin-core.txt"
        case .nunchuk: "nunchuk-export.json"
        case .bullBitcoin: "bull-bitcoin.txt"
        case .blueWallet: "new-blue.json"
        case .electrum: "new-electrum.json"
        case .wasabi: "new-wasabi.json"
        case .fullyNoded: "fully noded-export.json"
        case .unchained: "unchained-\(xfp).json"
        case .theya: "theya-export.json"
        case .bitcoinSafe: "bitcoin safe-export.json"
        case .zeus: "zeus-export.txt"
        case .samouraiPostmix: "samourai-post-mix.txt"
        case .samouraiPremix: "samourai-pre-mix.txt"
        case .descriptor: "descriptor.txt"
        case .genericJSON: "coldcard-export.json"
        case .keyExpression, .keyExpressionClassic, .keyExpressionWrapped,
             .keyExpressionMultiWSH, .keyExpressionMultiSHWSH: "key_expr.txt"
        case .dumpSummary: "public.txt"
        default: "coldcard-export"
        }
    }

    private func runExport(title: String, filenameHint: String, builder: @escaping () throws -> Data) {
        beginWorking(.generating)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String?) in
                do { return (try builder(), nil) }
                catch { return (nil, error.localizedDescription) }
            }.value
            endWorking()
            if let data = result.0 {
                walletExportTitle = title
                walletExportText = String(decoding: data, as: UTF8.self)
                exportFilename = filenameHint
                navigate(to: .walletExport)
            } else { errorMessage = result.1 }
        }
    }

    func exportCurrentWalletText() {
        guard !walletExportText.isEmpty else { return }
        let isJSON = walletExportText.first == "{"
        let filename = exportFilename.contains(".") ? exportFilename : (isJSON ? "coldcard-generic-export.json" : "coldcard-export.txt")
        let data = Data(walletExportText.utf8)
        let fileType: UTType = isJSON ? .json : .plainText
        if let kind = pendingExport,
           let root = rootKey,
           let format = kind.signatureFormat(addressType: walletExportAddressType, account: kind.signatureAccount(exportAccount: exportAccount),
                                             coinType: root.network.coinType) {
            let account = kind.signatureAccount(exportAccount: exportAccount)
            let context = WalletExporter.detachedSignatureContext(format: format, coinType: root.network.coinType, account: account)
            let sigName = BitcoinMessageSigner.signatureFilename(forInputFilename: filename)
            let story = WalletExporter.fileWrittenStory(title: kind.firmwareExportContentsTitle, filename: filename,
                                                        signatureFilename: sigName)
            prepareExport(data: data, filename: filename, type: fileType, successStory: ("", story))
            queueDetachedSignature(for: data, filename: filename, derive: context.derive, addressType: context.addressType)
        } else {
            prepareExport(data: data, filename: filename, type: fileType)
        }
    }

    func showCurrentWalletExportQR() {
        guard !walletExportText.isEmpty else { return }
        if WalletExporter.usesBBQr(body: walletExportText) {
            let fileType: BBQrFileType = walletExportText.first == "{" ? .json : .unicode
            presentBBQr(title: walletExportTitle, data: Data(walletExportText.utf8), fileType: fileType)
        } else {
            qrPresentation = QRPresentation(title: walletExportTitle, payload: walletExportText, sensitive: false)
        }
    }

    func requestPSBTImport() {
        abandonBatchSignForSingleFile()
        importPurpose = .psbt
        showFileImporter = true
    }

    /// Firmware Ready To Sign key (2): `force_vdisk=True` file picker on `/vdisk`.
    func importPSBTFromVirtualDisk() {
        guard virtualDiskEnabled else { return }
        presentReadyToSignChoices(SimulatorCardStandin.psbtFiles(on: .virtDisk), emptyShowsImportPrompt: false)
    }

    /// Firmware `NFC.start_psbt_rx()` from empty Ready To Sign (`KEY_NFC`).
    func requestPSBTNFCImport() {
        guard preferences.nfcSharingEnabled else { return }
        beginNFCPSBTReceive(wrapErrors: false)
    }

    var nfcStandInTitle: String {
        switch nfcStandInKind {
        case .psbt: return "NFC"
        case .ephemeralSeed: return "Import via NFC"
        case .showAddress: return "Show Address"
        case .verifyAddress: return "Verify Address"
        case .importMultisig: return "Import Multisig"
        case .signMessage: return "Sign Message"
        case .verifySigFile: return "Verify Sig File"
        }
    }

    var nfcStandInPrompt: String {
        switch nfcStandInKind {
        case .psbt:
            return "Paste a PSBT or import a file. Core NFC is unavailable on this device."
        case .ephemeralSeed:
            return "Paste 12, 18, or 24 seed words, or import a file. Core NFC is unavailable on this device."
        case .showAddress:
            return "Paste a derivation path and optional address format (p2pkh / p2wpkh / p2sh-p2wpkh), or import a file."
        case .verifyAddress:
            return "Paste a Bitcoin address or BIP-21 URI, or import a file."
        case .importMultisig:
            return "Paste a multisig descriptor or Coldcard config, or import a file."
        case .signMessage:
            return "Paste a 1-3 line message to sign (text, Sparrow, or JSON), or import a file."
        case .verifySigFile:
            return "Paste a Bitcoin signed-message armor file, or import a file."
        }
    }

    func handleNFCStandInText(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if tryHandleKeyTeleportText(trimmed) { return }
        switch nfcStandInKind {
        case .ephemeralSeed:
            applyEphemeralSeedFromNFCText(trimmed)
        case .psbt:
            if let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]),
               data.starts(with: PSBT.magic) {
                loadPSBT(data: data, source: "NFC", inputMethod: "nfc")
                return
            }
            loadPSBT(data: Data(trimmed.utf8), source: "NFC", inputMethod: "nfc")
        case .showAddress, .verifyAddress, .importMultisig, .signMessage, .verifySigFile:
            consumeNFCToolsText(nfcStandInKind == .signMessage ? value : trimmed)
        }
    }

    func beginNFCStandInFileImport() {
        switch nfcStandInKind {
        case .ephemeralSeed:
            importPurpose = .nfcSeed
        case .psbt:
            importPurpose = .psbt
        case .showAddress:
            importPurpose = .nfcShowAddress
        case .verifyAddress:
            importPurpose = .nfcVerifyAddress
        case .importMultisig:
            importPurpose = .nfcImportMultisig
        case .signMessage:
            importPurpose = .nfcSignMessage
        case .verifySigFile:
            importPurpose = .nfcVerifySig
        }
        showFileImporter = true
    }

    /// Firmware `actions.nfc_recv_ephemeral` / `NFC.import_ephemeral_seed_words_nfc`.
    func beginEphemeralSeedNFCImport() {
        guard preferences.nfcSharingEnabled else { return }
        nfcStandInKind = .ephemeralSeed
        pendingEphemeral = true
        ephemeralOrigin = "NFC Import"
        if SimulatorNFC.isAvailable {
            SimulatorNFC.read(prompt: FirmwareCopy.nfcTapPrompt) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    if let nfc = error as? SimulatorNFCError {
                        switch nfc {
                        case .cancelled: return
                        case .unavailable: self.presentEphemeralNFCStandIn()
                        case .failed: self.showStory(title: "Sorry!", body: FirmwareCopy.nfcNoTagData)
                        }
                    } else {
                        self.showStory(title: "ERROR", body: FirmwareCopy.nfcSeedImportFailedPrefix + error.localizedDescription)
                    }
                case .success(let payloads):
                    self.applyEphemeralSeedFromNFCPayloads(payloads)
                }
            }
            return
        }
        presentEphemeralNFCStandIn()
    }

    private func presentEphemeralNFCStandIn() {
        if interfaceMode == .phone {
            showNFCStandIn = true
        } else {
            showStory(title: "Import via NFC", body: FirmwareCopy.nfcSeedStandIn, onConfirm: .pasteNFCSeed)
        }
    }

    private func beginNFCSeedFileImport() {
        story.onConfirm = nil
        nfcStandInKind = .ephemeralSeed
        importPurpose = .nfcSeed
        showFileImporter = true
    }

    func finishNFCSeedPaste() {
        let text = passphraseInput
        textEntryIsNFCSeed = false
        textEntryIsNFCTools = false
        passphraseInput = ""
        back()
        applyEphemeralSeedFromNFCText(text)
    }

    func applyEphemeralSeedFromNFCText(_ text: String) {
        applyEphemeralSeedFromNFCPayloads([Data(text.utf8)])
    }

    private func applyEphemeralSeedFromNFCPayloads(_ payloads: [Data]) {
        if payloads.isEmpty {
            showStory(title: "Sorry!", body: FirmwareCopy.nfcNoTagData)
            return
        }
        var tokens: [String]?
        for payload in payloads {
            if let found = NFCShare.seedWordList(fromUTF8: payload) {
                tokens = found
                break
            }
        }
        guard let tokens else {
            showStory(title: "", body: FirmwareCopy.nfcSeedMissing)
            return
        }
        do {
            let words = try NFCShare.expandBIP39Words(tokens)
            pendingMnemonic = try BIP39Mnemonic(words: words)
            pendingEphemeral = true
            ephemeralOrigin = "NFC Import"
            try applyEphemeralSeed()
        } catch {
            showStory(title: "ERROR", body: FirmwareCopy.nfcSeedImportFailedPrefix + error.localizedDescription)
        }
    }

    /// Firmware `NFC.share_file`.
    func beginNFCFileShare() {
        listedFilesAreNFCShare = true
        listedDiskFiles = SimulatorCardStandin.listFilesForPicker(
            vdiskEnabled: virtualDiskEnabled,
            minSize: NFCShare.minSize,
            maxSize: NFCShare.maxSize
        ).filter { NFCShare.isSuitableFilename($0.filename) }
        guard !listedDiskFiles.isEmpty else {
            listedFilesAreNFCShare = false
            showStory(title: "", body: FirmwareCopy.noSuitableFiles)
            return
        }
        openMenu(.listedFiles)
    }

    private func shareListedFileViaNFC(id: String) {
        guard let file = listedDiskFiles.first(where: { $0.id == id }) else { return }
        let data = (try? Data(contentsOf: file.url)) ?? Data()
        shareNFCFile(named: file.filename, data: data)
    }

    private func shareNFCFile(named filename: String, data: Data) {
        guard let kind = NFCShare.kind(forFilename: filename) else { return }
        do {
            let message: SimulatorNDEFMessage
            let exportType: UTType
            switch kind {
            case .text:
                guard data.count < NFCShare.maxSize else {
                    showStory(title: "", body: FirmwareCopy.nfcPSBTTooLarge)
                    return
                }
                message = .text(String(decoding: data, as: UTF8.self))
                exportType = .plainText
            case .json:
                guard data.count < NFCShare.maxSize else {
                    showStory(title: "", body: FirmwareCopy.nfcPSBTTooLarge)
                    return
                }
                message = .json(String(decoding: data, as: UTF8.self))
                exportType = .json
            case .psbt:
                guard data.count < NFCShare.maxSize else {
                    showStory(title: "", body: FirmwareCopy.nfcPSBTTooLarge)
                    return
                }
                let sha = SHA2.sha256(data)
                message = SimulatorNDEFMessage(records: [
                    .text("PSBT file: \(filename)"),
                    .binary(type: "bitcoin.org:sha256", data: sha),
                    .binary(type: "bitcoin.org:psbt", data: data)
                ])
                exportType = .data
            case .txn:
                let txn = try PushTx.decodeTxnFile(data)
                guard txn.count < NFCShare.maxSize else {
                    showStory(title: "", body: FirmwareCopy.nfcTxnTooLarge)
                    return
                }
                let sha = SHA2.sha256(txn)
                var records: [SimulatorNDEFMessage.Record] = []
                if let txid = PushTx.txidFromFilename(filename) {
                    records.append(.text("Signed Transaction: \(txid)"))
                    if let hex = try? Data(hex: txid) {
                        records.append(.binary(type: "bitcoin.org:txid", data: hex))
                    }
                }
                records.append(.binary(type: "bitcoin.org:sha256", data: sha))
                records.append(.binary(type: "bitcoin.org:txn", data: txn))
                message = SimulatorNDEFMessage(records: records)
                exportType = .data
            }
            if SimulatorNFC.isAvailable {
                SimulatorNFC.write(message, prompt: FirmwareCopy.nfcTapPrompt) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.statusMessage = "Write complete."
                    case .failure(let error):
                        if let nfc = error as? SimulatorNFCError {
                            switch nfc {
                            case .cancelled: return
                            case .unavailable:
                                self.prepareExport(
                                    data: data,
                                    filename: filename,
                                    type: exportType,
                                    successStory: (title: "", body: FirmwareCopy.nfcStandInHint)
                                )
                            case .failed(let message):
                                self.showStory(title: "Sorry!", body: message)
                            }
                        } else {
                            self.showStory(title: "Sorry!", body: error.localizedDescription)
                        }
                    }
                }
            } else {
                prepareExport(
                    data: data,
                    filename: filename,
                    type: exportType,
                    successStory: (title: "", body: FirmwareCopy.nfcStandInHint)
                )
            }
        } catch {
            showStory(title: "ERROR", body: error.localizedDescription)
        }
    }

    func requestBackupRestore() {
        if hasSeed, !restoreAsEphemeral, !pendingEphemeral {
            showStory(title: "Restore Backup", body: FirmwareCopy.needClearSeed)
            return
        }
        restoreBackupAllowsCleartext = false
        importPurpose = .backup
        showFileImporter = true
    }

    func requestVerifyBackup() {
        importPurpose = .verifyBackup
        showFileImporter = true
    }

    func requestSignTextFile() {
        importPurpose = .signText
        showFileImporter = true
    }

    func handleImportedFiles(_ urls: [URL]) {
        if importPurpose == .batchPSBT {
            var queue: [BatchPSBTItem] = []
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      data.count >= SimulatorCardStandin.psbtPickerMinSize,
                      PSBT.isPSBTTaste(filename: url.lastPathComponent, data: data) else { continue }
                queue.append(BatchPSBTItem(name: url.lastPathComponent, data: data, url: url))
            }
            if queue.isEmpty {
                showStory(title: "", body: DoneSigning.noPSBTsFound)
                return
            }
            batchQueue = queue
            startNextBatchPSBT()
            return
        }
        if importPurpose == .siblingHashes {
            verifySiblingHashFiles(urls)
            return
        }
        if let url = urls.first { handleImportedFile(url) }
    }

    func startNextBatchPSBT() {
        guard !batchQueue.isEmpty else {
            quitBatchSign()
            return
        }
        let item = batchQueue.removeFirst()
        pendingBatchItem = item
        let body = FirmwareCopy.batchSignPrompt(filename: item.name)
        // Firmware loops `ux_show_story` on the same stack frame; replace in place
        // so skip does not push a nested story or pop `menuStack`.
        if screen == .story, story.onConfirm == .batchSignConfirm {
            story = StoryPresentation(title: "", body: body, onConfirm: .batchSignConfirm)
            storyTop = 0
            return
        }
        popToBatchSignCaller()
        if batchSignCallerDepth == nil {
            batchSignCallerDepth = history.count
        }
        showStory(title: "", body: body, onConfirm: .batchSignConfirm)
    }

    /// Firmware `_batch_sign` after a successful signed export: next file story,
    /// not Ready To Sign.
    private func continueBatchAfterSignedExport() {
        currentPSBT = nil
        psbtReview = nil
        signedPSBTData = nil
        signedPSBT = nil
        finalizedTransaction = nil
        signingResults = []
        loadedPSBTSHA = nil
        loadedPSBTURL = nil
        psbtSignedPriorMessage = nil
        startNextBatchPSBT()
    }

    private func popToBatchSignCaller() {
        guard let depth = batchSignCallerDepth else { return }
        while history.count > depth {
            screen = history.removeLast()
        }
        story.onConfirm = nil
    }

    func skipCurrentBatchPSBT() {
        // Firmware: `(1)` is neither sign nor quit; the loop continues to the next file.
        pendingBatchItem = nil
        if batchQueue.isEmpty {
            quitBatchSign()
        } else {
            startNextBatchPSBT()
        }
    }

    /// Firmware `_batch_sign` after CANCEL, the last skip, last refuse, or dismiss
    /// of the last signed filename story: return to the caller (File Management or
    /// Ready To Sign). Do not jump to `.psbt` or pop `menuStack`.
    private func quitBatchSign() {
        story.onConfirm = nil
        pendingBatchItem = nil
        batchQueue.removeAll()
        if batchSignCallerDepth != nil {
            popToBatchSignCaller()
            batchSignCallerDepth = nil
        } else if screen == .story, let previous = history.popLast() {
            screen = previous
        }
        selectedMenuIndex = 0
        storyTop = 0
    }

    /// Drop a leftover `_batch_sign` queue so the next sign is a single-file review.
    private func abandonBatchSignForSingleFile() {
        batchQueue.removeAll()
        pendingBatchItem = nil
        batchSignCallerDepth = nil
    }

    func handleImportedFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            if tryHandleKeyTeleportText(String(decoding: data, as: UTF8.self)) { return }
            switch importPurpose {
            case .psbt, .batchPSBT: loadPSBT(data: data, source: url.lastPathComponent, sourceURL: url, url: url)
            case .backup: restoreBackup(data: data, filename: url.lastPathComponent)
            case .verifyBackup: verifyBackupFile(data: data, filename: url.lastPathComponent)
            case .signText:
                let text = String(decoding: data, as: UTF8.self)
                let name = url.lastPathComponent
                let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                guard !name.lowercased().contains("-signed"),
                      (2...500).contains(data.count),
                      (1...3).contains(lines.count),
                      let request = BitcoinMessageSigner.parseSignRequest(text) else {
                    errorMessage = FirmwareCopy.signTextFileHint
                    return
                }
                messageSourceFilename = name
                applySignRequest(request)
            case .notes: importNotes(data: data, filename: url.lastPathComponent)
            case .fileShare:
                presentBBQr(title: url.lastPathComponent, data: data, fileType: .unicode)
            case .verifySig:
                verifySigFile(text: String(decoding: data, as: UTF8.self),
                              filename: url.lastPathComponent,
                              digestCheck: true,
                              siblingDirectory: url.deletingLastPathComponent())
            case .nfcVerifySig:
                verifySigFile(text: String(decoding: data, as: UTF8.self),
                              filename: url.lastPathComponent,
                              digestCheck: false)
            case .siblingHashes:
                break
            case .spendingWhitelist:
                importWhitelist(from: data)
            case .wif:
                consumeImportedWIFFile(data)
            case .microSD2FA:
                handleMicroSD2FAPickedFile(data)
            case .tapsigner:
                acceptTapsignerCiphertext(data, origin: url.lastPathComponent)
            case .cloneStartFile:
                ingestCloneStartFile(data: data)
            case .cloneIngest:
                ingestCloneBackup(data: data, filename: url.lastPathComponent)
            case .nfcSeed:
                applyEphemeralSeedFromNFCText(String(decoding: data, as: UTF8.self))
            case .nfcShowAddress:
                nfcStandInKind = .showAddress
                consumeNFCToolsText(String(decoding: data, as: UTF8.self))
            case .nfcVerifyAddress:
                nfcStandInKind = .verifyAddress
                consumeNFCToolsText(String(decoding: data, as: UTF8.self))
            case .nfcImportMultisig:
                nfcStandInKind = .importMultisig
                consumeNFCToolsText(String(decoding: data, as: UTF8.self))
            case .nfcSignMessage:
                nfcStandInKind = .signMessage
                consumeNFCToolsText(String(decoding: data, as: UTF8.self))
            case .pushTransaction:
                pushTransaction(data: data, filename: url.lastPathComponent)
            case .teleportPSBT:
                handleTeleportPSBTFile(data, source: url.lastPathComponent)
            case .xprv:
                consumeImportedXPRVFile(data)
            case .multisig:
                importMultisigFromText(String(decoding: data, as: UTF8.self),
                                       nameHint: (url.lastPathComponent as NSString).deletingPathExtension)
            case .multisigCreateXPUB:
                ingestCreateAirgappedJSON(String(decoding: data, as: UTF8.self))
            }
        } catch { present(error) }
    }

    func loadPSBT(data: Data, source: String = "file", fromBatch: Bool = false,
                  sourceURL: URL? = nil, expectedSHA: Data? = nil,
                  url: URL? = nil, volume: SimulatorCardStandin.Volume? = nil,
                  inputMethod: String = "sd") {
        if !fromBatch { abandonBatchSignForSingleFile() }
        guard let root = rootKey else { return }
        let maxFee = preferences.maxNetworkFee.rawValue
        let sighashChecks = !preferences.sighashWarnOnly
        let wallets = preferences.importedMultisigWallets
        let skip = skipMultisigChecks
        let unsorted = preferences.allowUnsortedMultisig
        let trust = MultisigTrustPolicy(rawValue: effectiveMultisigTrustPolicy) ?? .offer
        let sourceURL = sourceURL ?? url
        let sourceVolume = volume
        let storedWIF = wifKeys
        let units = preferences.displayUnits
        let history = OutptValueCache(entries: preferences.ovc)
        Task {
            await runReadingProgress(bytes: data.count)
            beginWorking(.validating)
            let result = await Task.detached(priority: .userInitiated) { () -> (PSBT?, PSBTReview?, ImportedMultisigWallet?, Data?, (String, String)?) in
                do {
                    let ingested = try PSBT.ingest(data, expectedSHA: expectedSHA)
                    let psbt = ingested.psbt
                    var reviewWallets = wallets
                    var enroll: ImportedMultisigWallet?
                    if let policy = psbt.guessMultisigPolicy(), !psbt.globalXpubs.isEmpty {
                        let context = MultisigImportContext(root: root, allowUnsorted: unsorted, disableChecks: skip)
                        if let resolved = try? MultisigWalletConfig.resolvePSBT(
                            xpubs: psbt.globalXpubs,
                            addressFormat: policy.format,
                            requiredSignatures: policy.requiredSignatures,
                            totalSigners: policy.totalSigners,
                            wallets: wallets,
                            context: context,
                            trust: trust,
                            existingNames: wallets.map(\.name)
                        ) {
                            switch resolved {
                            case .matched:
                                break
                            case .proposed(let wallet, let needsApproval):
                                if needsApproval { enroll = wallet }
                                else { reviewWallets = wallets + [wallet] }
                            case .notMultisig:
                                break
                            }
                        }
                    }
                    return (psbt, psbt.review(root: root, maxFeePercent: maxFee, sighashChecks: sighashChecks,
                                              wallets: reviewWallets, wifKeys: storedWIF,
                                              disableMultisigChecks: skip, utxoHistory: history,
                                              displayUnits: units),
                            enroll, ingested.sha, nil)
                } catch {
                    return (nil, nil, nil, nil, PSBT.approvalFailure(for: error))
                }
            }.value
            if result.0 != nil {
                await runVisualizingProgress()
            }
            endWorking()
            if let failure = result.4 {
                presentPSBTLoadFailure(failure, fromBatch: fromBatch)
                return
            }
            if let review = result.1 {
                preferences.ovc = review.utxoHistory.persistedEntries
                persistPreferencesQuietly()
            }
            if let psbt = result.0 {
                if let fatal = result.1?.fatalIssue {
                    presentPSBTLoadFailure((PSBT.failureTitle(for: fatal), fatal), fromBatch: fromBatch)
                    return
                }
                currentPSBT = psbt
                loadedPSBTSHA = result.3
                loadedPSBTURL = sourceURL
                psbtReview = result.1
                if var review = psbtReview {
                    if !applySpendingPolicy(to: &review, psbt: psbt) { return }
                    psbtReview = review
                }
                signedPSBTData = nil
                signedPSBT = nil
                finalizedTransaction = nil
                signingResults = []
                psbtSourceName = source
                psbtSourceURL = sourceURL
                psbtInputChannel = channelForPSBTSource(source, volume: sourceVolume)
                psbtSignedFirstPass = true
                psbtSignedPriorMessage = nil
                psbtSignedTitle = DoneSigning.signedTitle
                psbtInputMethod = inputMethod
                if screen == .nfcReceive { back() }
                if screen != .psbt { navigate(to: .psbt) }
                if let enroll = result.2 {
                    offerEnroll(enroll, existing: wallets)
                }
            } else {
                presentPSBTLoadFailure(("Failure", PSBT.parseFailedStory), fromBatch: fromBatch)
            }
        }
    }

    private func presentPSBTLoadFailure(_ failure: (title: String, body: String), fromBatch: Bool) {
        let confirm: StoryConfirmAction? = fromBatch ? .batchSignAfterExport : nil
        showStory(title: failure.title, body: failure.body, onConfirm: confirm)
    }

    /// Firmware `ApproveTransaction.interact()` story body (`shared/auth.py`).
    var psbtApprovalBody: String {
        guard let review = psbtReview else { return "" }
        var msg = ""
        let warningCount = review.warnings.count
        if warningCount == 1 { msg += "(1 warning below)\n\n" }
        else if warningCount >= 2 { msg += "(\(warningCount) warnings below)\n\n" }

        let summary = PSBT.approvalOutputSummary(review.outputs)
        if let bip322 = review.bip322Message {
            let challenge = review.bip322Challenge
            let challengeIsAddress = challenge.map {
                $0.hasPrefix("bc1") || $0.hasPrefix("tb1") || $0.hasPrefix("bcrt1")
                    || $0.hasPrefix("1") || $0.hasPrefix("3") || $0.hasPrefix("2")
                    || $0.hasPrefix("m") || $0.hasPrefix("n")
            } ?? false
            msg += PSBT.bip322ApprovalPreamble(
                isProofOfReserves: review.bip322IsProofOfReserves,
                message: bip322,
                amount: review.bip322IsProofOfReserves ? review.totalInput.map(formatAmount) : nil,
                challengeAddress: challengeIsAddress ? challenge : nil,
                challengeHex: challengeIsAddress ? nil : challenge,
                inputCount: review.inputs.count,
                outputCount: review.outputs.count
            )
        } else {
            msg += PSBT.approvalValuePreamble(
                isConsolidation: summary.isConsolidation,
                sendAmount: formatAmount(review.totalOutput - summary.changeTotal),
                totalOutput: formatAmount(review.totalOutput)
            )
            if let fee = review.fee { msg += "Network fee \(formatAmount(fee))\n\n" }
            msg += PSBT.inputOutputCountLine(inputs: review.inputs.count, outputs: review.outputs.count)
        }

        if review.bip322Message == nil {
            for output in summary.foreign {
                msg += renderPSBTOutput(output) + "\n"
            }
            if summary.hiddenForeignCount > 0 {
                msg += ".. plus \(summary.hiddenForeignCount) smaller output(s), not shown here, which total: \(formatAmount(summary.hiddenForeignValue))\n\n"
            }
            if !summary.change.isEmpty {
                msg += "Change back:\n\(formatAmount(summary.changeTotal))\n"
                if summary.change.count == 1 {
                    msg += " - to address -\n\(LCDDisplay.showSingleAddress(summary.change[0].address))\n\n"
                } else {
                    msg += " - to addresses -\n"
                    for output in summary.change { msg += "\(LCDDisplay.showSingleAddress(output.address))\n\n" }
                }
                if summary.hiddenChangeCount > 0 {
                    msg += ".. plus \(summary.hiddenChangeCount) smaller change output(s), not shown here, which total: \(formatAmount(summary.hiddenChangeValue))\n\n"
                }
            }
        }
        msg += PSBT.approvalLocktimeSection(review.locktimeNotes)
        if !review.warnings.isEmpty {
            msg += "---WARNING---\n\n"
            for warning in review.warnings { msg += "- \(warning)\n\n" }
        }
        msg += PSBT.approvalFooter(noun: psbtApproveNoun, writeToLowerSlot: psbtInputMethod == "sd")
        return msg
    }

    private var psbtApproveNoun: String {
        PSBT.approveNoun(
            isBIP322: psbtReview?.bip322Message != nil,
            isProofOfReserves: psbtReview?.bip322IsProofOfReserves == true
        )
    }

    /// Firmware `ApproveTransaction.render_output` (`shared/auth.py`).
    func renderPSBTOutput(_ output: PSBTOutputReview) -> String {
        let val = formatAmount(output.value)
        if let data = BitcoinScript.opReturnPayload(output.scriptPubKey) {
            if data.isEmpty {
                return "\(val)\n - OP_RETURN -\nnull-data\n"
            }
            let hex = data.hexString
            var line = "\(val)\n - OP_RETURN -\n"
            if data.count > 160 {
                line += String(hex.prefix(160)) + "\n ⋯\n" + String(hex.suffix(160))
            } else {
                line += hex
                if data.allSatisfy({ (32...126).contains(Int($0)) }), let ascii = String(data: data, encoding: .ascii) {
                    line += " (ascii: \(ascii))"
                }
            }
            return line + "\n"
        }
        if BitcoinScript.address(for: output.scriptPubKey, network: network) != nil,
           BitcoinScript.classify(output.scriptPubKey) != .opReturn,
           BitcoinScript.classify(output.scriptPubKey) != .unknown {
            return "\(val)\n - to address -\n\(LCDDisplay.showSingleAddress(output.address))\n"
        }
        return "\(val)\n - to script -\n\(output.scriptPubKey.hexString)\n"
    }

    /// Firmware `verify_armored_signed_msg` / `verify_txt_sig_file`. NFC uses `digest_check=False`.
    func verifySigFile(text: String, filename: String, digestCheck: Bool = true,
                       siblingDirectory: URL? = nil) {
        _ = filename
        let result = BitcoinMessageSigner.verifyArmoredSignedMessage(
            text,
            digestCheck: digestCheck,
            formatAddress: Self.chunkAddress,
            fileBytes: { name in
                SimulatorCardStandin.fileData(named: name, extraDirectory: siblingDirectory)
            }
        )
        if let parsed = try? BitcoinMessageSigner.parseArmored(text),
           let listed = BitcoinMessageSigner.parseFileHashMessage(parsed.message),
           !listed.isEmpty {
            pendingSiblingChecks = listed
            showStory(
                title: result.title,
                body: result.body + "\n\nThe signed message lists \(listed.count) file hash(es). Press ENTER to pick those files in the Files app and check SHA256 digests.",
                onConfirm: .verifySiblingHashes
            )
        } else {
            showStory(title: result.title, body: result.body)
        }
    }
    nonisolated static func chunkAddress(_ address: String) -> String {
        var groups: [String] = []
        var rest = Substring(address)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(4)))
            rest = rest.dropFirst(4)
        }
        return groups.joined(separator: " ")
    }

    /// Simulator-only debug helper. Not a firmware Ready To Sign key and not a menu item.
    func loadDemoPSBT() {
        guard let root = rootKey else { return }
        beginWorking(.validating)
        let maxFee = preferences.maxNetworkFee.rawValue
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (PSBT?, String?) in
                do { return (try DemoPSBT.make(root: root), nil) }
                catch { return (nil, error.localizedDescription) }
            }.value
            endWorking()
            if let psbt = result.0 {
                let review = psbt.review(
                    root: root,
                    maxFeePercent: maxFee,
                    sighashChecks: !preferences.sighashWarnOnly,
                    wifKeys: wifKeys,
                    disableMultisigChecks: skipMultisigChecks,
                    utxoHistory: OutptValueCache(entries: preferences.ovc),
                    displayUnits: preferences.displayUnits
                )
                preferences.ovc = review.utxoHistory.persistedEntries
                persistPreferencesQuietly()
                if let fatal = review.fatalIssue {
                    showStory(title: PSBT.failureTitle(for: fatal), body: fatal)
                    return
                }
                currentPSBT = psbt
                psbtReview = review
                signedPSBTData = nil
                signedPSBT = nil
                finalizedTransaction = nil
                psbtSourceName = "Demo PSBT (simulator only)"
                psbtSourceURL = nil
                psbtInputChannel = .other
                psbtSignedFirstPass = true
                psbtSignedPriorMessage = nil
                psbtInputMethod = "usb"
                if screen != .psbt { navigate(to: .psbt) }
            } else { errorMessage = result.1 }
        }
    }

    func signCurrentPSBT(writeToLowerSlot: Bool = false) {
        guard currentPSBT != nil else { return }
        if let fatal = psbtReview?.fatalIssue {
            showStory(title: PSBT.failureTitle(for: fatal), body: fatal)
            return
        }
        if let sha = loadedPSBTSHA, let url = loadedPSBTURL,
           let current = try? Data(contentsOf: url), PSBT.bytesWereModified(originalSHA: sha, current: current) {
            showStory(title: "Failure", body: PSBT.transactionModifiedStory)
            return
        }
        if !gatePSBTSigning() { return }
        completePSBTSigning(writeToLowerSlot: writeToLowerSlot)
    }

    func beginMessageSigning() {
        wifSignPrivateKey = nil
        wifAddressPicker = nil
        messageAddressType = .nativeSegwit
        messageAccount = 0
        messageChange = false
        messageIndex = 0
        messagePath = ""
        messagePathLocked = false
        messageMaxLength = BitcoinMessageSigner.uxInputMaximumLength
        messageSignDoneMode = .exportPrompt
        messageAllowTabNewline = false
        messageSourceFilename = "msg_sign.txt"
        signedMessage = nil
        navigate(to: .messageSigning)
    }

    func defaultMessagePath() -> String {
        let purpose = messageAddressType.purpose
        return "m/\(purpose)'/\(network.coinType)'/\(messageAccount)'/\(messageChange ? 1 : 0)/\(messageIndex)"
    }

    func signMessage() {
        guard !messageText.isEmpty else { return }
        if wifSignPrivateKey != nil {
            presentWIFMessageApproval()
            return
        }
        guard let root = rootKey else { return }
        if !messagePathLocked {
            do {
                _ = try BitcoinMessageSigner.validate(messageText, allowTabAndNewline: messageAllowTabNewline,
                                                     maxLength: messageMaxLength)
            } catch {
                showStory(title: "", body: "Problem: \(error.localizedDescription)\n\nMessage to be signed must be a single line of ASCII text.")
                return
            }
            openMenu(.messageAddressFormat)
            return
        }
        let pathText = messagePath.isEmpty ? defaultMessagePath() : messagePath
        messagePath = pathText
        let address: String
        do {
            let path = try DerivationPath(pathText)
            let key = try root.derived(path: path)
            address = try BitcoinAddress.address(publicKey: key.publicKey, type: messageAddressType, network: root.network)
        } catch {
            present(error)
            return
        }
        do {
            _ = try BitcoinMessageSigner.validate(messageText, allowTabAndNewline: messageAllowTabNewline,
                                                 maxLength: messageMaxLength)
        } catch {
            showStory(title: "", body: "Problem: \(error.localizedDescription)\n\nMessage to be signed must be a single line of ASCII text.")
            return
        }
        showStory(title: "", body: """
        Ok to sign this?
              --=--
        \(messageText)
              --=--

        Using the key associated with address:

        \(Self.hardNotation(pathText)) =>
        \(Self.chunkAddress(address))

        \(FirmwareCopy.messageSignFooter)
        """, onConfirm: .approveMessageSign)
    }

    /// Firmware `cleanup_deriv_path` standardizes on `h` notation (utils.py).
    nonisolated static func hardNotation(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "h").replacingOccurrences(of: "p", with: "h")
    }

    func performMessageSignature() {
        if wifSignPrivateKey != nil {
            performWIFMessageSignature()
            return
        }
        guard let root = rootKey else { return }
        beginWorking(.generating)
        let text = messageText
        let pathText = messagePath.isEmpty ? defaultMessagePath() : messagePath
        let type = messageAddressType
        let deltaMode = deltaModeActive
        let allowNL = messageAllowTabNewline
        let doneMode = messageSignDoneMode
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (SignedBitcoinMessage?, String?) in
                do {
                    let path = try DerivationPath(pathText)
                    return (try BitcoinMessageSigner.sign(text, root: root, path: path, type: type,
                                                          deltaMode: deltaMode, allowTabAndNewline: allowNL), nil)
                } catch { return (nil, error.localizedDescription) }
            }.value
            endWorking()
            signedMessage = result.0
            errorMessage = result.1
            if signedMessage != nil { finishSignedMessage(mode: doneMode) }
        }
    }

    /// Firmware `msg_signing_done` / `NFC.msg_sign_done` / `qr_msg_sign_done`.
    func finishSignedMessage(mode: MessageSignDoneMode? = nil) {
        switch mode ?? messageSignDoneMode {
        case .qrDone:
            showSignedMessageQR()
        case .nfcRFC:
            shareNFCSignedMessageRFC()
        case .exportPrompt:
            presentSignedMessageExportPrompt()
        }
    }

    /// Firmware `NFC.msg_sign_done`: write RFC armor. Export prompt is the iOS stand-in.
    private func shareNFCSignedMessageRFC() {
        guard preferences.nfcSharingEnabled, let signedMessage else {
            presentSignedMessageExportPrompt()
            return
        }
        guard SimulatorNFC.isAvailable else {
            presentSignedMessageExportPrompt()
            return
        }
        SimulatorNFCWriter.shared.shareText(signedMessage.armored) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: break
            case .failure(let error):
                if let nfc = error as? SimulatorNFCError {
                    switch nfc {
                    case .cancelled: return
                    case .unavailable: self.presentSignedMessageExportPrompt()
                    case .failed(let message): self.showStory(title: "", body: message)
                    }
                } else {
                    self.showStory(title: "", body: error.localizedDescription)
                }
            }
        }
    }

    /// Firmware `msg_signing_done` → `import_export_prompt("Signed Msg")`.
    var signedMessageExportPrompt: String {
        ExportPromptBuilder.prompt(
            whatItIs: "Signed Msg",
            dualSDSlots: true,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: preferences.nfcSharingEnabled,
            qrEnabled: true,
            qwerty: true
        ) ?? ""
    }

    func presentSignedMessageExportPrompt() {
        story = StoryPresentation(
            title: "",
            body: signedMessageExportPrompt,
            onConfirm: .signedMessageExport,
            hintQR: true,
            hintNFC: preferences.nfcSharingEnabled
        )
        navigate(to: .story)
    }

    func clampMessageText() {
        if messageText.count > messageMaxLength {
            messageText = String(messageText.prefix(messageMaxLength))
        }
    }

    func exportSignedMessage() {
        guard let signedMessage else { return }
        let name = BitcoinMessageSigner.signedMessageFilename(forInputFilename: messageSourceFilename)
        prepareExport(data: Data(signedMessage.armored.utf8),
                      filename: name, type: .plainText,
                      successStory: ("File Signed", "Created new file:\n\n\(name)"))
    }

    func exportSignedMessageToCard(_ volume: SimulatorCardStandin.Volume) {
        guard let signedMessage else { return }
        let name = BitcoinMessageSigner.signedMessageFilename(forInputFilename: messageSourceFilename)
        do {
            let url = try writeCardStandin(Data(signedMessage.armored.utf8), named: name, to: volume)
            story = StoryPresentation(title: "File Signed", body: "Created new file:\n\n\(url.lastPathComponent)")
            if screen != .story { navigate(to: .story) }
        } catch { present(error) }
    }

    func shareSignedMessageNFC() {
        guard preferences.nfcSharingEnabled, let signedMessage else { return }
        SimulatorNFCWriter.shared.shareText(signedMessage.armored) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                self.showStory(title: "", body: error.localizedDescription)
            }
        }
    }

    /// Firmware `qr_msg_sign_done`: ENTER = signature QR only, (0) = full RFC BBQr.
    func showSignedMessageQR() {
        let presentation = StoryPresentation(title: "", body: FirmwareCopy.signedMessageQR, onConfirm: .signedMessageQR)
        story = presentation
        if screen != .story { navigate(to: .story) }
    }

    func addSecureNote() {
        if noteEditorMode == .changePassword {
            guard let note = selectedNote else { return }
            if notePassword == note.password {
                statusMessage = "No changes."
                openMenu(.noteActions)
                return
            }
            let npw = notePassword.isEmpty ? "<EMPTY>" : notePassword
            let opw = note.password.isEmpty ? "<EMPTY>" : note.password
            showStory(title: "Confirm Change?",
                      body: "New Password:\n\(npw)\n\nOld Password:\n\(opw)",
                      onConfirm: .confirmPasswordChange)
            return
        }
        clipNoteEditorFields()
        let title = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { errorMessage = "Enter a title."; return }
        if noteEditorMode == .editNote || noteEditorMode == .editPasswordMetadata {
            if noteGroupDraft.isEmpty { noteGroupDraft = selectedNote?.group ?? "" }
        }
        selectedNoteGroup = noteGroupDraft.isEmpty ? nil : noteGroupDraft
        history.append(screen)
        menuStack.append(currentMenu)
        currentMenu = .noteGroupPicker
        screen = .menu
        jumpMenu(to: NoteGroupPickerUX.chosenIndex(
            current: selectedNoteGroup ?? "",
            groups: notes.map(\.group)
        ))
    }

    func persistSecureNote() {
        guard var record else { return }
        clipNoteEditorFields()
        let title = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { errorMessage = "Enter a title."; return }
        let kind: SecureNoteKind = (noteEditorMode == .createPassword || noteEditorMode == .editPasswordMetadata || noteEditorMode == .changePassword) ? .password : .note
        let savedID: UUID
        if let selectedNoteID, let index = record.notes.firstIndex(where: { $0.id == selectedNoteID }) {
            record.notes[index].title = title
            record.notes[index].username = noteUsername
            record.notes[index].password = notePassword
            record.notes[index].site = noteSite
            record.notes[index].note = noteBody
            record.notes[index].kind = kind
            if noteEditorMode != .changePassword {
                record.notes[index].group = noteGroupDraft
            }
            savedID = selectedNoteID
        } else {
            let note = SecureNote(kind: kind, title: title, username: noteUsername,
                                  password: notePassword, site: noteSite, note: noteBody,
                                  group: noteGroupDraft)
            record.notes.append(note)
            savedID = note.id
        }
        self.record = record
        do { try persistRecord() }
        catch { present(error) }
        selectedNoteID = savedID
        noteTitle = ""; noteUsername = ""; notePassword = ""; noteSite = ""; noteBody = ""
        statusMessage = "Saved."
        while let last = history.last, last == .noteEditor || last == .story {
            _ = history.popLast()
        }
        if currentMenu == .noteGroupPicker {
            currentMenu = menuStack.popLast() ?? .notes
        }
        if !noteGroupDraft.isEmpty {
            selectedNoteGroup = noteGroupDraft
            if currentMenu != .noteGroup && currentMenu != .noteActions {
                menuStack.append(currentMenu)
                currentMenu = .noteGroup
            }
        }
        if currentMenu != .noteActions {
            menuStack.append(currentMenu)
        }
        currentMenu = .noteActions
        if menuStack.last == .noteGroup {
            history.append(.menu)
        }
        screen = .menu
        selectedMenuIndex = 0
    }

    private func clipNoteEditorFields() {
        noteTitle = String(noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SecureNotesSupport.oneLineLimit))
        noteUsername = String(noteUsername.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SecureNotesSupport.oneLineLimit))
        noteSite = String(noteSite.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SecureNotesSupport.oneLineLimit))
        if notePassword.count > SecureNotesSupport.passwordLimit {
            notePassword = String(notePassword.prefix(SecureNotesSupport.passwordLimit))
        }
    }

    func pickNoteGroup(_ group: String) {
        noteGroupDraft = String(group.prefix(SecureNotesSupport.oneLineLimit))
        if let existing = selectedNote, noteEditorMode == .editNote || noteEditorMode == .editPasswordMetadata {
            let changes = noteEditChanges(from: existing, group: noteGroupDraft)
            if changes.isEmpty {
                statusMessage = "No changes."
                openMenu(.noteActions)
                return
            }
            showStory(title: "", body: "Save changes?\n- " + changes.joined(separator: "\n- "),
                      onConfirm: .confirmNoteEdits)
            return
        }
        persistSecureNote()
    }

    private func noteEditChanges(from existing: SecureNote, group: String) -> [String] {
        var changes: [String] = []
        if existing.title != noteTitle { changes.append("Title") }
        if existing.kind == .password {
            if existing.site != noteSite { changes.append("Site Name") }
            if existing.username != noteUsername { changes.append("Username") }
            if existing.note != noteBody { changes.append("Other Notes") }
        } else if existing.note != noteBody {
            changes.append("Note Text")
        }
        if existing.group != group { changes.append("Group") }
        return changes
    }

    func deleteSecureNote(id: UUID) {
        guard pendingNoteDelete else {
            pendingNoteDelete = true
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.notesDelete, onConfirm: .deleteNote)
            return
        }
        pendingNoteDelete = false
        guard var record else { return }
        record.notes.removeAll { $0.id == id }
        self.record = record
        do { try persistRecord() }
        catch { present(error) }
        selectedNoteID = nil
        statusMessage = "Deleted."
        openMenu(.notes)
    }

    func exportNotes(all: Bool) {
        pendingNoteExportAll = all
        let payload = notesPayloadForExport()
        let item = SecureNotes.exportItemLabel(
            count: payload.count,
            kind: payload.count == 1 ? (payload.first?.kind == .password ? "password" : "note") : nil
        )
        showStory(
            title: SecureNotes.exportTitle,
            body: SecureNotes.exportPrompt(item: item, virtualDiskEnabled: virtualDiskEnabled),
            onConfirm: .exportNotesFile,
            hintQR: true
        )
    }

    func writeNotesExport(qr: Bool, destination: AddressExportDestination = .sdCard) {
        let payload = notesPayloadForExport()
        guard !payload.isEmpty else { return }
        guard let data = try? SecureNotes.encodeNotesJSON(payload.map { $0.firmwareRecord() }) else { return }
        if qr {
            presentBBQr(title: SecureNotes.bbqrExportTitle, data: data, fileType: .json)
            return
        }
        pendingNotesJSON = data
        pendingNotesFilename = SecureNotes.jsonFilename(
            all: pendingNoteExportAll,
            isPassword: payload.first?.kind == .password
        )
        pendingNotesExportDestination = destination
        pendingNotesFileExport = true
        if let saved = storedBackupPassword {
            showStory(title: SecureNotes.exportTitle,
                      body: BackupFile.reusePasswordStory(saved),
                      onConfirm: .reuseBackupPassword)
            return
        }
        generateNewBackupPassword()
    }

    private func notesPayloadForExport() -> [SecureNote] {
        pendingNoteExportAll ? notes : notes.filter { $0.id == selectedNoteID }
    }

    func writeEncryptedNotesExport() {
        guard let json = pendingNotesJSON else { return }
        let password = backupPassword
        guard !password.isEmpty else { errorMessage = "Missing backup password."; return }
        beginWorking(.saving)
        let jsonName = pendingNotesFilename
        let destination = pendingNotesExportDestination
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String, String?) in
                do {
                    let salt = try SecureRandom.bytes(count: 16)
                    let iv = try SecureRandom.bytes(count: 16)
                    let word = BIP39EnglishWords.all.randomElement() ?? "able"
                    let inner = "\(word)\(Int.random(in: 0..<1000)).json"
                    let archive = try Compat7z.encrypt(
                        plaintext: json,
                        password: password,
                        innerName: inner,
                        salt: salt,
                        iv: iv
                    )
                    return (archive, SecureNotes.sevenZipFilename(jsonName: jsonName), nil)
                } catch {
                    return (nil, jsonName, error.localizedDescription)
                }
            }.value
            endWorking()
            if pendingCacheBackupPassword {
                rememberBackupPassword(password)
                pendingCacheBackupPassword = false
            }
            pendingNotesFileExport = false
            pendingNotesJSON = nil
            guard let data = result.0 else {
                errorMessage = result.2
                return
            }
            emitNotesExport(data: data, filename: result.1, type: .data, encrypted: true, destination: destination)
        }
    }

    func writeNotesJSONAndSignature() {
        guard let json = pendingNotesJSON else { return }
        let filename = pendingNotesFilename
        let destination = pendingNotesExportDestination
        pendingNotesFileExport = false
        pendingNotesJSON = nil
        emitNotesExport(data: json, filename: filename, type: .json, encrypted: false, destination: destination)
    }

    private func emitNotesExport(
        data: Data,
        filename: String,
        type: UTType,
        encrypted: Bool,
        destination: AddressExportDestination
    ) {
        let sigName = encrypted ? nil : BitcoinMessageSigner.signatureFilename(forInputFilename: filename)
        let story = SecureNotes.successStory(encrypted: encrypted, filename: filename, signatureFilename: sigName)
        switch destination {
        case .sdCard:
            if !encrypted { queueDetachedSignature(for: data, filename: filename) }
            prepareExport(data: data, filename: filename, type: type,
                          successStory: (title: "", body: story))
        case .lowerSlot:
            writeNotesToCard(data: data, filename: filename, signatureName: sigName, volume: .microSD, story: story)
        case .virtDisk:
            writeNotesToCard(data: data, filename: filename, signatureName: sigName, volume: .virtDisk, story: story)
        }
    }

    private func writeNotesToCard(
        data: Data,
        filename: String,
        signatureName: String?,
        volume: SimulatorCardStandin.Volume,
        story: String
    ) {
        do {
            _ = try writeCardStandin(data, named: filename, to: volume)
            if let signatureName, let root = rootKey {
                let message = BitcoinMessageSigner.fileHashMessage(hashesAndNames: [(SHA2.sha256(data), filename)])
                let coin = root.network.coinType
                if let path = try? DerivationPath("m/44h/\(coin)h/0h/0/0"),
                   let signed = try? BitcoinMessageSigner.sign(message, root: root, path: path, type: .legacy) {
                    _ = try writeCardStandin(Data(signed.armored.utf8), named: signatureName, to: volume)
                }
            }
            showStory(title: "", body: story)
        } catch { present(error) }
    }

    func startImportNotes() {
        importPurpose = .notes
        showStory(
            title: SecureNotes.importTitle,
            body: SecureNotes.importPrompt(virtualDiskEnabled: virtualDiskEnabled),
            onConfirm: .importNotesSource,
            hintQR: true
        )
    }

    func importNotes(data: Data, filename: String = "") {
        if !filename.isEmpty {
            let listed = SecureNotes.isImportCandidate(filename: filename, data: data)
                || Compat7z.isFirmware7z(data)
            guard SecureNotes.isImportSizeOK(data.count), listed else {
                showStory(title: "Failure", body: SecureNotes.incorrectFormatMessage)
                return
            }
        }
        if Compat7z.isFirmware7z(data) {
            pendingEncryptedNotesData = data
            backupPassword = ""
            showStory(title: SecureNotes.customPWDTitle, body: SecureNotes.customPWDBody,
                      onConfirm: .notesCustomPWD)
            return
        }
        if (try? JSONDecoder().decode(BackupEnvelope.self, from: data)) != nil {
            pendingEncryptedNotesData = data
            backupPassword = ""
            showStory(title: BackupFile.customPasswordTitle,
                      body: BackupFile.customPasswordStory,
                      onConfirm: .notesCustomPassword)
            return
        }
        importNotesJSON(data)
    }

    func beginNotesCustomPassword() {
        textEntryIsNotesImportPassword = true
        passphraseInput = ""
        navigate(to: .passphrase)
    }

    func commitNotesImportPassword() {
        let password = passphraseInput
        guard password.count >= SecureNotes.customPasswordMinLength else { return }
        textEntryIsNotesImportPassword = false
        passphraseInput = ""
        backupPassword = password
        decryptAndImportNotes()
    }

    func decryptAndImportNotes() {
        guard let data = pendingEncryptedNotesData else { return }
        if Compat7z.isFirmware7z(data) {
            do {
                let decoded = try Compat7z.decrypt(data, password: backupPassword)
                pendingEncryptedNotesData = nil
                importNotesJSON(decoded.plaintext)
            } catch let error as Compat7zError {
                let body: String
                if error == .wrongPassword {
                    body = SecureNotes.decryptFailureMessage(password: backupPassword)
                } else {
                    body = error.firmwareMessage
                }
                showStory(title: "FAILED", body: body)
            } catch {
                showStory(title: "FAILED", body: error.localizedDescription)
            }
            return
        }
        do {
            let clear = try BackupCrypto.decryptBytes(data, password: backupPassword)
            pendingEncryptedNotesData = nil
            importNotesJSON(clear)
            statusMessage = (statusMessage ?? "") + " " + SecureNotes.savedPause
        } catch SecureServiceError.wrongPassword {
            showStory(title: "FAILED", body: BackupFile.decryptFailed(tried: backupPassword))
        } catch {
            showStory(title: "FAILED", body: error.localizedDescription)
        }
    }

    func importNotesFromVolume(_ volume: SimulatorCardStandin.Volume) {
        if volume == .virtDisk, !virtualDiskEnabled { return }
        let files = SimulatorCardStandin.listRootFiles(
            on: volume,
            minSize: SecureNotes.importMinSize,
            maxSize: SecureNotes.importMaxSize
        ).filter { file in
            guard let data = try? Data(contentsOf: file.url) else { return false }
            return SecureNotes.isImportCandidate(filename: file.filename, data: data)
        }
        guard !files.isEmpty else {
            showStory(title: "", body: FirmwareCopy.noSuitableFiles)
            return
        }
        if files.count == 1, let file = files.first, let data = try? Data(contentsOf: file.url) {
            importNotes(data: data, filename: file.filename)
            return
        }
        listedFilesAreNotesImport = true
        listedDiskFiles = files
        openMenu(.listedFiles)
    }

    func pickNotesFromFiles() {
        importPurpose = .notes
        showFileImporter = true
    }

    func handleNotesStoryKey(_ value: String) -> Bool {
        if story.onConfirm == .exportNotesFile {
            switch value.lowercased() {
            case "1":
                writeNotesExport(qr: false, destination: .sdCard)
                return true
            case "b":
                writeNotesExport(qr: false, destination: .lowerSlot)
                return true
            case "2":
                if virtualDiskEnabled { writeNotesExport(qr: false, destination: .virtDisk) }
                return true
            default:
                return false
            }
        }
        if story.onConfirm == .importNotesSource {
            switch value.lowercased() {
            case "1":
                pickNotesFromFiles()
                return true
            case "b":
                importNotesFromVolume(.microSD)
                return true
            case "2":
                importNotesFromVolume(.virtDisk)
                return true
            default:
                return false
            }
        }
        if story.onConfirm == .notesCustomPWD, value == "1" {
            beginNotesCustomPassword()
            return true
        }
        return false
    }

    func handleNotesQRKey() -> Bool {
        guard screen == .story else { return false }
        if story.onConfirm == .exportNotesFile {
            writeNotesExport(qr: true)
            return true
        }
        if story.onConfirm == .importNotesSource {
            importPurpose = .notes
            showScanner = true
            return true
        }
        return false
    }

    private func importNotesJSON(_ data: Data) {
        do {
            let imported: [SecureNote]
            if let rows = try? SecureNotes.decodeNotesJSON(data) {
                imported = rows.map(SecureNote.fromFirmwareRecord)
            } else if let legacy = try? JSONDecoder().decode([SecureNote].self, from: data) {
                imported = legacy
            } else {
                throw SecureNotesImportError.incorrectFormat
            }
            guard var record else { return }
            record.notes.append(contentsOf: imported)
            self.record = record
            try persistRecord()
            preferences.secnapEnabled = true
            persistPreferencesQuietly()
            statusMessage = SecureNotes.savedPause
            showStory(title: "", body: SecureNotes.savedPause)
            openMenu(.notes)
        } catch {
            showStory(title: "Failure", body: SecureNotes.incorrectFormatMessage)
        }
    }

    func sortNotes() {
        guard var record else { return }
        record.notes.sort { SecureNotes.compareTitles($0.title, $1.title) }
        self.record = record
        try? persistRecord()
    }

    func signSelectedNote() {
        guard let note = selectedNote, note.canSignMisc else { return }
        messageText = note.note
        beginMessageSigning()
        messageMaxLength = BitcoinMessageSigner.maximumLength
        messageSourceFilename = "msg_sign.txt"
        messageText = note.note
    }

    func saveSettings() {
        guard var record else { return }
        let nickname = settingsNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        record.nickname = String(nickname.prefix(100))
        record.network = settingsNetwork
        record.preferences = preferences
        self.record = record
        persistPreloginSettings()
        do {
            try persistRecord()
            if isUnlocked { try rebuildRoot() }
            statusMessage = "Settings saved."
        } catch { present(error) }
    }

    func persistPreferencesQuietly() {
        persistPreloginSettings()
        guard var record else { return }
        record.preferences = preferences
        self.record = record
        try? persistRecord()
    }

    func startKeyboardTest() {
        textEntryIsKeyboardTest = true
        passphraseInput = ""
        navigate(to: .passphrase)
    }

    func finishKeyboardTest() {
        textEntryIsKeyboardTest = false
        passphraseInput = ""
        back()
    }

    func startNFCTest() {
        let text = DeveloperDebug.nfcTestText(uid: DeveloperDebug.simulatorNFCUID)
        SimulatorNFCWriter.shared.shareText(text) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.showStory(title: "", body: text)
            case .failure(let error):
                let note: String
                if case SimulatorNFCError.unavailable = error {
                    note = FirmwareCopy.nfcSessionUnavailable
                } else {
                    note = error.localizedDescription
                }
                self.showStory(title: "", body: text + "\n\n" + note)
            }
        }
    }

    /// Firmware `mk4.dev_enable_repl` plus an in-app serial REPL console stand-in.
    func startSerialREPL() {
        switch DeveloperDebug.serialREPLStart(
            deltaMode: deltaModeActive,
            isDevMode: isDevMode || DeveloperDebug.unixSimulatorIsDevMode
        ) {
        case .wipeDelta:
            _ = wipeIfDeltaMode()
        case .noopNotDevMode:
            break
        case .showEnabledStory:
            serialREPL.enable()
            showStory(title: "", body: DeveloperDebug.serialREPLEnabledStory, onConfirm: .openSerialREPL)
        }
    }

    func submitSerialREPL() {
        _ = serialREPL.submit(serialREPLInput)
        serialREPLInput = ""
    }

    /// Firmware `actions.check_firewall_read`: a working firewall resets; a miss hits `assert False`.
    func startCheckFirewallRead() {
        switch DeveloperDebug.checkFirewallRead(firewallIntact: true) {
        case .blockedReset:
            warmReset()
        case .assertionReached:
            showStory(title: DeveloperDebug.yikesTitle, body: DeveloperDebug.firewallAssertBody,
                      onConfirm: .warmResetAfterCrash)
        }
    }

    /// Firmware `gpu.reflash_gpu_ux` confirm story.
    func startReflashGPU() {
        showStory(title: "", body: DeveloperDebug.gpuReflashConfirm(current: gpuVersion),
                  onConfirm: .reflashGPU)
    }

    func performReflashGPU() {
        back()
        Task { @MainActor in
            await dramaticPause(DeveloperDebug.gpuReflashBusyTitle, seconds: 1.0)
            switch DeveloperDebug.reflashGPU(succeed: true) {
            case .success(let version):
                gpuVersion = version
                showStory(title: "", body: DeveloperDebug.gpuReflashSuccess(version: version))
            case .failure(let detail):
                showStory(title: "", body: DeveloperDebug.gpuReflashFailure(detail: detail))
            }
        }
    }

    func showBKPWOverrideStory() {
        let presentation = StoryPresentation(
            title: DeveloperDebug.bkpwOverrideTitle,
            body: DeveloperDebug.bkpwOverrideBody(hasPassword: storedBackupPassword != nil),
            onConfirm: .bkpwOverride
        )
        if screen == .story {
            story = presentation
            return
        }
        story = presentation
        navigate(to: .story)
    }

    func beginBKPWPasswordEntry() {
        textEntryIsBKPWOverride = true
        passphraseInput = storedBackupPassword ?? ""
        navigate(to: .passphrase)
    }

    func commitBKPWOverride() {
        let npwd = passphraseInput
        guard npwd.count >= DeveloperDebug.bkpwMinLength else { return }
        if npwd == storedBackupPassword {
            textEntryIsBKPWOverride = false
            passphraseInput = ""
            returnToBKPWOverrideStory()
            return
        }
        rememberBackupPassword(npwd)
        textEntryIsBKPWOverride = false
        passphraseInput = ""
        statusMessage = DeveloperDebug.savedPause
        returnToBKPWOverrideStory()
    }

    private func returnToBKPWOverrideStory() {
        if screen == .passphrase, !history.isEmpty {
            screen = history.removeLast()
        }
        showBKPWOverrideStory()
    }

    func deleteStoredBackupPassword() {
        preferences.bkpw = nil
        preferences.lastBackupPassword = []
        persistPreferencesQuietly()
        statusMessage = DeveloperDebug.deletedPause
        showBKPWOverrideStory()
    }

    private func rememberBackupPassword(_ password: String) {
        preferences.bkpw = password
        let words = password.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count == 12 {
            preferences.lastBackupPassword = words
        }
        persistPreferencesQuietly()
    }

    /// Firmware `SettingsObject.prelogin()`: `kbtn` / `rngk` / `lgto` live outside the PIN.
    private func persistPreloginSettings() {
        if preferences.killKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.preloginKillKeyDefaultsKey)
        } else {
            UserDefaults.standard.set(preferences.killKey, forKey: Self.preloginKillKeyDefaultsKey)
        }
        UserDefaults.standard.set(preferences.scrambleKeys, forKey: Self.preloginScrambleDefaultsKey)
        UserDefaults.standard.set(preferences.loginCountdownMinutes, forKey: Self.preloginCountdownDefaultsKey)
        persistFactoryStandIn()
    }

    private func applyPreloginSettingsOverlay() {
        if let kbtn = UserDefaults.standard.string(forKey: Self.preloginKillKeyDefaultsKey) {
            preferences.killKey = kbtn
        }
        if UserDefaults.standard.object(forKey: Self.preloginScrambleDefaultsKey) != nil {
            preferences.scrambleKeys = UserDefaults.standard.bool(forKey: Self.preloginScrambleDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: Self.preloginCountdownDefaultsKey) != nil {
            preferences.loginCountdownMinutes = UserDefaults.standard.integer(forKey: Self.preloginCountdownDefaultsKey)
        }
        applyFactoryStandInFromDefaults()
        persistPreloginSettings()
    }

    /// Q `KEY_CANCEL` on the PIN screen (`login.py`); Backspace is a separate key.
    private func applyUnlockPINCancel() {
        let hasPrefix = unlockPhase == .suffix && !pinPrefix.isEmpty
        switch LoginUX.pinCancelAction(currentPart: pinInput, hasPrefix: hasPrefix) {
        case .stay:
            break
        case .resetToPrefix:
            pinPrefix = ""
            pinInput = ""
            unlockPhase = .prefix
        case .clearCurrentPart:
            pinInput = ""
        }
    }

    private func applyUnlockPINDelete() {
        let prefix = unlockPhase == .suffix ? pinPrefix : nil
        let next = LoginUX.applyDelete(PINEntryState(prefix: prefix, current: pinInput))
        if next.prefix == nil {
            pinPrefix = ""
            pinInput = next.current
            unlockPhase = .prefix
        } else {
            pinPrefix = next.prefix ?? ""
            pinInput = next.current
        }
    }

    private func applyPINSetupDelete() {
        switch pinSetupPhase {
        case .prefix, .confirmPrefix:
            let next = LoginUX.applyDelete(PINEntryState(prefix: nil, current: pinPrefix))
            pinPrefix = next.current
        case .suffix, .confirmSuffix:
            let next = LoginUX.applyDelete(PINEntryState(prefix: pinPrefix, current: pinInput))
            if next.prefix == nil {
                pinPrefix = next.current
                pinInput = ""
                pinSetupPhase = pinSetupPhase == .confirmSuffix ? .confirmPrefix : .prefix
            } else {
                pinInput = next.current
            }
        case .warning, .proveRead:
            break
        }
    }

    private var killKeyContext: LoginKillContext {
        switch screen {
        case .nicknameSplash: .nicknameSplash
        case .unlock: .pinEntry
        case .loginCountdown: .loginCountdown
        case .pinSetup: .pinSetting
        default: .other
        }
    }

    func applyNetwork(_ network: BitcoinNetwork) {
        if network == .mainnet, settingsNetwork != .mainnet {
            showStory(title: "Testnet Mode", body: """
            Switching to Bitcoin mainnet.

            \(FirmwareCopy.mainnetNotHardwareWallet)

            Press ENTER to continue, CANCEL to stop.
            """, onConfirm: .applyMainnet)
            return
        }
        settingsNetwork = network
        saveSettings()
        back()
    }

    func startBackupSystem() {
        if wipeIfDeltaMode() { return }
        // Firmware offers reusing the cached backup password (`backups.py`); OK reuses it,
        // cancel/back falls through to picking a fresh 12-word password.
        if let saved = storedBackupPassword {
            showStory(title: "",
                      body: BackupFile.reusePasswordStory(saved),
                      onConfirm: .reuseBackupPassword)
            return
        }
        generateNewBackupPassword()
    }

    func generateNewBackupPassword() {
        beginWorking(.generating)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> [String]? in
                guard let entropy = try? SecureRandom.bytes(count: 32),
                      let mnemonic = try? BIP39Mnemonic(entropy: entropy) else { return nil }
                return Array(mnemonic.words.prefix(12))
            }.value
            endWorking()
            guard let words = result else { errorMessage = "Unable to generate backup password."; return }
            backupPasswordWords = words
            backupPassword = words.joined(separator: " ")
            backupConfirmPassword = backupPassword
            seedAcknowledged = false
            navigate(to: .backupPassword)
        }
    }

    func continueBackupPassword() {
        startWordQuiz(words: backupPasswordWords, backupPassword: true)
    }

    /// ENTER / Confirm on the verify-backup password screen (notes decrypt, restore, or CRC check).
    func confirmVerifyBackupPassword() {
        if pendingEncryptedNotesData != nil {
            decryptAndImportNotes()
        } else if pendingBackupRestoreData != nil {
            decryptPendingRestore()
        } else if importPurpose == .backup {
            showFileImporter = true
        } else {
            requestVerifyBackup()
        }
    }

    private func finishBackupPasswordExport() {
        if pendingNotesFileExport {
            writeEncryptedNotesExport()
        } else {
            createEncryptedBackup()
        }
    }

    private func createEncryptedBackup() {
        let password = backupPassword
        guard !password.isEmpty else { errorMessage = "Missing backup password."; return }
        let text: String
        do { text = try currentBackupText() }
        catch { present(error); return }
        beginWorking(.saving)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String?) in
                do { return (try BackupCrypto.encryptBytes(Data(text.utf8), password: password, innerExt: "txt"), nil) }
                catch { return (nil, error.localizedDescription) }
            }.value
            endWorking()
            if let data = result.0 {
                if pendingCacheBackupPassword {
                    rememberBackupPassword(password)
                    pendingCacheBackupPassword = false
                }
                presentWrittenBackup(data: data, filename: BackupFile.encryptedFilename, type: .sevenZip,
                                     allowCopies: true)
            } else { errorMessage = result.1 }
        }
    }

    func restoreBackup(data: Data, filename: String = "") {
        if hasSeed, !restoreAsEphemeral, !pendingEphemeral {
            showStory(title: "Restore Backup", body: FirmwareCopy.needClearSeed)
            return
        }
        let name = filename.isEmpty ? pendingBackupRestoreFilename : filename
        if restoreBackupAllowsCleartext {
            if BackupFile.isCleartextBackupFilename(name) || BackupFile.looksLikeBackupText(data) {
                acceptCleartextRestore(data: data, filename: name)
                return
            }
            if BackupFile.isEncryptedBackupFilename(name) || (try? JSONDecoder().decode(BackupEnvelope.self, from: data)) != nil {
                pendingBackupRestoreData = data
                pendingBackupRestoreFilename = name
                beginCustomBackupPasswordEntry()
                return
            }
            showStory(title: "FAILED", body: BackupFile.unableToOpenPath(name.isEmpty ? "backup" : name))
            return
        }
        if !name.isEmpty, !BackupFile.isEncryptedBackupFilename(name) {
            showStory(title: "FAILED", body: BackupFile.unableToOpenPath(name))
            return
        }
        pendingBackupRestoreData = data
        pendingBackupRestoreFilename = name
        if backupPassword.isEmpty {
            beginBackupPasswordEntry()
            return
        }
        decryptPendingRestore()
    }

    private func acceptCleartextRestore(data: Data, filename: String) {
        do {
            let payload = try Self.payloadFromClearBytes(data)
            presentRestoreFingerprint(payload)
        } catch {
            showStory(title: "FAILED", body: error.localizedDescription)
        }
    }

    private func decryptPendingRestore() {
        guard let data = pendingBackupRestoreData else { return }
        let password = backupPassword
        let filename = pendingBackupRestoreFilename
        beginWorking(.loading)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String?) in
                do {
                    let clear: Data
                    if BackupFile.looksLikeBackupText(data) {
                        clear = data
                    } else {
                        do {
                            clear = try BackupCrypto.decryptBytes(data, password: password)
                        } catch SecureServiceError.wrongPassword {
                            return (nil, BackupFile.decryptFailed(tried: password))
                        } catch SecureServiceError.invalidBackup {
                            return (nil, BackupFile.touchedFileError("headers"))
                        }
                    }
                    return (clear, nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            endWorking()
            if let clear = result.0 {
                do {
                    let payload = try SimulatorStore.payloadFromClearBytes(clear)
                    pendingBackupRestoreData = nil
                    presentRestoreFingerprint(payload)
                } catch {
                    showStory(title: "FAILED", body: error.localizedDescription)
                }
            } else {
                showStory(title: "FAILED", body: result.1 ?? BackupFile.unableToOpenPath(filename))
            }
        }
    }

    private func presentRestoreFingerprint(_ payload: WalletBackupPayload) {
        do {
            let key = try Self.rootKey(fromBackup: payload)
            pendingRestorePayload = payload
            let asTemporary = restoreAsEphemeral || pendingEphemeral
            showStory(title: BackupFile.restoreTitle(xfp: key.fingerprintHex),
                      body: asTemporary ? FirmwareCopy.restoreBackupAsTemporary : FirmwareCopy.restoreBackupAsMaster,
                      onConfirm: .confirmRestoreBackup)
        } catch {
            showStory(title: "FAILED", body: BackupFile.decodeRawSecretFailed(error.localizedDescription))
        }
    }

    private func commitPendingRestore() {
        guard let payload = pendingRestorePayload else { return }
        pendingRestorePayload = nil
        pendingRestoreTrickPins = payload.trickPins
        do {
            if !payload.mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pendingMnemonic = try BIP39Mnemonic(phrase: payload.mnemonic)
                pendingExtendedKey = nil
            } else if let xprv = payload.extendedPrivateKey, !xprv.isEmpty {
                pendingExtendedKey = xprv
                pendingMnemonic = nil
            } else {
                throw SimulatorInputError.missingSeed
            }
            pendingNotes = payload.notes
            pendingWIFKeys = payload.wifKeys
            if restoreAsEphemeral || pendingEphemeral {
                restoreAsEphemeral = false
                if ephemeralOrigin.isEmpty || ephemeralOrigin == "unknown origin" {
                    ephemeralOrigin = "Coldcard Backup"
                }
                if var record {
                    record.wifKeys = payload.wifKeys
                    self.record = record
                    try persistRecord()
                }
                try applyEphemeralSeed()
                return
            }
            settingsNetwork = payload.network
            settingsNickname = payload.nickname
            if let restored = payload.preferences {
                preferences = restored
                preferences.sd2faNonces = []
            }
            if hasPIN {
                try commitSeedOntoExistingPIN()
                restorePendingTrickPinsIfNeeded()
            }
            else { beginPINSetup(isChange: false) }
            showStory(title: "Success!",
                      body: "Everything has been successfully restored. We must now reboot to install the updated settings and seed.\n\n(Simulator continues without a reboot.)")
        } catch { present(error) }
    }

    func verifyBackupFile(data: Data, filename: String = "") {
        if !filename.isEmpty, !BackupFile.isEncryptedBackupFilename(filename) {
            showStory(title: "", body: BackupFile.verifyFailure(problem: BackupFile.unableToOpen, error: filename))
            return
        }
        do {
            try BackupCrypto.verifyEnvelope(data)
            showStory(title: "Verify Backup", body: BackupFile.crcOKStory)
        } catch let error as SecureServiceError {
            switch error {
            case .truncatedHeaders:
                showStory(title: "", body: BackupFile.verifyFailure(problem: BackupFile.unableToReadHeaders, error: "headers"))
            case .verifyFailed(let detail):
                showStory(title: "", body: BackupFile.verifyFailure(problem: BackupFile.unableToVerifyContents, error: detail))
            default:
                showStory(title: "", body: BackupFile.verifyFailure(problem: BackupFile.unableToOpen, error: error.localizedDescription))
            }
        } catch {
            showStory(title: "", body: BackupFile.verifyFailure(problem: BackupFile.unableToReadHeaders, error: error.localizedDescription))
        }
    }

    func runSelfTests() {
        selftestInProgress = true
        selftestFill = nil
        selftestLED = .off
        selftestExpectedKey = nil
        selftestAwaitingNFCShare = false
        selftestAllowsSkip = false
        selftestAllowsEnter = true
        selftestAbortReason = QSelftest.confirmAbortReason
        // Q has NFC hardware (`version.has_nfc`); Settings NFC Sharing does not gate this.
        selftestQueue = QSelftest.qSequence(hasNFC: true)
        if screen != .story {
            navigate(to: .story)
        }
        advanceSelftest()
    }

    func submitSelftestKey(_ key: String) {
        _ = consumeSelftestToken(key)
    }

    private func advanceSelftest() {
        guard selftestInProgress else { return }
        selftestExpectedKey = nil
        selftestFill = nil
        selftestLED = .off
        selftestAwaitingNFCShare = false
        selftestAllowsSkip = false
        selftestAllowsEnter = true
        selftestAbortReason = QSelftest.confirmAbortReason
        guard !selftestQueue.isEmpty else {
            finishSelftestPass()
            return
        }
        let step = selftestQueue.removeFirst()
        if step.source == "test_secure_element",
           let reason = QSelftest.secureElementBlockedReason(isBricked: isBricked) {
            failSelftest(reason)
            return
        }
        applySelftestStepChrome(step)
        switch step.interaction {
        case .confirm:
            presentSelftestConfirm(step)
        case .keyboard:
            presentSelftestKeyboard(step)
        case .auto:
            presentSelftestAuto(step)
        case .nfcShare:
            presentSelftestNFCShare(step)
        }
    }

    private func applySelftestStepChrome(_ step: QSelftest.Step) {
        selftestFill = step.fill
        selftestLED = step.led
        selftestAllowsSkip = step.allowsSkip
        selftestAllowsEnter = step.allowsEnter
        selftestAbortReason = step.abortReason
        selftestAwaitingNFCShare = step.interaction == .nfcShare
        selftestExpectedKey = step.keyboardKey
    }

    private func presentSelftestConfirm(_ step: QSelftest.Step) {
        story = StoryPresentation(
            title: step.title,
            body: step.body,
            onConfirm: .continueSelftest
        )
        screen = .story
    }

    private func presentSelftestKeyboard(_ step: QSelftest.Step) {
        story = StoryPresentation(title: step.title, body: step.body)
        screen = .story
    }

    private func presentSelftestAuto(_ step: QSelftest.Step) {
        story = StoryPresentation(title: step.title, body: step.body)
        screen = .story
        switch step.source {
        case "test_psram":
            runSelftestPSRAM()
        case "test_microsd":
            runSelftestMicroSD()
        case "test_secure_element":
            runSelftestSecureElementWait()
        default:
            advanceSelftest()
        }
    }

    private func presentSelftestNFCShare(_ step: QSelftest.Step) {
        story = StoryPresentation(
            title: step.title,
            body: step.body,
            onConfirm: .continueSelftest,
            hintNFC: true
        )
        screen = .story
        attemptSelftestNFCShare(autoAdvanceOnSuccess: SimulatorNFC.isAvailable)
    }

    private func attemptSelftestNFCShare(autoAdvanceOnSuccess: Bool) {
        let text = DeveloperDebug.nfcTestText(uid: DeveloperDebug.simulatorNFCUID)
        guard SimulatorNFC.isAvailable else { return }
        SimulatorNFCWriter.shared.shareText(text) { [weak self] result in
            guard let self, self.selftestInProgress, self.selftestAwaitingNFCShare else { return }
            switch result {
            case .success:
                if autoAdvanceOnSuccess {
                    self.advanceSelftest()
                }
            case .failure(let error):
                if let nfc = error as? SimulatorNFCError, case .cancelled = nfc {
                    self.failSelftest(QSelftest.nfcAbortReason)
                }
            }
        }
    }

    func completeSelftestNFCShare() {
        guard selftestInProgress, selftestAwaitingNFCShare else { return }
        if SimulatorNFC.isAvailable {
            attemptSelftestNFCShare(autoAdvanceOnSuccess: true)
        } else {
            // iOS Simulator has no Core NFC; NFC key stands in for RF activity.
            advanceSelftest()
        }
    }

    private func finishSelftestPass() {
        clearSelftestRuntime()
        preferences.tested = true
        persistPreferencesQuietly()
        story = StoryPresentation(title: QSelftest.passTitle, body: QSelftest.passBody)
        screen = .story
    }

    private func failSelftest(_ reason: String) {
        clearSelftestRuntime()
        story = StoryPresentation(title: QSelftest.failTitle, body: QSelftest.failBody(reason))
        screen = .story
    }

    private func clearSelftestRuntime() {
        selftestInProgress = false
        selftestQueue = []
        selftestExpectedKey = nil
        selftestFill = nil
        selftestLED = .off
        selftestAwaitingNFCShare = false
        selftestAllowsSkip = false
        selftestAllowsEnter = true
        selftestAbortReason = QSelftest.confirmAbortReason
    }

    private func consumeSelftestKey(_ key: HardwareKey) -> Bool {
        guard selftestInProgress else { return false }
        if isWorking {
            return key != .power
        }
        switch key {
        case .power:
            return false
        case .enter:
            return consumeSelftestToken("ENTER")
        case .cancel:
            return consumeSelftestToken("CANCEL")
        case .qr:
            return consumeSelftestToken("QR")
        case .nfc:
            return consumeSelftestToken("NFC")
        case .space:
            return consumeSelftestToken(" ")
        case .character(let value):
            let mapped = applyShift(value)
            if mapped.isEmpty { return true }
            return consumeSelftestToken(mapped)
        case .shift, .symbol:
            return false
        default:
            return selftestExpectedKey != nil || story.onConfirm == .continueSelftest
        }
    }

    private func consumeSelftestToken(_ token: String) -> Bool {
        guard selftestInProgress else { return false }
        if let expected = selftestExpectedKey {
            if token == "CANCEL" {
                failSelftest(QSelftest.keyboardAbortReason)
                return true
            }
            let matched: Bool
            if expected == "QR" {
                matched = token == "QR"
            } else if expected == " " {
                matched = token == " "
            } else {
                matched = token.lowercased() == expected.lowercased()
            }
            if matched {
                advanceSelftest()
            }
            return true
        }
        if selftestAwaitingNFCShare {
            if token == "NFC" {
                completeSelftestNFCShare()
                return true
            }
            if token == "CANCEL" || token.lowercased() == "x" {
                failSelftest(QSelftest.nfcAbortReason)
                return true
            }
            return true
        }
        if story.onConfirm == .continueSelftest {
            if selftestAllowsSkip, token.lowercased() == QSelftest.batterySkipKey {
                advanceSelftest()
                return true
            }
            if token == "ENTER" || token.lowercased() == "y" {
                if selftestAllowsEnter {
                    confirmStory()
                }
                return true
            }
            if token == "CANCEL" || token.lowercased() == "x" {
                failSelftest(selftestAbortReason)
                return true
            }
            return true
        }
        return false
    }

    private func runSelftestSecureElementWait() {
        beginWorking(.wait)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard selftestInProgress else { return }
            endWorking()
            advanceSelftest()
        }
    }

    private func runSelftestPSRAM() {
        beginWorking(.wait)
        var failure: String?
        do {
            let bytes = try SecureRandom.bytes(count: 32)
            if bytes.count != 32 || Set(bytes).count <= 1 {
                failure = "entropy"
            }
        } catch {
            failure = error.localizedDescription
        }
        if failure == nil {
            let digest = SHA2.sha256(Data("abc".utf8)).hexString
            if digest != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" {
                failure = "SHA-256"
            }
        }
        if failure == nil {
            do {
                let key = Data(repeating: 0, count: 31) + Data([1])
                let publicKey = try Secp256k1.publicKey(fromPrivateKey: key)
                if !publicKey.hexString.hasPrefix("0279be667e") {
                    failure = "secp256k1"
                }
            } catch {
                failure = error.localizedDescription
            }
        }
        if failure == nil {
            do {
                let mnemonic = try BIP39Mnemonic(entropy: Data(repeating: 0, count: 16))
                if mnemonic.words.last != "about" {
                    failure = "BIP-39"
                }
            } catch {
                failure = error.localizedDescription
            }
        }
        endWorking()
        if let failure {
            failSelftest(failure)
        } else {
            advanceSelftest()
        }
    }

    private func runSelftestMicroSD() {
        beginWorking(.wait)
        do {
            let url = try SimulatorCardStandin.write(Data("Hello".utf8), named: "test-delme.txt", to: .microSD)
            let read = try String(contentsOf: url, encoding: .utf8)
            guard read == "Hello" else {
                endWorking()
                failSelftest("SD read mismatch")
                return
            }
            try FileManager.default.removeItem(at: url)
            endWorking()
            advanceSelftest()
        } catch {
            endWorking()
            failSelftest(error.localizedDescription)
        }
    }

    func evaluateCalculator() {
        let trimmed = calculatorExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        calculatorExpression = ""
        beginGPUBusyBar()
        Task { @MainActor in
            await Task.yield()
            self.finishCalculatorEvaluation(trimmed)
            self.endWorking()
        }
    }

    private func finishCalculatorEvaluation(_ trimmed: String) {
        let attemptsLeft = max(0, Self.maxPINAttempts - failedPINAttempts)
        var session = CalculatorSession(
            lines: calculatorLines,
            attemptsLeft: attemptsLeft,
            allowPINLogin: !isUnlocked && !isBricked && record != nil && attemptsLeft > 0,
            allowPrefixWords: !isUnlocked && record != nil
        )
        let pinOK: ((String) -> Bool)? = record.map { stored in
            { pin in SHA2.sha256(stored.pinSalt + Data(pin.utf8)) == stored.pinHash }
        }
        let result = session.submit(
            trimmed,
            pinOK: pinOK,
            prefixWords: { [pairingSecret] prefix in
                PinPrefixWords.words(pairingSecret: pairingSecret, pinPrefix: prefix)
            },
            randomBytes: { try SecureRandom.bytes(count: $0) }
        )
        calculatorLines = session.lines
        calculatorResult = calculatorLines.last ?? ""
        if session.attemptsLeft < attemptsLeft {
            failedPINAttempts = Self.maxPINAttempts - session.attemptsLeft
            persistPINAttempts()
        }
        if session.attemptsLeft == 0, !isUnlocked, record != nil {
            isBricked = true
            persistPINAttempts()
        }
        if case .login(let pin) = result {
            let parts = pin.split(separator: "-", maxSplits: 1)
            pinPrefix = parts.first.map(String.init) ?? ""
            pinInput = parts.count > 1 ? String(parts[1]) : ""
            attemptUnlock(pin: pin)
        }
    }

    private func resetCalculatorDisplay() {
        calculatorExpression = ""
        calculatorLines = CalculatorLogin.exampleLines
        calculatorResult = "0"
    }

    func handleScannedText(_ text: String) -> ScanHandlingResult {
        if screen == .wordEntry {
            return consumeWordEntryQR(text)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(whereSeparator: \.isNewline).map(String.init)
        if lines.count > 1, lines.allSatisfy({ $0.hasPrefix(BBQrHeader.prefix) }) {
            var last: ScanHandlingResult = .continueScanning("Keep scanning more...")
            for line in lines {
                last = handleBBQrPart(line)
                if case .complete = last { return last }
            }
            return last
        }
        if trimmed.hasPrefix(BBQrHeader.prefix) { return handleBBQrPart(trimmed) }
        resetBBQrScan()
        return processScannedText(trimmed)
    }

    private func consumeWordEntryQR(_ text: String) -> ScanHandlingResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(BBQrHeader.prefix) {
            if let header = try? BBQrHeader(trimmed), header.fileType == "P" || header.fileType == "T" {
                setWordEntryBottomLine(error: SeedCreation.expectedSecretsNotPSBT)
            } else {
                setWordEntryBottomLine(error: SeedCreation.unableToDecodeSecret)
            }
            return .complete
        }
        if let words = SeedCreation.wordsFromQRText(trimmed) {
            if words.count != wordEntryWords.count {
                setWordEntryBottomLine(error: SeedCreation.wrongSeedLength(expected: wordEntryWords.count, actual: words.count))
                return .complete
            }
            wordEntryWords = words
            wordEntryPrefix = ""
            if wordEntryHasChecksum {
                wordEntryLastWords = SeedCreation.importedChecksumWords(words)
            }
            setWordEntryBottomLine(error: nil)
            return .complete
        }
        let kind = ScanAnything.classifyText(trimmed)
        switch kind {
        case .xprv, .wif:
            setWordEntryBottomLine(error: SeedCreation.mustBeSeedWords(not: kind.rawValue))
        default:
            setWordEntryBottomLine(error: SeedCreation.unableToDecodeSecret)
        }
        return .complete
    }

    func handleBBQrPart(_ text: String) -> ScanHandlingResult {
        do {
            switch try bbqrCollector.add(text) {
            case .progress(let progress):
                applyBBQrScanProgress(progress)
                return .continueScanning(progress.statusMessage)
            case .complete(let payload):
                applyBBQrScanProgress(nil)
                if payload.encoding == .zlib {
                    beginWorking(.decompressing)
                    let result = consumeCompletedBBQr(payload)
                    if case .complete = result {
                        // Dismiss the scanner first; keep fullscreen 'Decompressing...'
                        // for a runloop turn so LCD and iPhone overlays can paint.
                        Task { @MainActor in self.endWorking() }
                        return .complete
                    }
                    endWorking()
                    return result
                }
                return consumeCompletedBBQr(payload)
            }
        } catch {
            bbqrCollector.reset()
            errorMessage = error.localizedDescription
            return .continueScanning("Invalid BBQr part; try again")
        }
    }

    private func applyBBQrScanProgress(_ progress: BBQrScanProgress?) {
        if let progress, !progress.skipsProgressUI {
            bbqrScanProgress = progress
        } else {
            bbqrScanProgress = nil
        }
    }

    private func consumeCompletedBBQr(_ payload: BBQrDecodedPayload) -> ScanHandlingResult {
        if scanExpectsText, payload.fileType != BBQrFileType.unicode.rawValue {
            return .continueScanning(ScanAnything.bbqrExpectedTextMessage(fileType: payload.fileType))
        }
        let utf8Body = String(decoding: payload.data, as: UTF8.self)
        let kind = ScanAnything.classifyBBQr(fileType: payload.fileType, utf8Body: utf8Body)
        if presentHobbledScanAnythingBlockIfNeeded(kind: kind) {
            return .complete
        }
        guard kind != nil else {
            return .continueScanning(ScanAnything.bbqrNotUsefulMessage(fileType: payload.fileType))
        }
        switch payload.fileType {
        case BBQrFileType.psbt.rawValue:
            loadPSBT(data: payload.data, source: "BBQr", inputMethod: "qr")
        case BBQrFileType.unicode.rawValue, BBQrFileType.json.rawValue:
            return processScannedText(utf8Body)
        case BBQrFileType.transaction.rawValue:
            presentVisualizedTransaction(payload.data)
        case BBQrFileType.keyTeleportReceive.rawValue,
             BBQrFileType.keyTeleportTransmit.rawValue,
             BBQrFileType.keyTeleportPSBT.rawValue:
            incomingKeyTeleport(fileType: payload.fileType, payload: payload.data)
        default:
            return .continueScanning(ScanAnything.bbqrNotUsefulMessage(fileType: payload.fileType))
        }
        return .complete
    }

    private func processScannedText(_ text: String) -> ScanHandlingResult {
        if pendingBagScan {
            return handleFactoryBagScan(text)
        }
        if nfcAwaitingQRStandIn {
            consumeNFCToolsText(text)
            return .complete
        }
        if teleportTextKind != .numericPassword, teleportTextKind != .paranoidPassword,
           tryHandleKeyTeleportText(text) { return .complete }
        if handleWhitelistScan(text) { return .complete }
        if pendingNoteQuickCreate {
            pendingNoteQuickCreate = false
            createNoteFromQR(text)
            return .complete
        }
        if importPurpose == .tapsigner, let payload = try? TapsignerBackup.payload(fromQR: text) {
            acceptTapsignerCiphertext(payload, origin: "QR")
            return .complete
        }
        if importPurpose == .xprv || story.onConfirm == .importXPRVSource {
            consumeImportedXPRVText(text)
            return .complete
        }
        if importPurpose == .multisig {
            importMultisigFromText(text)
            return .complete
        }
        if importPurpose == .multisigCreateXPUB {
            ingestCreateAirgappedJSON(text)
            return .complete
        }
        if screen == .passphrase, teleportTextKind == .numericPassword || teleportTextKind == .paranoidPassword {
            // Firmware teleport passwords: `scan_ok=False`.
            return .complete
        }
        if screen == .passphrase, !textEntryIsNickname, !textEntryIsNoteGroup, renamingVaultSeedID == nil,
           renamingMultisigIndex == nil {
            // Firmware passphrase / keyboard test / BKPW / Push Tx URL entry accepts a scanned value (`scan_ok=True`).
            let limit: Int
            if textEntryIsKeyboardTest || textEntryIsBKPWOverride || textEntryIsNotesImportPassword {
                limit = DeveloperDebug.keyboardTestMaxLength
            } else if textEntryIsPushtxURL {
                limit = 256
            } else if textEntryIsWIF {
                limit = 52
            } else {
                passphraseInput = BIP39Passphrase.sanitized(text)
                return .complete
            }
            passphraseInput = String(text.prefix(limit))
            return .complete
        }
        // Firmware `ux_q1.scan_anything`: hobbled whitelist before import.
        if presentHobbledScanAnythingBlockIfNeeded(kind: ScanAnything.classifyText(text)) {
            return .complete
        }
        if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
           object["coldcard_notes"] != nil {
            importNotes(data: Data(text.utf8))
            return .complete
        }
        if let data = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]), data.starts(with: PSBT.magic) {
            loadPSBT(data: data, source: "QR", inputMethod: "qr")
            return .complete
        }
        if (try? PSBT.decodeText(text)) != nil {
            loadPSBT(data: Data(text.utf8), source: "QR", inputMethod: "qr")
            return .complete
        }
        if let xprv = Self.firstExtendedPrivateKey(in: text) {
            importExtendedKey(xprv, temporary: pendingEphemeral || (hasSeed && currentMenu == .home))
            return .complete
        }
        if let mnemonic = try? BIP39Mnemonic.fromSeedQR(text) {
            if (screen == .wordEntry || screen == .importSeed), seedWordCount > 0, mnemonic.words.count != seedWordCount {
                errorMessage = "Must be seed of length \(seedWordCount), not \(mnemonic.words.count)"
                return .complete
            }
            importSeedText = mnemonic.phrase
            if pendingEphemeral {
                pendingMnemonic = mnemonic
                ephemeralOrigin = "From QR"
                do { try applyEphemeralSeed() } catch { present(error) }
            } else if !hasSeed {
                pendingMnemonic = mnemonic
                if hasPIN {
                    do { try commitSeedOntoExistingPIN() } catch { present(error) }
                } else {
                    navigate(to: .importSeed)
                }
            } else {
                showStory(title: "SeedQR detected", body: FirmwareCopy.needClearSeed)
            }
            return .complete
        }
        if handleWIFScannedText(text) { return .complete }
        if ScanAnything.classifyText(text) == .vmsg {
            verifySigFile(text: text, filename: "qr", digestCheck: true)
            return .complete
        }
        if isUnlocked, BitcoinMessageSigner.isQRSignMessagePayload(text) {
            messageSignDoneMode = .exportPrompt
            messageSourceFilename = "msg_sign.txt"
            if let request = BitcoinMessageSigner.parseSignRequest(text) {
                applySignRequest(request)
            } else {
                showStory(title: "", body: "Problem: MSG required\n\nMessage to be signed must be a single line of ASCII text.")
            }
            return .complete
        }
        presentSimpleTextQR(text)
        return .complete
    }

    /// Firmware `ux_q1.scan_anything` when `pa.hobbled_mode` and `what` is not whitelisted.
    /// NFC Tools Sign PSBT (`nfcAwaitingQRStandIn`) is a different scanner and is not gated here.
    @discardableResult
    private func presentHobbledScanAnythingBlockIfNeeded(kind: ScanAnythingKind?) -> Bool {
        guard hobbledMode.isHobbled, !nfcAwaitingQRStandIn, !pendingNoteQuickCreate, let kind else { return false }
        let relatedKeys = preferences.sssp?.relatedKeys ?? false
        guard !ScanAnything.allowsHobbled(kind, relatedKeys: relatedKeys) else { return false }
        showStory(title: FirmwareCopy.spendingPolicyQRBlockedTitle,
                  body: FirmwareCopy.spendingPolicyQRBlocked)
        return true
    }

    /// Firmware `ux_q1.ux_visualize_txn`.
    func presentVisualizedTransaction(_ data: Data) {
        Task {
            await runVisualizingProgress()
            endWorking()
            if let transaction = try? BitcoinTransaction(data: data) {
                showStory(
                    title: VisualizeTransactionUX.title,
                    body: VisualizeTransactionUX.body(
                        inputs: transaction.inputs.count,
                        outputs: transaction.outputs.count,
                        txid: transaction.txid
                    )
                )
            } else {
                showStory(title: VisualizeTransactionUX.title, body: VisualizeTransactionUX.deserializeFailed)
            }
        }
    }

    /// Firmware `ux_visualize_textqr`. (0) starts `qr_sign_msg` when length ≤ 240.
    func presentSimpleTextQR(_ text: String) {
        messageText = text
        let vis = FirmwareCopy.simpleTextQR(text)
        let canSign = vis.canSign && isUnlocked
        showStory(title: vis.title, body: vis.body, onConfirm: canSign ? .simpleTextQR : nil)
    }

    /// Firmware `qr_sign_msg` → `ux_sign_msg(..., approved_cb=qr_msg_sign_done)`.
    func startQRSignMsg() {
        messageSignDoneMode = .qrDone
        messageAllowTabNewline = true
        messageMaxLength = BitcoinMessageSigner.maximumLength
        messagePathLocked = false
        messageSourceFilename = "msg_sign.txt"
        signedMessage = nil
        wifSignPrivateKey = nil
        back()
        openMenu(.messageAddressFormat)
    }

    func applySignRequest(_ request: BitcoinMessageSigner.SignRequest) {
        if wifSignPrivateKey != nil {
            applyWIFMessage(request.message)
            return
        }
        do {
            _ = try BitcoinMessageSigner.validate(request.message, allowTabAndNewline: request.allowTabAndNewline,
                                                 maxLength: BitcoinMessageSigner.maximumLength)
        } catch {
            showStory(title: "", body: "Problem: \(error.localizedDescription)\n\nMessage to be signed must be a single line of ASCII text.")
            return
        }
        messageMaxLength = BitcoinMessageSigner.maximumLength
        messageAllowTabNewline = request.allowTabAndNewline
        messageText = request.message
        messageAddressType = request.addressType
        messagePathLocked = true
        if request.subpath.isEmpty {
            messageAccount = 0
            messageChange = false
            messageIndex = 0
            messagePath = defaultMessagePath()
        } else {
            messagePath = request.subpath
        }
        signedMessage = nil
        signMessage()
    }

    func showSeedQR() {
        guard let mnemonic = activeMnemonic ?? pendingMnemonic else { return }
        qrPresentation = QRPresentation(title: SeedCreation.seedQRCaption, payload: mnemonic.seedQR, sensitive: true)
    }

    /// Firmware `show_words` (1)/QR: 4-letter truncated words, not compact SeedQR (`seed.py`).
    func showRecordWordsQR() {
        guard let mnemonic = pendingMnemonic ?? activeMnemonic else { return }
        let payload = mnemonic.words.map { String($0.prefix(4)) }.joined(separator: " ")
        qrPresentation = QRPresentation(title: "Seed words — secret", payload: payload, sensitive: true)
    }

    func showStory(title: String, body: String, onConfirm: StoryConfirmAction? = nil, confirmCode: String? = nil,
                   hintQR: Bool = false, hintNFC: Bool = false) {
        story = StoryPresentation(title: title, body: body, confirmCode: confirmCode, onConfirm: onConfirm,
                                  hintQR: hintQR, hintNFC: hintNFC)
        navigate(to: .story)
    }

    func confirmStory() {
        if story.onConfirm == .xorSplitParts || story.onConfirm == .xorRestoreMore
            || story.onConfirm == .exportNotesFile || story.onConfirm == .importNotesSource {
            return
        }
        let action = story.onConfirm
        story.onConfirm = nil
        switch action {
        case .enableSecureNotes:
            preferences.secnapEnabled = true
            persistPreferencesQuietly()
            back()
            openMenu(.notes)
        case .confirmPassphrase:
            confirmPassphrase(save: false)
        case .savePassphrase:
            confirmPassphrase(save: true)
        case .destroySeed:
            destroySeed()
        case .wipeSimulator:
            wipeSimulator()
        case .continuePINWarning:
            showStory(title: "WARNING", body: FirmwareCopy.proveRead,
                      onConfirm: .continuePINPrefix, confirmCode: "6")
        case .continueAddressExplorer:
            back()
            openMenu(.addressExplorer)
        case .hideAddressExplorerIntro:
            preferences.skipAddressExplorerIntro = true
            persistPreferencesQuietly()
            back()
            openMenu(.addressExplorer)
        case .continueRiskyPIN:
            back()
            attemptUnlock(pin: pinPrefix + "-" + pinInput)
        case .retryPINConfirm:
            pinSetupPhase = .confirmPrefix
            pinPrefix = ""; pinInput = ""
            back()
            screen = .pinSetup
        case .continueCustomPath:
            back()
            loadCustomPathAddresses(type: addressType)
        case .continueDice:
            back()
            if diceMixesWithTRNG {
                beginDiceMixCollect()
            } else {
                navigate(to: .diceRoll)
            }
        case .deleteNote:
            pendingNoteDelete = true
            if let id = selectedNoteID { deleteSecureNote(id: id) }
        case .verifySiblingHashes:
            importPurpose = .siblingHashes
            showFileImporter = true
        case .reuseBackupPassword:
            if let stored = storedBackupPassword {
                backupPassword = stored
                backupPasswordWords = stored.split(whereSeparator: \.isWhitespace).map(String.init)
                backupConfirmPassword = stored
            }
            back()
            finishBackupPasswordExport()
        case .cacheBackupPassword:
            pendingCacheBackupPassword = true
            back()
            finishBackupPasswordExport()
        case .skipBackupCache:
            pendingCacheBackupPassword = false
            back()
            finishBackupPasswordExport()
        case .backupFirstCopyWritten:
            clearPendingBackupExport()
            back()
        case .backupMoreCopies:
            exportAnotherBackupCopy()
        case .notesCustomPassword:
            back()
            beginBackupPasswordEntry()
        case .enableSighashWarn:
            preferences.sighashWarnOnly = true
            persistPreferencesQuietly()
            back()
        case .enableDeletePSBTs:
            preferences.deletePSBTs = true
            persistPreferencesQuietly()
            back()
        case .enableKeyboardEMU:
            preferences.keyboardEmuEnabled = true
            persistPreferencesQuietly()
            back()
        case .enableSeedVault:
            preferences.seedVaultEnabled = true
            persistPreferencesQuietly()
            back()
        case .enableAEStartIndex:
            preferences.aeStartIndexEnabled = true
            persistPreferencesQuietly()
            back()
        case .enableB85Unlimited:
            preferences.b85Unlimited = true
            persistPreferencesQuietly()
            back()
        case .clearOVCache:
            back()
            statusMessage = "Cleared."
        case .clearAddressCache:
            addressPreviews = [:]
            derivedAddresses = []
            back()
            statusMessage = "Cleared."
        case .approveMessageSign:
            back()
            if wifSignPrivateKey != nil { performWIFMessageSignature() }
            else { performMessageSignature() }
        case .signedMessageExport:
            story.onConfirm = .signedMessageExport
        case .continueExport:
            back()
            continueNamedExport(account: 0)
        case .exportPickAccount:
            back()
            accountPromptPurpose = pendingKeyExpression ? .walletExport : .walletExport
            accountPromptValue = "0"
            navigate(to: .accountNumber)
        case .descriptorIntExt:
            descriptorCombined = true
            back()
            exportAddressTypes = AddressType.singlesigExportOrder
            openMenu(.exportAddressType)
        case .openKeyExpressionMenu:
            back()
            openMenu(.exportKeyExpression)
        case .messageChange:
            messageChange = false
            promptMessageIndex()
        case .signedMessageQR:
            presentSignedMessageSignatureQR()
            story.onConfirm = .signedMessageQR
        case .continuePassphrase:
            back()
            beginPassphraseEntry()
        case .continueViewSeedWords:
            if wipeIfDeltaMode() { return }
            pendingMnemonic = nil
            back()
            if !activePassphrase.isEmpty, let key = rootKey, let xprv = try? key.serializePrivate() {
                let shown = SeedCreation.viewSeedWords(passphraseActive: true, xprv: xprv, words: [])
                showStory(title: shown.title, body: shown.body)
                return
            }
            navigate(to: .seedWords)
        case .continueExportSeedQR:
            if wipeIfDeltaMode() { return }
            back()
            showSeedQR()
        case .applyMainnet:
            settingsNetwork = .mainnet
            saveSettings()
            back()
        case .applyTestnet:
            settingsNetwork = .testnet
            saveSettings()
            back()
        case .applyRegtest:
            settingsNetwork = .regtest
            saveSettings()
            back()
        case .restoreMasterPreserve:
            saveCurrentEphemeralToVault()
            performRestoreMaster()
        case .xorSplitParts:
            return
        case .xorSplitRNG:
            performXORSplit(useRNG: false)
        case .xorRestoreWordCount:
            xorDesiredWordCount = 24
            continueXORRestoreAfterWordCount()
        case .xorRestoreInclude:
            continueXORRestoreAfterInclude(includeCurrent: false)
        case .xorRestoreVault:
            continueXORRestoreAfterVault(addVault: false)
        case .xorRestoreMore:
            return
        case .xorShowParts:
            beginXORSplitQuiz()
        case .xorStopForgetSplit:
            leaveXORFlowToMenu()
        case .xorAbortRestore:
            leaveXORFlowToMenu()
        case .bip85Reveal:
            story.onConfirm = .bip85Reveal
        case .bip85Intro:
            continueBIP85AfterIntro()
        case .confirmBIP85TmpSeed:
            back()
            openMenu(.deriveSeeds)
        case .openTemporarySeed:
            back()
            openMenu(.temporarySeed)
        case .exportCleartext:
            back()
            if pendingNotesFileExport {
                writeNotesJSONAndSignature()
            } else {
                writeCleartextBackup()
            }
        case .addToSeedVault:
            saveCurrentEphemeralToVault()
            back()
        case .skipVaultSave:
            continueAfterVaultOffer(saved: false)
        case .continueAfterVaultSave:
            continueAfterVaultOffer(saved: true)
        case .deleteVaultSeedConfirm:
            if let id = pendingVaultDeleteID {
                deleteVaultSeed(id, keepSettings: false)
            }
        case .uxAborted:
            abortWithFirmwarePause()
        case .continueMash:
            back()
            beginMashCollect()
        case .continueCoin:
            back()
            beginCoinCollect()
        case .continueDiceRolling:
            back()
        case .skipQuiz:
            back()
            skipSeedQuiz()
        case .throwAwayWords:
            abortPendingSeedFlow()
        case .abortDice:
            if diceForPaperWallet {
                returnToPaperWalletsMenu(selecting: 2)
            } else {
                abortPendingSeedFlow()
            }
        case .entropyBiasRetry:
            returnToEntropyMethodMenu()
        case .beginChangePINOld:
            pinSetupCollectingOld = true
            pinSetupIsChange = true
            pinSetupPhase = .prefix
            pinPrefix = ""
            pinInput = ""
            screen = .pinSetup
        case .enableCalculatorLogin:
            preferences.calculatorLogin = true
            persistPreferencesQuietly()
            back()
        case .confirmPasswordChange:
            back()
            persistSecureNote()
        case .notesCustomPWD:
            beginWordEntry(purpose: .notesImportPassword, wordCount: 12)
        case .beginNickname:
            back()
            textEntryIsNickname = true
            passphraseInput = nickname
            navigate(to: .passphrase)
        case .confirmNoteEdits:
            back()
            persistSecureNote()
        case .exportNotesSignature:
            back()
            if let data = pendingNotesSignature {
                let name = pendingNotesFilename.replacingOccurrences(of: ".json", with: ".sig")
                prepareExport(data: data, filename: name, type: .plainText)
            }
            pendingNotesSignature = nil
            pendingNotesJSON = nil
        case .batchSignConfirm:
            back()
            if let item = pendingBatchItem {
                pendingBatchItem = nil
                loadPSBT(data: item.data, source: item.name, fromBatch: true, url: item.url)
            }
        case .batchSignAfterExport:
            continueBatchAfterSignedExport()
        case .batchSignImport:
            break
        case .destroySeedAgain:
            // Firmware clear_seed second confirmation (`AGAIN...`, confirm_key='4').
            showStory(title: SeedDanger.destroyAgainTitle, body: SeedDanger.destroyAgainBody,
                      onConfirm: .destroySeed, confirmCode: SeedDanger.destroyAgainConfirmKey)
        case .nukeDeviceBrick:
            // Firmware nuke_device second confirmation (confirm key 1).
            showStory(title: "", body: FirmwareCopy.nukeDeviceBrick,
                      onConfirm: .wipeSimulator, confirmCode: "1")
        case .confirmRestoreBackup:
            back()
            commitPendingRestore()
        case .confirmDeleteSavedPassphrase:
            back()
            performDeleteSavedPassphrase()
        case .restoreMasterConfirm:
            performRestoreMaster()
        case .showXPUBQR:
            // Firmware loops the story after showing the QR (actions.py export_xpub).
            story.onConfirm = .showXPUBQR
            presentXPUBQR()
        case .acceptTerms:
            UserDefaults.standard.set(true, forKey: Self.termsAcceptedDefaultsKey)
            showBagNumberStory(onConfirm: .continueAfterBag)
        case .continueAfterBag:
            history.removeAll()
            menuStack.removeAll()
            currentMenu = rootMenu
            screen = .menu
            selectedMenuIndex = 0
        case .continuePINPrefix:
            pinSetupPhase = .prefix
            pinPrefix = ""
            pinInput = ""
            screen = .pinSetup
        case .continueToggleChooser:
            back()
            if let menu = pendingToggleMenu {
                pendingToggleMenu = nil
                openMenu(menu)
            }
        case .pickScramble:
            back()
            openMenu(.scrambleKeys)
        case .pickKillKey:
            back()
            openMenu(.killKey)
        case .abortWordEntry:
            wordEntryWords = Array(repeating: "", count: wordEntryWords.count)
            wordEntryPrefix = ""
            wordEntryLastWords = []
            wordEntryHint = ""
            abortPendingSeedFlow()
        case .lockDownSeed:
            lockDownTemporarySeed()
        case .pasteNFCSeed:
            back()
            nfcStandInKind = .ephemeralSeed
            textEntryIsNFCSeed = true
            passphraseInput = ""
            navigate(to: .passphrase)
        case .nfcToolsStandIn:
            back()
            textEntryIsNFCTools = true
            passphraseInput = ""
            navigate(to: .passphrase)
        case .nfcShowAddress, .nfcVerifiedAddress:
            back()
        case .enrollImportedMultisig:
            if pendingNFCMultisig != nil {
                commitNFCImportedMultisig()
            } else {
                _ = confirmMultisigStory(.enrollImportedMultisig)
            }
        case .openDeveloperMenu:
            back()
            openMenu(.iAmDeveloper)
        case .openSerialREPL:
            back()
            navigate(to: .serialREPL)
        case .reflashGPU:
            performReflashGPU()
        case .bkpwOverride:
            showBKPWOverrideStory()
        case .bkpwDelete:
            deleteStoredBackupPassword()
        case .bkpwShow:
            if let password = storedBackupPassword {
                showStory(title: DeveloperDebug.bkpwShowTitle, body: password, onConfirm: .bkpwOverride)
            } else {
                showBKPWOverrideStory()
            }
        case .warmResetAfterCrash:
            warmReset()
        case .formatRamDisk:
            performFormatVolume(.virtDisk)
        case .formatSDCard:
            performFormatVolume(.microSD)
        case .listedFileDetail:
            story.onConfirm = .listedFileDetail
        case .listedFileRestoreDetail:
            if history.last == .story { _ = history.popLast() }
            presentListedFileDetail()
        case .enrollMicroSD2FA:
            back()
            enrollMicroSD2FACard()
        case .removeMicroSD2FA:
            back()
            removePendingMicroSD2FACard()
        case .cloneStartWriteKey:
            writeCloneStartFile()
        case .cloneIngestPickFile:
            continueCloneIngest()
        case .cloneWriteConfirmTmp:
            writeCloneBackup()
        case .cloneWritePickStart:
            pickCloneStartFile()
        case .tapsignerImportSource:
            pickTapsignerBackupFile()
        case .tapsignerHaveCard:
            beginTapsignerKeyEntry()
        case .tapsignerRetryKey:
            hexEntryText = ""
            back()
        case .continueSelftest:
            if selftestAwaitingNFCShare { return }
            advanceSelftest()
        case .continuePushtxSetup:
            continuePushtxSetupAfterIntro()
        case .enableNFCForFeature:
            enableNFCForPushTxFeature()
        case .retryPushtxURLEdit:
            retryPushtxURLEdit()
        case .continuePushTxnPicker:
            continuePushTxnPicker()
        case .pickPushTxnFromFiles:
            back()
            importPurpose = .pushTransaction
            showFileImporter = true
        case .keyTeleportReusePubkey, .keyTeleportSendWarning, .keyTeleportShareMaster,
             .keyTeleportShareBackup, .keyTeleportShowPayload, .keyTeleportRetryPassword,
             .keyTeleportPickPSBTFile:
            if let action { _ = confirmKeyTeleportStory(action) }
        case .some(.none), nil:
            back()
            openVelocityAfterStoryIfNeeded()
        default:
            if let action, confirmFactoryStory(action) { break }
            if let action, confirmPaperWalletStory(action) { break }
            if let action, confirmSpendingStory(action) {
                openVelocityAfterStoryIfNeeded()
                break
            }
            if let action, confirmXPRVStory(action) { break }
            if let action, confirmWIFStory(action) { break }
            if let action, confirmTrickStory(action) { break }
            if let action, confirmMultisigStory(action) { break }
            back()
        }
    }

    func showIdentityQR() {
        guard let root = rootKey, let xpub = try? root.neutered().serializePublic() else { return }
        qrPresentation = QRPresentation(title: "Master XPUB", payload: xpub, sensitive: false)
    }

    func resetPSBTFlow() {
        currentPSBT = nil
        psbtReview = nil
        signedPSBTData = nil
        signedPSBT = nil
        finalizedTransaction = nil
        signingResults = []
        loadedPSBTSHA = nil
        loadedPSBTURL = nil
        psbtSignedPriorMessage = nil
        abandonBatchSignForSingleFile()
        navigate(to: .psbt)
    }

    func refusePSBT() {
        currentPSBT = nil
        psbtReview = nil
        signedPSBTData = nil
        signedPSBT = nil
        finalizedTransaction = nil
        loadedPSBTSHA = nil
        loadedPSBTURL = nil
        // Firmware `ux_dramatic_pause("Refused.")` then pops; remaining batch files continue.
        // Last file: `_batch_sign` loop ends — same as last skip (`quitBatchSign`).
        Task {
            await dramaticPause("Refused.", seconds: 2)
            if !batchQueue.isEmpty {
                startNextBatchPSBT()
                return
            }
            if batchSignCallerDepth != nil {
                quitBatchSign()
                return
            }
            back()
        }
    }

    func pageAddresses(by delta: Int) {
        if customSingleAddress { return }
        let next = AddressExplorer.move(start: addressPageStart, deltaPages: delta < 0 ? -1 : 1)
        if next == addressPageStart { return }
        addressPageStart = next
        storyTop = 0
        loadAddresses()
    }

    /// Firmware `KEY_HOME` on the address story — index 0 (`address_explorer.py:430`).
    func resetAddressExplorerHome() {
        if customSingleAddress { return }
        addressPageStart = AddressExplorer.homeStart(from: addressPageStart)
        storyTop = 0
        loadAddresses()
    }

    func toggleChangeAddresses() {
        guard addressAllowChange, !addressChange else { return }
        addressChange = true
        loadAddresses()
    }

    func startMessageSigningFromAddress() {
        let address: DerivedAddress?
        if let selectedAddress {
            address = selectedAddress
        } else if derivedAddresses.indices.contains(selectedMenuIndex) {
            address = derivedAddresses[selectedMenuIndex]
        } else {
            address = nil
        }
        guard let address else { return }
        messageText = ""
        messagePath = address.path
        if let parsed = try? DerivationPath(address.path), parsed.components.count >= 5 {
            messageAccount = parsed.components[2] & ~DerivationPath.hardened
            messageChange = (parsed.components[3] & ~DerivationPath.hardened) == 1
            messageIndex = parsed.components[4] & ~DerivationPath.hardened
        }
        messageAddressType = addressType
        messagePathLocked = true
        messageMaxLength = BitcoinMessageSigner.uxInputMaximumLength
        messageSignDoneMode = .exportPrompt
        messageAllowTabNewline = false
        messageSourceFilename = "msg_sign.txt"
        signedMessage = nil
        navigate(to: .messageSigning)
    }

    func beginDestroySeed() {
        if SeedDanger.shouldBlockDestroyForDuress(
            hobbled: hobbledMode.isHobbled,
            hasActiveDuress: trickTable.hasDuressWallet
        ) {
            showStory(title: "", body: SeedDanger.duressBlockBody, onConfirm: .uxAborted)
            return
        }
        showStory(
            title: SeedDanger.destroyFirstTitle,
            body: SeedDanger.destroyFirstBody,
            onConfirm: .destroySeedAgain
        )
    }

    func destroySeed() {
        guard var record else { return }
        var tricks = TrickPinTable(slots: record.trickPins)
        tricks.clearAll()
        record.trickPins = tricks.slots
        record.mnemonic = ""
        record.extendedPrivateKey = nil
        record.notes = []
        record.settingsXFP = nil
        record.wifKeys = []
        preferences = SimulatorPreferences()
        record.preferences = preferences
        self.record = record
        activeMnemonic = nil
        ephemeralPhrase = nil
        ephemeralXPRV = nil
        pendingEphemeral = false
        pendingMnemonic = nil
        pendingExtendedKey = nil
        activePassphrase = ""
        passphraseInput = ""
        persistPreferencesQuietly()
        clearSpendingPolicyOnDestroySeed()
        Task { @MainActor in
            await dramaticPause(SeedDanger.clearingTitle, seconds: 1)
            lock()
        }
    }

    func loadIdentity() {
        var msg = ""
        if !activePassphrase.isEmpty {
            msg += "\(FirmwareCopy.identityPassphrase)\n\n"
        } else if ephemeralPhrase != nil || ephemeralXPRV != nil {
            msg += "\(FirmwareCopy.identityTemporarySeed)\n\n"
        }
        let xfp = rootKey?.fingerprintHex ?? "00000000"
        let xpub: String
        if let root = rootKey, let serialized = try? root.neutered().serializePublic() {
            xpub = serialized
        } else {
            xpub = "(none yet)"
        }
        msg += """
        Master Key Fingerprint:

          \(xfp)

        USB Serial Number:

          Q-SIMULATOR

        Extended Master Key:

        \(xpub)
        """
        if let bag = displayedBagNumber {
            msg += "\n\nShipping Bag:\n  \(bag)\n"
        }
        if xpub != "(none yet)" {
            msg += "\n\n\(FirmwareCopy.identityQRHint)"
        }
        identityText = msg
        navigate(to: .viewIdentity)
    }

    private func restoreAddressExplorerSelection() {
        if let label = lastAddressExplorerLabel,
           let index = menuItems.firstIndex(where: { $0.title == label }) {
            jumpMenu(to: index)
            return
        }
        guard let last = preferences.lastAddressType,
              let typeIndex = AddressType.explorerCases.firstIndex(of: last) else { return }
        selectedMenuIndex = min(typeIndex * 2, max(0, menuItems.count - 1))
    }

    func exportAddressCSV(destination: AddressExportDestination = .sdCard) {
        guard let root = rootKey else { return }
        beginWorking(.saving)
        let type = addressType
        let account = addressOverrideAccount ?? addressAccount
        let change = addressAllowChange && addressChange
        let start = addressStartIndex
        let template = addressPathTemplate
        let isSingle = customSingleAddress
        let singlePath = customPathText
        let msIndex = exploringMultisigIndex
        let wallets = preferences.importedMultisigWallets
        let showFull = preferences.fullMultisigAddressView
        let changeIdx: UInt32 = change ? 1 : 0
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String?) in
                do {
                    if let msIndex, wallets.indices.contains(msIndex) {
                        let wallet = wallets[msIndex]
                        let count = Int(AddressExplorer.csvCount(isSingle: false, start: start) ?? 0)
                        var rows: [(index: UInt32, address: String, scriptHex: String, derivations: [String])] = []
                        rows.reserveCapacity(count)
                        for offset in 0..<count {
                            let idx = start + UInt32(offset)
                            let derived = try wallet.derivedAddress(change: changeIdx, index: idx, network: root.network)
                            let shown = MultisigWalletConfig.censorAddress(derived.address, showFull: showFull)
                            rows.append((idx, shown, derived.script.hexString, derived.paths))
                        }
                        return (Data(AddressExplorer.multisigCSV(rows: rows, signerCount: wallet.totalSigners).utf8), nil)
                    }
                    if isSingle {
                        let base = try DerivationPath(singlePath)
                        let child = try root.derived(path: base)
                        let address = try BitcoinAddress.address(publicKey: child.publicKey, type: type, network: root.network)
                        let script = try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: type)
                        let derived = DerivedAddress(index: 0, change: false, path: base.description, address: address,
                                                     publicKeyHex: child.publicKey.hexString, scriptPubKeyHex: script.hexString)
                        return (Data(WalletExporter.addressSummaryCSV(addresses: [derived]).utf8), nil)
                    }
                    let count = Int(AddressExplorer.csvCount(isSingle: false, start: start) ?? 0)
                    var addresses: [DerivedAddress] = []
                    addresses.reserveCapacity(count)
                    for offset in 0..<count {
                        let index = start + UInt32(offset)
                        if let template, template.contains("{idx}") {
                            let expanded = Self.expandPathTemplate(template, idx: index, change: changeIdx, account: account)
                            let base = try DerivationPath(expanded)
                            let child = try root.derived(path: base)
                            let address = try BitcoinAddress.address(publicKey: child.publicKey, type: type, network: root.network)
                            let script = try BitcoinAddress.scriptPubKey(publicKey: child.publicKey, type: type)
                            addresses.append(DerivedAddress(index: index, change: change, path: base.description, address: address,
                                                            publicKeyHex: child.publicKey.hexString, scriptPubKeyHex: script.hexString))
                        } else {
                            addresses.append(try BitcoinAddress.derive(root: root, type: type, account: account,
                                                                       change: change, index: index))
                        }
                    }
                    return (Data(WalletExporter.addressSummaryCSV(addresses: addresses).utf8), nil)
                } catch { return (nil, error.localizedDescription) }
            }.value
            endWorking()
            if let data = result.0 {
                switch destination {
                case .sdCard:
                    prepareExport(data: data, filename: "addresses.csv", type: .commaSeparatedText)
                    queueDetachedSignature(for: data, filename: "addresses.csv")
                case .lowerSlot:
                    writeAddressSummary(data, to: .microSD)
                case .virtDisk:
                    writeAddressSummary(data, to: .virtDisk)
                }
            } else { errorMessage = result.1 }
        }
    }

    /// Firmware `make_address_summary_file` onto CardSlot (Documents stand-in).
    private func writeAddressSummary(_ data: Data, to volume: SimulatorCardStandin.Volume) {
        do {
            let csv = try SimulatorCardStandin.write(data, named: "addresses.csv", to: volume)
            var body = "Address summary file written:\n\n\(csv.lastPathComponent)"
            if let root = rootKey {
                let message = BitcoinMessageSigner.fileHashMessage(hashesAndNames: [(SHA2.sha256(data), "addresses.csv")])
                let coin = root.network.coinType
                if let path = try? DerivationPath("m/44h/\(coin)h/0h/0/0"),
                   let signed = try? BitcoinMessageSigner.sign(message, root: root, path: path, type: .legacy) {
                    let sigName = BitcoinMessageSigner.signatureFilename(forInputFilename: "addresses.csv")
                    let sig = try SimulatorCardStandin.write(Data(signed.armored.utf8), named: sigName, to: volume)
                    body += "\n\nAddress signature file written:\n\n\(sig.lastPathComponent)"
                }
            }
            showStory(title: "", body: body)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var psbtExplorerPageSize: Int { psbtExploreKind == .inputs ? 1 : 10 }

    var psbtExplorerMax: Int {
        switch psbtExploreKind {
        case .inputs: psbtReview?.inputs.count ?? 0
        case .outputs: psbtReview?.outputs.count ?? 0
        }
    }

    var psbtExplorerBody: String {
        guard let review = psbtReview else { return "No PSBT loaded." }
        let end = min(psbtExploreOffset + psbtExplorerPageSize, psbtExplorerMax)
        var lines: [String] = []
        switch psbtExploreKind {
        case .inputs:
            guard review.inputs.indices.contains(psbtExploreOffset) else { return "No inputs." }
            let input = review.inputs[psbtExploreOffset]
            lines.append("\(input.previousOutpoint)\n\n")
            if input.hasUTXO {
                lines.append("=== UTXO ===\n\n")
                lines.append("\(formatAmount(input.value))\n\n")
                if let spk = input.scriptPubKeyHex { lines.append("\(spk)\n\n") }
                if let address = input.address { lines.append("\(LCDDisplay.showSingleAddress(address))\n\n") }
                if let addressFormat = input.addressFormat {
                    lines.append("Address Format: \(addressFormat)\n\n")
                }
            }
            if let rtl = input.relativeTimelockNote { lines.append("\(rtl)\n\n") }
            var psbtItem = ""
            if !input.ourKeys.isEmpty {
                let wif = Set(wifKeys.map { $0.publicKeyHex.lowercased() })
                psbtItem += "Our key\(input.ourKeys.count == 1 ? "" : "s"):\n\n"
                for key in input.ourKeys {
                    let note = wif.contains(key.publicKeyHex.lowercased()) ? "\n\(DoneSigning.wifStoreNote)" : ""
                    psbtItem += "\(key.xfpPath):\n\(key.publicKeyHex)\(note)\n\n"
                }
            } else {
                let unmatched = wifKeys.filter { item in
                    input.ourPublicKeyHex?.lowercased() == item.publicKeyHex.lowercased()
                }
                if !unmatched.isEmpty {
                    psbtItem += "Our key\(unmatched.count == 1 ? "" : "s"):\n\n"
                    for item in unmatched {
                        psbtItem += "\(item.publicKeyHex)\n\(DoneSigning.wifStoreNote)\n\n"
                    }
                }
            }
            if let mn = input.multisigMN { psbtItem += "Multisig: \(mn)\n\n" }
            if !input.signedCosignerXFPs.isEmpty || input.fullySigned {
                if input.fullySigned {
                    psbtItem += "Input fully signed.\n\n"
                } else {
                    psbtItem += "Already signed:\n"
                    for xfp in input.signedCosignerXFPs { psbtItem += "  \(xfp)\n" }
                    psbtItem += "\n"
                }
            }
            if let sighash = input.sighashNote { psbtItem += "\(sighash)\n\n" }
            if let warning = input.warning { psbtItem += "\(warning)\n\n" }
            if !psbtItem.isEmpty { lines.append("=== PSBT ===\n\n" + psbtItem) }
        case .outputs:
            for index in psbtExploreOffset..<end where review.outputs.indices.contains(index) {
                let output = review.outputs[index]
                lines.append("Output \(output.index)\(output.isChange ? " (change)" : ""):\n\n")
                lines.append(renderPSBTOutput(output) + "\n")
            }
        }
        lines.append(DoneSigning.qExplorerHints(
            hasNext: end < psbtExplorerMax,
            hasPrev: psbtExploreOffset > 0,
            canGoto: psbtExplorerMax > 1
        ))
        return lines.joined(separator: "\n")
    }

    var psbtExplorerQRPayloads: [String] {
        guard let review = psbtReview else { return [] }
        let end = min(psbtExploreOffset + psbtExplorerPageSize, psbtExplorerMax)
        switch psbtExploreKind {
        case .inputs:
            guard review.inputs.indices.contains(psbtExploreOffset) else { return [] }
            let input = review.inputs[psbtExploreOffset]
            return [input.previousOutpoint.split(separator: ":").first.map(String.init) ?? input.previousOutpoint,
                    input.address].compactMap { $0 }
        case .outputs:
            return (psbtExploreOffset..<end).compactMap { index in
                review.outputs.indices.contains(index) ? review.outputs[index].address : nil
            }
        }
    }

    func startPSBTExplorer(_ kind: PSBTExploreKind) {
        guard psbtReview != nil else { return }
        psbtExploreKind = kind
        psbtExploreOffset = 0
        navigate(to: .psbtExplorer)
    }

    func pagePSBTExplorer(by pages: Int) {
        let step = psbtExplorerPageSize * pages
        let next = psbtExploreOffset + step
        guard next >= 0, next < psbtExplorerMax else { return }
        psbtExploreOffset = next
    }

    func pagePSBTExplorer(to index: Int) {
        let clamped = min(max(0, index), max(0, psbtExplorerMax - 1))
        psbtExploreOffset = clamped
    }

    func promptPSBTExploreIndex() {
        guard psbtExplorerMax > 1 else { return }
        accountPromptPurpose = .psbtExploreIndex
        accountPromptValue = String(psbtExploreOffset)
        navigate(to: .accountNumber)
    }

    func offerAddCurrentToVault(fromMenu: Bool) {
        guard ephemeralPhrase != nil || ephemeralXPRV != nil else { return }
        showStory(title: "[\(fingerprint)]", body: FirmwareCopy.addToSeedVault, onConfirm: .addToSeedVault)
    }

    func saveCurrentEphemeralToVault() {
        if let xprv = ephemeralXPRV {
            if preferences.vaultedSeeds.contains(where: { $0.extendedPrivateKey == xprv }) {
                statusMessage = "Already in Seed Vault."
                return
            }
            let entry = VaultedSeed(fingerprint: fingerprint, mnemonic: "", label: "[\(fingerprint)]",
                                    origin: ephemeralOrigin, extendedPrivateKey: xprv)
            preferences.vaultedSeeds.append(entry)
            persistPreferencesQuietly()
            statusMessage = "[\(fingerprint)]\nSaved to Seed Vault"
            return
        }
        guard let phrase = ephemeralPhrase else { return }
        if preferences.vaultedSeeds.contains(where: { $0.mnemonic == phrase }) {
            statusMessage = "Already in Seed Vault."
            return
        }
        let entry = VaultedSeed(fingerprint: fingerprint, mnemonic: phrase, label: "[\(fingerprint)]",
                                origin: ephemeralOrigin)
        preferences.vaultedSeeds.append(entry)
        persistPreferencesQuietly()
        statusMessage = "[\(fingerprint)]\nSaved to Seed Vault"
    }

    /// Firmware `SeedVaultMenu._detail`.
    func showVaultSeedDetail(_ id: UUID) {
        guard let seed = preferences.vaultedSeeds.first(where: { $0.id == id }) else { return }
        let xfp = seed.fingerprint.filter(\.isHexDigit)
        let label = seed.label.isEmpty ? "[\(xfp)]" : seed.label
        let encoded: Data
        if let mnemonic = try? BIP39Mnemonic(phrase: seed.mnemonic) {
            encoded = SecretStash.encode(entropy: mnemonic.entropy)
        } else {
            encoded = Data([0])
        }
        showStory(title: "", body: SeedVaultMenuCopy.detailStory(
            label: label, xfp: xfp, encodedSecret: encoded, origin: seed.origin))
    }

    func useVaultSeed(_ id: UUID) {
        guard let seed = preferences.vaultedSeeds.first(where: { $0.id == id }) else { return }
        if interceptVaultSeedForCCC(seed) { return }
        do {
            if let xprv = seed.extendedPrivateKey, !xprv.isEmpty {
                pendingExtendedKey = xprv
                pendingMnemonic = nil
            } else {
                pendingMnemonic = try BIP39Mnemonic(phrase: seed.mnemonic)
                pendingExtendedKey = nil
            }
            pendingEphemeral = true
            ephemeralOrigin = seed.origin
            try applyEphemeralSeed(offerVault: false)
        } catch { present(error) }
    }

    func beginDeleteVaultSeed(_ id: UUID) {
        guard let seed = preferences.vaultedSeeds.first(where: { $0.id == id }) else { return }
        let current = SeedVaultMenuCopy.normalizedXFP(rootKey?.fingerprintHex ?? "")
        let currentlyActive = tmpSeedActive && !current.isEmpty
            && SeedVaultMenuCopy.normalizedXFP(seed.fingerprint) == current
        pendingVaultDeleteID = id
        pendingVaultDeleteIsActive = currentlyActive
        showStory(
            title: SeedVaultMenuCopy.deleteTitle(xfp: seed.fingerprint),
            body: SeedVaultMenuCopy.deleteStory(xfp: seed.fingerprint, currentlyActive: currentlyActive),
            onConfirm: .deleteVaultSeedConfirm
        )
    }

    func deleteVaultSeed(_ id: UUID, keepSettings: Bool = false) {
        _ = keepSettings
        preferences.vaultedSeeds.removeAll { $0.id == id }
        persistPreferencesQuietly()
        selectedVaultSeedID = nil
        pendingVaultDeleteID = nil
        pendingVaultDeleteIsActive = false
        back()
    }

    func beginRenameVaultSeed(_ id: UUID) {
        guard let seed = preferences.vaultedSeeds.first(where: { $0.id == id }) else { return }
        renamingVaultSeedID = id
        passphraseInput = seed.label
        navigate(to: .passphrase)
    }

    func saveVaultRename() {
        guard let id = renamingVaultSeedID,
              let index = preferences.vaultedSeeds.firstIndex(where: { $0.id == id }) else { return }
        let label = String(passphraseInput.prefix(SeedVaultMenuCopy.renameMaxLength))
        guard !label.isEmpty else {
            renamingVaultSeedID = nil
            passphraseInput = ""
            back()
            return
        }
        preferences.vaultedSeeds[index].label = label
        persistPreferencesQuietly()
        renamingVaultSeedID = nil
        passphraseInput = ""
        back()
    }

    func handleHardwareKey(_ key: HardwareKey) {
        noteUserActivity()
        if lockIfIdle() { return }
        let resolved = resolvedHardwareKey(key)
        if consumeSelftestKey(resolved) { return }
        if consumeFactoryLockupKey(resolved) { return }
        switch resolved {
        case .power:
            if screen == .poweredOff {
                goToLockedRoot()
            } else if isUnlocked {
                lock()
            } else {
                goToLockedRoot()
            }
        case .qr: handleQRKey()
        case .nfc:
            if consumeTapsignerNFCKey() {
                break
            } else if handleWIFNFC() {
                break
            } else if handleXPRVNFC() {
                break
            } else if handleKeyTeleportNFCKey() {
                break
            } else if handleMultisigNFCKey() {
                break
            } else if screen == .story, story.onConfirm == .showXPUBQR {
                shareXPUBNFC()
            } else if screen == .story, story.onConfirm == .signedMessageExport {
                shareSignedMessageNFC()
            } else if screen == .story, story.onConfirm == .nfcShowAddress {
                shareNFCShownAddress()
            } else if screen == .addresses {
                shareAddressListNFC()
            } else if screen == .nfcReceive {
                break
            } else if screen == .psbtSigned {
                shareSignedResultNFC()
            } else if screen == .psbt, psbtReview == nil {
                requestPSBTNFCImport()
            } else {
                openNFCTools()
            }
        case .cancel:
            if screen == .psbt, psbtReview != nil { refusePSBT() }
            else { back() }
        case .up:
            if usesStoryPaging { applyStoryNav(.pageUp) }
            else { moveSelection(-1) }
        case .down:
            if usesStoryPaging { applyStoryNav(.pageDown) }
            else { moveSelection(1) }
        case .left:
            if screen == .addresses { pageAddresses(by: -10) }
            else if screen == .psbtExplorer { pagePSBTExplorer(by: -1) }
            else { moveSelection(-1) }
        case .right:
            if screen == .addresses { pageAddresses(by: 10) }
            else if screen == .psbtExplorer { pagePSBTExplorer(by: 1) }
            else { moveSelection(1) }
        case .home:
            if screen == .addresses { resetAddressExplorerHome() }
            else { goToHomeKey() }
        case .end: goToEndKey()
        case .pageUp: pageByKey(-1)
        case .pageDown: pageByKey(1)
        case .enter: activateCurrentSelection()
        case .character(let value):
            if keyboardSymbol, let function = HardwareKeyboardMapper.symbolFunctionKey(value) {
                handleFunctionKey(function)
                return
            }
            let mapped = applyShift(value)
            if !mapped.isEmpty { typeCharacter(mapped) }
        case .space: typeCharacter(" ")
        case .backspace: deleteCharacter()
        case .clear: clearCurrentField()
        case .tab: typeCharacter("\t")
        case .shift:
            keyboardShift.toggle()
            if keyboardSymbol { keyboardCaps.toggle() }
        case .symbol:
            keyboardSymbol.toggle()
            if keyboardShift { keyboardCaps.toggle() }
        case .lamp: flashTorch()
        }
    }

    /// Caps decoder keeps arrows; SYMBOL remaps d-pad; SHIFT+Delete is KEY_CLEAR.
    private func resolvedHardwareKey(_ key: HardwareKey) -> HardwareKey {
        let overlay = HardwareKeyboardMapper.applyHeldModifiers(
            key, symbol: keyboardSymbol, shift: keyboardShift, caps: keyboardCaps
        )
        if overlay == .clear { keyboardShift = false }
        return overlay
    }

    private var usesStoryPaging: Bool {
        switch screen {
        case .story, .viewIdentity, .brick, .walletExport,
             .psbt, .psbtSigned, .passphraseConfirm, .addressDetail,
             .typePasswordConfirm, .psbtExplorer, .addresses:
            true
        case .pinSetup:
            pinSetupPhase == .warning || pinSetupPhase == .proveRead
        default:
            false
        }
    }

    func noteStoryLineCount(_ count: Int) {
        storyLineCount = max(2, count)
    }

    private func applyStoryNav(_ command: FirmwareStoryPaging.Command) {
        let count = max(storyLineCount, currentStoryLineCount)
        storyTop = LCDStory.move(top: storyTop, lineCount: count, nav: command)
    }

    private var currentStoryLineCount: Int { lcdStoryPageLines.count }

    var lcdStoryPageLines: [LCDStoryLine] {
        LCDStory.compose(
            title: currentStoryTitle.isEmpty ? nil : currentStoryTitle,
            body: currentStoryBody,
            hintQR: lcdStoryHintQR,
            hintNFC: lcdStoryHintNFC
        )
    }

    private var lcdStoryHintQR: Bool {
        (screen == .story && story.hintQR) || screen == .psbtSigned || screen == .psbtExplorer
    }
    private var lcdStoryHintNFC: Bool {
        (screen == .story && story.hintNFC) || (screen == .psbtSigned && preferences.nfcSharingEnabled)
    }

    private var currentStoryTitle: String {
        switch screen {
        case .story: story.title
        case .pinSetup: "WARNING"
        case .psbt: screenTitle
        case .psbtSigned: screenTitle
        case .walletExport: walletExportTitle
        case .brick: screenTitle
        case .passphraseConfirm: pendingPassphraseXFP.isEmpty ? "" : "[\(pendingPassphraseXFP)]"
        case .psbtExplorer: screenTitle
        default: ""
        }
    }

    private var currentStoryBody: String {
        switch screen {
        case .story: story.body
        case .viewIdentity: identityText
        case .walletExport: walletExportText
        case .psbt: psbtReview == nil ? psbtEmptyStory : psbtApprovalBody
        case .passphraseConfirm: passphraseConfirmBody
        case .typePasswordConfirm: typePasswordConfirmBody
        case .addresses: addressListStory
        case .addressDetail: addressDetailStory
        case .psbtExplorer: psbtExplorerBody
        case .psbtSigned: signedTransactionStory
        case .pinSetup: pinSetupStoryBody
        case .brick: brickStoryBody
        default: story.body
        }
    }

    private var pinSetupStoryBody: String {
        if pinSetupPhase == .proveRead { return FirmwareCopy.proveRead }
        return pinSetupIsChange ? FirmwareCopy.changeMainPIN : FirmwareCopy.choosePIN
    }

    private var brickStoryBody: String {
        LoginUX.brickStory(numFails: max(failedPINAttempts, 1))
    }

    private var addressDetailStory: String {
        guard let address = selectedAddress else { return "" }
        return """
        Showing single address.

        \(address.path) =>
        \(Self.chunkAddress(address.address))

         Press (0) to sign message with this key.
        """
    }

    private func pageByKey(_ direction: Int) {
        if screen == .psbtExplorer {
            pagePSBTExplorer(by: direction)
            return
        }
        if screen == .addresses {
            // Q PAGE_UP/DOWN are in the address-story escape set (`:347-350`).
            pageAddresses(by: direction < 0 ? -10 : 10)
            return
        }
        if usesStoryPaging {
            applyStoryNav(direction < 0 ? .pageUp : .pageDown)
            return
        }
        applyMenuPager { pager in
            pager.page(direction)
        }
    }

    private func goToHomeKey() {
        if usesStoryPaging {
            applyStoryNav(.home)
            return
        }
        applyMenuPager { pager in
            pager.home()
        }
    }

    private func goToEndKey() {
        if usesStoryPaging {
            applyStoryNav(.end)
            return
        }
        applyMenuPager { pager in
            pager.gotoIndex(pager.count - 1)
        }
    }

    private func applyMenuPager(_ body: (inout LCDMenuPager) -> Void) {
        let count: Int
        switch screen {
        case .menu: count = menuItems.count
        case .wordQuiz: count = wordQuiz?.choices.count ?? 0
        default: return
        }
        var pager = LCDMenuPager(
            count: count,
            wrap: preferences.menuWrapping || count > 10,
            cursor: selectedMenuIndex,
            ypos: menuYPos
        )
        body(&pager)
        selectedMenuIndex = pager.cursor
        if screen == .menu { menuYPos = pager.ypos }
    }

    /// Q `login.py` / `ux_q1.py` KEY_CLEAR: wipe the current field, not one character.
    func clearCurrentField() {
        switch screen {
        case .unlock:
            pinInput = LoginUX.applyClear(PINEntryState(
                prefix: unlockPhase == .suffix ? pinPrefix : nil, current: pinInput
            )).current
        case .pinSetup:
            if pinSetupPhase == .prefix || pinSetupPhase == .confirmPrefix {
                pinPrefix = LoginUX.applyClear(PINEntryState(prefix: nil, current: pinPrefix)).current
            } else if pinSetupPhase == .suffix || pinSetupPhase == .confirmSuffix {
                pinInput = LoginUX.applyClear(PINEntryState(prefix: pinPrefix, current: pinInput)).current
            }
        case .importSeed: importSeedText = ""
        case .wordEntry: wordEntryPrefix = ""
        case .passphrase, .listedFileRename:
            if screen == .listedFileRename { errorMessage = nil }
            passphraseInput = ""
        case .diceRoll: diceRolls = ""
        case .entropyCollect:
            if entropyKind == .coin { coinFlips = "" }
            else if entropyKind == .diceMix { diceRolls = "" }
        case .calculator: calculatorExpression = ""
        case .serialREPL: serialREPLInput = ""
        case .messageSigning: messageText = ""
        case .accountNumber: accountPromptValue = ""
        case .verifyBackup, .backupPassword: backupPassword = ""
        case .hexEntry: hexEntryText = ""
        default: break
        }
    }

    private func flashTorch() {
        torchOn = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            torchOn = false
        }
    }

    /// Q SYMBOL+z/x/c/v/b/n → F1–F6 (`charcodes.DECODER_SYMBOL`).
    func handleFunctionKey(_ functionKey: Int) {
        if screen == .noteEditor {
            generateNotePassword(functionKey)
        }
    }

    private func applyShift(_ value: String) -> String {
        // Firmware decoder priority: caps_lock, then SYMBOL, then SHIFT (`keyboard.py`).
        if keyboardCaps {
            return value.uppercased()
        }
        if keyboardSymbol {
            return HardwareKeyboardMapper.symbolLayer(value) ?? ""
        }
        defer { if keyboardShift && value.rangeOfCharacter(from: .letters) != nil { keyboardShift = false } }
        guard keyboardShift else { return value }
        return value.uppercased()
    }

    func handleQRKey() {
        if screen == .factoryBagged || screen == .factoryDFU { return }
        if handleNotesQRKey() { return }
        if handlePaperWalletQRKey() { return }
        if handleKeyTeleportQRKey() { return }
        if handleXPRVQRKey() { return }
        if handleMultisigQRKey() { return }
        if !pendingTOTPSecret.isEmpty {
            let url = TOTP.otpauthURL(secretBase32: pendingTOTPSecret)
            qrPresentation = QRPresentation(title: FirmwareCopy.web2FATitle, payload: url, sensitive: true)
            return
        }
        if consumeSelftestKey(.qr) { return }
        if screen == .listedFileRename { return }
        if screen == .menu, currentMenu == .notes {
            pendingNoteQuickCreate = true
            showScanner = true
            return
        }
        if screen == .menu && (currentMenu == .noteActions || currentMenu == .noteGroup),
           selectedNote != nil {
            showSelectedNoteQR()
            return
        }
        if screen == .story, selectedNote != nil {
            showSelectedNoteQR()
            return
        }
        if screen == .menu {
            // Firmware `shortcut=KEY_QR` runs that item; ShortcutItem rows are never shown.
            if let index = menuItems.firstIndex(where: { Self.qrMenuShortcutTitles.contains($0.title) }) {
                selectedMenuIndex = index
                perform(menuItems[index].action)
                return
            }
            // EmptyWallet ShortcutItem(KEY_QR, f=scan_any_qr) — hidden, still scans.
            if currentMenu == .emptyWallet {
                pendingEphemeral = false
                showScanner = true
            }
            return
        }
        if screen == .story, story.onConfirm == .signedMessageExport {
            showSignedMessageQR()
            return
        }
        if screen == .story, story.onConfirm == .signedMessageQR {
            presentSignedMessageSignatureQR()
            return
        }
        switch screen {
        case .addresses:
            showAddressListQR()
        case .addressDetail:
            if selectedAddress != nil { showSelectedAddressQR() }
            else { showScanner = true }
        case .seedWords: showRecordWordsQR()
        case .psbtSigned: showPSBTQR()
        case .walletExport: showCurrentWalletExportQR()
        case .viewIdentity: showIdentityQR()
        case .messageSigning:
            showScanner = true
        case .psbtExplorer:
            if psbtExploreKind == .inputs {
                let captions = Array(DoneSigning.inputQRLabels.prefix(psbtExplorerQRPayloads.count))
                qrPresentation = QRPresentation(
                    title: captions.first ?? "TXID",
                    payloads: psbtExplorerQRPayloads,
                    sensitive: false,
                    captions: captions
                )
            } else if !psbtExplorerQRPayloads.isEmpty {
                qrPresentation = QRPresentation(title: screenTitle, payloads: psbtExplorerQRPayloads, sensitive: false)
            }
        case .nfcReceive:
            if nfcReceiveNeedsStandIn { showScanner = true }
        case .wordEntry:
            showScanner = true
        case .psbt:
            // Firmware empty Ready To Sign: KEY_QR → `_scan_any_qr`.
            showScanner = true
        case .story:
            if pendingBIP85Result != nil {
                qrPresentation = QRPresentation(title: pendingBIP85Result?.derivedXFP.map { "[\($0)]" } ?? "",
                                                payload: pendingBIP85Result?.qr ?? "", sensitive: true)
            } else if !xorWordLists.isEmpty, story.onConfirm == .xorShowParts {
                let qrs = xorWordLists.compactMap { try? BIP39Mnemonic(phrase: $0.joined(separator: " ")).seedQR }
                if !qrs.isEmpty {
                    qrPresentation = QRPresentation(title: "XOR SeedQR", payloads: qrs, sensitive: true)
                }
            } else if story.onConfirm == .xorRestoreMore, xorEntropyParts.count >= 2,
                      let preview = try? BIP39Mnemonic(entropy: SeedXOR.xor(xorEntropyParts)) {
                qrPresentation = QRPresentation(title: "SeedQR", payload: preview.seedQR, sensitive: true)
            } else if story.onConfirm == .nfcShowAddress || story.onConfirm == .nfcVerifiedAddress {
                showNFCShownAddressQR()
            } else if story.onConfirm == .nfcToolsStandIn {
                beginNFCToolsQRStandIn()
            } else {
                showScanner = true
            }
        default:
            showScanner = true
        }
    }

    func moveSelection(_ delta: Int) {
        if screen == .addresses {
            // Firmware `ux_show_story`: Up/Down page; do not wrap like MenuSystem when count>10.
            applyStoryNav(delta > 0 ? .pageDown : .pageUp)
            return
        }
        if screen == .menu {
            var pager = LCDMenuPager(
                count: menuItems.count,
                wrap: preferences.menuWrapping || menuItems.count > 10,
                cursor: selectedMenuIndex,
                ypos: menuYPos
            )
            if delta > 0 { pager.down() } else { pager.up() }
            selectedMenuIndex = pager.cursor
            menuYPos = pager.ypos
            return
        }
        let count: Int
        switch screen {
        case .wordQuiz: count = max(1, wordQuiz?.choices.count ?? 1)
        default: count = 1
        }
        let wrapping = preferences.menuWrapping || count > 10
        if wrapping {
            selectedMenuIndex = (selectedMenuIndex + delta + count) % count
        } else {
            selectedMenuIndex = min(max(0, selectedMenuIndex + delta), count - 1)
        }
    }

    func jumpMenu(to index: Int) {
        var pager = LCDMenuPager(
            count: menuItems.count,
            wrap: preferences.menuWrapping || menuItems.count > 10,
            cursor: selectedMenuIndex,
            ypos: menuYPos
        )
        pager.gotoIndex(index)
        selectedMenuIndex = pager.cursor
        menuYPos = pager.ypos
    }

    func activateCurrentSelection() {
        switch screen {
        case .nicknameSplash: dismissNicknameSplash()
        case .menu:
            if currentMenu == .xorVaultPick {
                confirmXORVaultSelection()
            } else if menuItems.indices.contains(selectedMenuIndex) {
                perform(menuItems[selectedMenuIndex].action)
            }
        case .unlock: unlock()
        case .pinSetup: advancePINSetup()
        case .seedWords: continueAfterSeedWords()
        case .wordQuiz:
            if quizWrongPause { break }
            reviewSeedWordsFromQuiz()
        case .diceRoll: finishDiceRolls()
        case .importSeed: validateImportedSeed()
        case .passphrase:
            if renamingVaultSeedID != nil { saveVaultRename() }
            else if renamingMultisigIndex != nil { saveMultisigRename() }
            else if textEntryIsNickname { saveNicknameFromField() }
            else if textEntryIsNoteGroup { saveNoteGroupFromField() }
            else if textEntryIsKeyboardTest { finishKeyboardTest() }
            else if textEntryIsBKPWOverride { commitBKPWOverride() }
            else if textEntryIsNotesImportPassword { commitNotesImportPassword() }
            else if textEntryIsCustomBackupPassword { commitCustomBackupPassword() }
            else if textEntryIsWIF { commitManualWIFEntry() }
            else if textEntryIsNFCSeed { finishNFCSeedPaste() }
            else if textEntryIsNFCTools { finishNFCToolsPaste() }
            else if textEntryIsPushtxURL { commitPushtxURLFromField() }
            else if teleportTextKind != .none { submitTeleportTextEntry() }
            else { applyPassphrasePreview() }
        case .listedFileRename:
            saveListedFileRename()
        case .passphraseConfirm: confirmPassphrase(save: false)
        case .addresses:
            // Firmware `show_n_addresses`: ENTER is a no-op; stay on the address story.
            break
        case .backupPassword:
            continueBackupPassword()
        case .verifyBackup:
            confirmVerifyBackupPassword()
        case .hexEntry:
            confirmHexEntry()
        case .accountNumber: submitAccountNumber()
        case .calculator: evaluateCalculator()
        case .serialREPL: submitSerialREPL()
        case .story:
            if selftestExpectedKey != nil { break }
            if story.confirmCode == nil { confirmStory() }
        case .noteEditor: addSecureNote()
        case .wordEntry: commitWordEntry()
        case .entropyCollect:
            if entropyKind == .mash { finishMashIfReady() }
            else if entropyKind == .coin { finishCoinIfReady() }
            else { finishDiceMixIfReady() }
        case .psbt:
            if psbtReview != nil { signCurrentPSBT() }
        case .nfcReceive:
            if nfcReceiveNeedsStandIn {
                nfcStandInKind = .psbt
                textEntryIsNFCTools = true
                passphraseInput = ""
                navigate(to: .passphrase)
            }
        case .psbtSigned:
            break
        case .brick:
            openBrickedCalculator()
        case .typePasswordIndex: submitTypePasswordIndex()
        case .typePasswordConfirm: confirmTypePasswordSend()
        case .messageSigning:
            if !messageText.isEmpty { signMessage() }
        case .walletExport:
            exportCurrentWalletText()
        default: break
        }
    }

    func perform(_ action: SimulatorMenuAction) {
        switch action {
        case .openMenu(let menu):
            if menu == .multisigWallets, !hasSeed, !tmpSeedActive {
                showStory(title: "", body: FirmwareCopy.needSeedForMultisig)
                return
            }
            if menu == .passphrase { startPassphraseFlow(); return }
            if menu == .temporarySeed, ephemeralPhrase == nil, ephemeralXPRV == nil, !preferences.seedVaultEnabled {
                showStory(title: "WARNING", body: FirmwareCopy.temporarySeedWarning,
                          onConfirm: .openTemporarySeed, confirmCode: "4")
                return
            }
            if menu == .addressExplorer, !preferences.skipAddressExplorerIntro {
                showStory(title: "Address Explorer", body: FirmwareCopy.addressExplorerIntro,
                          onConfirm: .continueAddressExplorer, confirmCode: "4")
                return
            }
            if menu == .scrambleKeys {
                showStory(title: "", body: FirmwareCopy.scrambleKeysIntro, onConfirm: .pickScramble)
                return
            }
            if menu == .killKey {
                showStory(title: "", body: FirmwareCopy.killKeyIntro, onConfirm: .pickKillKey)
                return
            }
            if menu == .nfcPushTx {
                beginNFCPushTxSetup()
                return
            }
            if let story = toggleMenuStoryIfDefault(menu) {
                pendingToggleMenu = menu
                showStory(title: "", body: story, onConfirm: .continueToggleChooser)
                return
            }
            if menu == .wifStore {
                presentWIFStoreMenu()
                return
            }
            if menu == .iAmDeveloper, DeveloperDebug.shouldConfirmOpeningDeveloperMenu(isDevMode: isDevMode) {
                showStory(title: DeveloperDebug.confirmTitle, body: DeveloperDebug.confirmBody,
                          onConfirm: .openDeveloperMenu)
                return
            }
            openMenu(menu)
        case .command(let command):
            perform(command)
        }
    }

    func perform(_ command: SimulatorCommand) {
        switch command {
        case .officialDemo: createOfficialDemoWallet()
        case .choosePIN:
            beginPINSetup(isChange: false)
        case .bagNumber:
            showBagNumberStory()
        case .bagMeNow:
            beginFactoryBagMeNow()
        case .shipWithoutBag:
            beginFactoryShipWithoutBag()
        case .factoryDFU:
            beginFactoryDFU()
        case .readyToSign: readyToSign()
        case .nfcSignPSBT: beginNFCSignPSBT()
        case .signAllReadyToSign: signAllReadyToSign()
        case .signReadyToSignPSBT(let id): signReadyToSignPSBT(id: id)
        case .scanAnyQR:
            scanExpectSecret = currentMenu == .importExisting
            pendingEphemeral = hasSeed && currentMenu == .home
            ephemeralOrigin = "From QR"
            showScanner = true
        case .scanEphemeralQR:
            pendingEphemeral = true
            scanExpectSecret = true
            ephemeralOrigin = "From QR"
            showScanner = true
        case .secureLogout: lock()
        case .viewIdentity: loadIdentity()
        case .selftest: runSelfTests()
        case .generateSeed(let count): createNewSeed(wordCount: count)
        case .diceSeed(let count): startDice(wordCount: count)
        case .importWords(let count): beginImport(wordCount: count)
        case .restoreBackup:
            restoreAsEphemeral = currentMenu == .temporarySeed || pendingEphemeral
            if hasSeed, !restoreAsEphemeral {
                showStory(title: "Restore Backup", body: FirmwareCopy.needClearSeed)
            } else {
                if restoreAsEphemeral, ephemeralOrigin.isEmpty || ephemeralOrigin == "unknown origin" {
                    ephemeralOrigin = "Coldcard Backup"
                }
                restoreBackupAllowsCleartext = false
                importPurpose = .backup
                showFileImporter = true
            }
        case .restoreBackupBlocked:
            showStory(title: "Restore Backup", body: FirmwareCopy.needClearSeed)
        case .enableSecureNotes:
            showStory(title: "Secure Notes", body: FirmwareCopy.enableSecureNotes, onConfirm: .enableSecureNotes)
        case .viewSeedWords:
            showStory(title: "WARNING", body: FirmwareCopy.viewSeedWordsWarning, onConfirm: .continueViewSeedWords)
        case .exportSeedQR:
            showStory(title: "Export SeedQR", body: FirmwareCopy.exportSeedQRWarning, onConfirm: .continueExportSeedQR)
        case .destroySeed:
            beginDestroySeed()
        case .lockDownSeed:
            beginLockDownSeed()
        case .nukeDevice:
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.nukeDeviceFirst, onConfirm: .nukeDeviceBrick)
        case .setNetwork(let network): applyNetwork(network)
        case .setDisplayUnits(let units):
            preferences.displayUnits = units; persistPreferencesQuietly(); back()
        case .setMaxFee(let fee):
            preferences.maxNetworkFee = fee; persistPreferencesQuietly(); back()
        case .setDeletePSBTs(let value):
            preferences.deletePSBTs = value
            persistPreferencesQuietly()
            back()
        case .setKeyboardEMU(let value):
            preferences.keyboardEmuEnabled = value
            persistPreferencesQuietly()
            back()
        case .setMenuWrapping(let value):
            preferences.menuWrapping = value; persistPreferencesQuietly(); back()
        case .setCalculatorLogin(let value):
            preferences.calculatorLogin = value
            persistPreferencesQuietly()
            back()
        case .setSighashChecks(let warnOnly):
            preferences.sighashWarnOnly = warnOnly
            persistPreferencesQuietly()
            back()
        case .clearOVCache:
            showStory(title: "Clear OV cache", body: FirmwareCopy.clearOVCache, onConfirm: .clearOVCache)
        case .clearAddressCache:
            showStory(title: "Clear Address cache", body: FirmwareCopy.clearAddressCache, onConfirm: .clearAddressCache)
        case .setAEStartIndex(let value):
            preferences.aeStartIndexEnabled = value
            persistPreferencesQuietly()
            back()
        case .setAlwaysShowHomeXFP(let value):
            preferences.alwaysShowHomeXFP = value; persistPreferencesQuietly(); back()
        case .changeMainPIN: beginPINSetup(isChange: true)
        case .setNickname:
            if nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showStory(title: "", body: FirmwareCopy.nicknameIntro, onConfirm: .beginNickname)
            } else {
                textEntryIsNickname = true
                passphraseInput = nickname
                navigate(to: .passphrase)
            }
        case .testLoginNow:
            testLoginNow()
        case .microSD2FAAddCard:
            beginMicroSD2FAEnroll()
        case .microSD2FACheckCard:
            checkMicroSD2FACard()
        case .microSD2FARemoveCard(let nonce):
            pendingMicroSD2FARemoveNonce = nonce
            showStory(title: "", body: MicroSD2FA.removeConfirm, onConfirm: .removeMicroSD2FA)
        case .backupSystem: startBackupSystem()
        case .verifyBackup:
            importPurpose = .verifyBackup
            showFileImporter = true
        case .cloneColdcard:
            startCloneWrite()
        case .cloneStart:
            startCloneIngest()
        case .importTapsignerBackup:
            startTapsignerBackupImport()
        case .importXPRV:
            startImportXPRV()
        case .signTextFile: requestSignTextFile()
        case .batchSignPSBT:
            startBatchSignFromMenu()
        case .listFiles:
            presentListedFiles()
        case .inspectListedFile(let id):
            inspectListedFile(id: id)
        case .verifySigFile:
            if currentMenu == .nfcTools {
                beginNFCVerifySigFile()
            } else {
                importPurpose = .verifySig
                showFileImporter = true
            }
        case .shareFileQR:
            importPurpose = .fileShare
            showFileImporter = true
        case .pickAddressType(let type):
            addressType = type
            preferences.lastAddressType = type
            persistPreferencesQuietly()
            customSingleAddress = false
            addressAllowChange = true
            addressChange = false
            addressPathTemplate = nil
            addressOverrideAccount = nil
            addressPageStart = addressStartIndex
            exploringMultisigIndex = nil
            lastAddressExplorerLabel = nil
            navigate(to: .addresses)
        case .changeAccount:
            accountPromptPurpose = .addressExplorer
            accountPromptValue = String(addressAccount)
            navigate(to: .accountNumber)
        case .customPath:
            customPathIsKeyExpression = false
            keypathRanged = true
            keypathAtRoot = true
            keypathCPath = "m"
            keypathLeaf = 0
            openMenu(.keypath)
        case .keypathDeeper(let cpath):
            keypathPendingDeeper = cpath
            accountPromptPurpose = .keypathIndex
            accountPromptValue = "0"
            navigate(to: .accountNumber)
        case .keypathDone(let path):
            customPathText = path
            addressPathTemplate = AddressExplorer.listCount(path: path) != nil ? path : nil
            if customPathIsKeyExpression {
                exportKeyExpressionCustomPath()
            } else {
                openMenu(.customPathFormat)
                jumpMenu(to: AddressExplorer.formatPickerIndex(path: customPathText))
            }
        case .applicationWasabi:
            startApplicationAddresses(.wasabi)
        case .samouraiPostmix:
            startApplicationAddresses(.samouraiPostmix)
        case .samouraiPremix:
            startApplicationAddresses(.samouraiPremix)
        case .changeStartIndex:
            accountPromptPurpose = .addressStartIndex
            accountPromptValue = String(addressStartIndex)
            navigate(to: .accountNumber)
        case .export(let kind): performWalletExport(kind)
        case .pickExportAddressType(let type): pickExportAddressType(type)
        case .pickMessageAddressType(let type): pickMessageAddressType(type)
        case .pickCustomPathFormat(let type):
            addressType = type
            showCustomPathWarning()
        case .restoreMaster:
            var body = "Restore main wallet and its settings?\n\n"
            var confirm: StoryConfirmAction = .restoreMasterConfirm
            if ephemeralPhrase != nil, !preferences.vaultedSeeds.contains(where: { $0.mnemonic == ephemeralPhrase }) {
                body += "Press ENTER to forget current temporary seed settings, or press (1) to save & keep those settings if same seed is later restored."
                confirm = .restoreMasterConfirm
            }
            showStory(title: "", body: body, onConfirm: confirm)
        case .beginKeyExpression: beginKeyExpressionExport()
        case .newNote:
            noteEditorMode = .createNote
            noteTitle = ""; noteBody = ""; noteUsername = ""; notePassword = ""; noteSite = ""
            noteGroupDraft = ""
            selectedNoteID = nil
            navigate(to: .noteEditor)
        case .newPassword:
            noteEditorMode = .createPassword
            noteTitle = ""; noteBody = ""; noteUsername = ""; notePassword = ""; noteSite = ""
            noteGroupDraft = ""
            selectedNoteID = nil
            navigate(to: .noteEditor)
        case .exportAllNotes: exportNotes(all: true)
        case .sortNotes: sortNotes()
        case .importNotes: startImportNotes()
        case .openNote(let id):
            selectedNoteID = id
            openMenu(.noteActions)
        case .viewNote:
            guard let note = selectedNote else { return }
            if note.kind == .password {
                var body = ""
                if !note.username.isEmpty { body += "User: \(note.username)\n" }
                body += "Password: (\(note.password.count) chars)\n"
                if !note.site.isEmpty { body += "Site: \(note.site)\n" }
                if !note.note.isEmpty { body += "\nNotes:\n" + note.note }
                showStory(title: note.title, body: body)
            } else {
                showStory(title: note.title, body: note.note)
            }
        case .viewPassword:
            guard let note = selectedNote, note.kind == .password else { return }
            showStory(title: note.title, body: note.password.isEmpty ? "<EMPTY>" : note.password)
        case .disableSecureNotes:
            preferences.secnapEnabled = false
            if var record {
                record.notes = []
                self.record = record
                try? persistRecord()
            }
            persistPreferencesQuietly()
            history.removeAll()
            menuStack.removeAll()
            openMenu(.home, remember: false)
        case .applyNotePassphrase:
            guard let note = selectedNote else { return }
            let readOnly = spendingPolicySnapshot.notesReadOnly
            let relatedKeys = spendingPolicySnapshot.relatedKeys
            let raw = note.kind == .password ? note.password : note.note
            guard SecureNotes.isB39PassApplicable(
                raw, readOnly: readOnly, relatedKeys: relatedKeys, wordBased: wordBasedSeed
            ) else { return }
            let stripped = SecureNotes.rstripPassphrase(raw)
            guard SecureNotes.isB39PassApplicable(
                stripped, readOnly: readOnly, relatedKeys: relatedKeys, wordBased: wordBasedSeed
            ) else { return }
            passphraseInput = stripped
            applyPassphrasePreview()
        case .openNoteGroup(let group):
            selectedNoteGroup = group
            openMenu(.noteGroup)
        case .pickNoteGroup(let group):
            pickNoteGroup(group)
        case .newNoteGroup:
            textEntryIsNoteGroup = true
            passphraseInput = ""
            navigate(to: .passphrase)
        case .generateNotePassword(let key):
            generateNotePassword(key)
        case .editNote:
            guard let note = selectedNote else { return }
            noteTitle = note.title
            noteUsername = note.username
            notePassword = note.password
            noteSite = note.site
            noteBody = note.note
            noteGroupDraft = note.group
            noteEditorMode = note.kind == .password ? .editPasswordMetadata : .editNote
            navigate(to: .noteEditor)
        case .changeNotePassword:
            guard let note = selectedNote else { return }
            noteTitle = note.title
            noteUsername = note.username
            notePassword = note.password
            noteSite = note.site
            noteBody = note.note
            noteEditorMode = .changePassword
            navigate(to: .noteEditor)
        case .deleteNote:
            if let id = selectedNoteID { deleteSecureNote(id: id) }
        case .exportNote: exportNotes(all: false)
        case .signNote: signSelectedNote()
        case .editPhrase: navigate(to: .passphrase)
        case .restoreSavedPassphrase(let id): restoreSavedPassphrase(id)
        case .deleteSavedPassphrase(let id):
            selectedSavedPassphraseID = id
            // Firmware confirms first (pwsave.py: "Delete saved passphrase?").
            showStory(title: "Are you SURE ?!?", body: "Delete saved passphrase?",
                      onConfirm: .confirmDeleteSavedPassphrase)
        case .openSavedPassphrase(let id):
            selectedSavedPassphraseID = id
            openMenu(.savedPassphraseActions)
        case .sendPassword:
            guard let note = selectedNote, note.kind == .password else { return }
            guard EmulatedKeyboard.canType(note.password) else {
                showStory(title: "", body: SecureNotes.sendPasswordUntypeable)
                return
            }
            UIPasteboard.general.string = TypePasswords.clipboardPayload(password: note.password)
            showStory(title: "", body: TypePasswords.sentConfirmation(password: note.password))
        case .showVersion:
            showStory(title: "Show Version", body: "COLDCARD Q Simulator\nUnofficial iOS 17+ SwiftUI simulator\nFirmware reference: 15de4a0c1a4587d8f6cf93b3763afbcbe0a7581c\n\nThis is not Coldcard firmware and cannot be upgraded.")
        case .keyExpressionCustomPath:
            customPathIsKeyExpression = true
            keypathRanged = false
            keypathAtRoot = true
            keypathCPath = "m"
            keypathLeaf = 0
            openMenu(.keypath)
        case .signMessageFromAddress:
            startMessageSigningFromAddress()
        case .generateEphemeralSeed(let count): createNewSeed(wordCount: count, ephemeral: true)
        case .diceEphemeralSeed(let count): startDice(wordCount: count, ephemeral: true)
        case .importEphemeralWords(let count): beginImport(wordCount: count, ephemeral: true)
        case .setSeedVault(let enabled):
            if !enabled, !preferences.vaultedSeeds.isEmpty {
                showStory(title: "", body: FirmwareCopy.seedVaultDisableBlocked)
                return
            }
            preferences.seedVaultEnabled = enabled
            persistPreferencesQuietly()
            back()
        case .signMessage:
            beginNFCSignMessage()
        case .explorePSBTInputs:
            startPSBTExplorer(.inputs)
        case .explorePSBTOutputs:
            startPSBTExplorer(.outputs)
        case .exportAddressCSV:
            exportAddressCSV(destination: .sdCard)
        case .mashEntropy:
            showStory(title: FirmwareCopy.mashEntropyTitle,
                      body: FirmwareCopy.mashEntropyStory,
                      onConfirm: .continueMash)
        case .coinEntropy:
            showStory(title: FirmwareCopy.coinEntropyTitle,
                      body: FirmwareCopy.coinEntropyStory,
                      onConfirm: .continueCoin)
        case .diceMixEntropy:
            startDice(wordCount: entropyWordCount, ephemeral: pendingEphemeral, mixWithTRNG: true)
        case .addCurrentTmpToVault:
            offerAddCurrentToVault(fromMenu: true)
        case .useVaultSeed(let id):
            useVaultSeed(id)
        case .deleteVaultSeed(let id):
            beginDeleteVaultSeed(id)
        case .renameVaultSeed(let id):
            beginRenameVaultSeed(id)
        case .openVaultSeed(let id):
            selectedVaultSeedID = id
            openMenu(.seedVaultActions)
        case .showVaultSeedDetail(let id):
            showVaultSeedDetail(id)
        case .menuCancel:
            back()
        case .xorSplit: beginXORSplit()
        case .xorRestore: beginXORRestore()
        case .drvEntro: beginBIP85()
        case .typePasswords: beginTypePasswords()
        case .drvEntroKind(let raw):
            pendingBIP85Kind = BIP85Kind(rawValue: raw) ?? .words12
            accountPromptPurpose = .bip85Index
            accountPromptValue = "0"
            navigate(to: .accountNumber)
        case .setScrambleKeys(let value):
            preferences.scrambleKeys = value
            persistPreferencesQuietly()
            back()
        case .setKillKey(let value):
            preferences.killKey = value
            persistPreferencesQuietly()
            back()
        case .setLoginCountdown(let minutes):
            preferences.loginCountdownMinutes = minutes
            persistPreferencesQuietly()
            back()
        case .setB85Unlimited(let value):
            preferences.b85Unlimited = value
            persistPreferencesQuietly()
            back()
        case .setIdleTimeout(let seconds):
            preferences.idleTimeoutSeconds = seconds
            persistPreferencesQuietly()
            back()
        case .setIdleTimeoutBattery(let seconds):
            preferences.idleTimeoutBatterySeconds = seconds
            persistPreferencesQuietly()
            back()
        case .setNFCSharing(let value):
            preferences.nfcSharingEnabled = value
            persistPreferencesQuietly()
            back()
        case .setUSBPort(let value):
            preferences.usbPortEnabled = value
            preferences.du = FirstTimeUX.du(usbEnabled: value)
            persistPreferencesQuietly()
            back()
        case .setVirtualDisk(let value):
            preferences.virtualDiskMode = min(max(value, 0), 2)
            persistPreferencesQuietly()
            if preferences.virtualDiskMode != 0 { VirtualDiskFolder.ensureDirectory() }
            syncVirtualDiskMonitor()
            back()
        case .formatRamDisk:
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.formatRamDisk, onConfirm: .formatRamDisk)
        case .formatSDCard:
            showStory(title: "Are you SURE ?!?", body: FirmwareCopy.formatSDCard, onConfirm: .formatSDCard)
        case .importEphemeralNFC:
            beginEphemeralSeedNFCImport()
        case .nfcPushTransaction:
            beginPushTransaction()
        case .setPushtxURL(let url):
            applyPushtxURL(url)
        case .editPushtxURL:
            beginEditPushtxURL()
        case .nfcShowAddress:
            beginNFCShowAddress()
        case .nfcVerifyAddress:
            beginNFCVerifyAddress()
        case .nfcImportMultisig:
            beginNFCToolsImportMultisig()
        case .nfcFileShare:
            beginNFCFileShare()
        case .keyboardTest: startKeyboardTest()
        case .bbqrDemo:
            presentBBQr(title: DeveloperDebug.bbqrDemoTitle,
                        data: DeveloperDebug.bbqrDemoPayload(),
                        fileType: DeveloperDebug.bbqrDemoFileType)
        case .nfcTest: startNFCTest()
        case .clearTested:
            preferences.tested = false
            persistPreferencesQuietly()
            warmReset()
        case .debugAssert:
            showStory(title: DeveloperDebug.yikesTitle, body: DeveloperDebug.assertFatalBody,
                      onConfirm: .warmResetAfterCrash)
        case .debugExcept:
            showStory(title: DeveloperDebug.yikesTitle, body: DeveloperDebug.exceptFatalBody,
                      onConfirm: .warmResetAfterCrash)
        case .checkFirewallRead:
            startCheckFirewallRead()
        case .serialREPL:
            startSerialREPL()
        case .reflashGPU:
            startReflashGPU()
        case .warmReset: warmReset()
        case .restoreDeveloperBackup:
            restoreAsEphemeral = hasSeed
            restoreBackupAllowsCleartext = true
            importPurpose = .backup
            showFileImporter = true
        case .bkpwOverride: showBKPWOverrideStory()
        case .menuNoop:
            break
        case .unimplemented(let name):
            handleUnimplemented(name)
        default:
            if performKeyTeleportCommand(command) { break }
            if performPaperWalletCommand(command) { break }
            if performWIFCommand(command) { break }
            if performTrickCommand(command) { break }
            if performMultisigCommand(command) { break }
            if performSpendingCommand(command) { break }
            handleUnimplemented(String(describing: command))
        }
    }

    func exportKeyExpressionCustomPath() {
        guard let root = rootKey else { return }
        let pathText = customPathText
        customPathIsKeyExpression = false
        runExport(title: "Key Expression", filenameHint: "key_expr.txt") {
            let path = try DerivationPath(pathText)
            return Data(try WalletExporter.keyExpression(root: root, path: path).utf8)
        }
    }

    func saveNicknameFromField() {
        settingsNickname = String(passphraseInput.prefix(100))
        textEntryIsNickname = false
        passphraseInput = ""
        saveSettings()
        back()
    }

    func saveListedFileRename() {
        // Firmware `ux_input_text`: ENTER with len < min_len stays on the field (`ux_q1.py`).
        if passphraseInput.count < 3 {
            errorMessage = FirmwareCopy.uxInputTextNeedCharacters(3)
            return
        }
        let name = passphraseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        passphraseInput = ""
        back()
        do {
            try SimulatorCardStandin.validateRename(name)
            guard var file = selectedListedFile else { return }
            if file.volume == .virtDisk { virtDiskMonitor.noteWritten(filename: name) }
            file = try SimulatorCardStandin.rename(file, to: name)
            selectedListedFile = file
            presentListedFileDetail()
        } catch {
            showStory(title: "Failure",
                      body: FirmwareCopy.listedFileRenameFailedPrefix + (error.localizedDescription),
                      onConfirm: .listedFileRestoreDetail)
        }
    }

    func saveNoteGroupFromField() {
        let group = String(passphraseInput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SecureNotesSupport.oneLineLimit))
        textEntryIsNoteGroup = false
        passphraseInput = ""
        pickNoteGroup(group)
    }

    func generateNotePassword(_ functionKey: Int) {
        switch functionKey {
        case 1:
            guard let entropy = try? SecureRandom.bytes(count: 16),
                  let mnemonic = try? BIP39Mnemonic(entropy: entropy) else { return }
            notePassword = mnemonic.phrase
        case 2:
            guard let entropy = try? SecureRandom.bytes(count: 32),
                  let mnemonic = try? BIP39Mnemonic(entropy: entropy) else { return }
            notePassword = mnemonic.words.map { String($0.prefix(4)) }.joined(separator: " ")
        case 3:
            guard let first = try? SecureRandom.bytes(count: 32),
                  let se1 = try? SecureRandom.bytes(count: 32),
                  let se2 = try? SecureRandom.bytes(count: 8) else { return }
            let seedA = SHA2.doubleSHA256(first + se1 + se2)
            guard let firstB = try? SecureRandom.bytes(count: 32),
                  let se1B = try? SecureRandom.bytes(count: 32),
                  let se2B = try? SecureRandom.bytes(count: 8) else { return }
            let seedB = SHA2.doubleSHA256(firstB + se1B + se2B)
            notePassword = SecureNotes.densePassword(from: seedA + seedB)
        case 4:
            let words = BIP39EnglishWords.all
            func cap() -> String {
                let word = words.randomElement() ?? "able"
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            var symbols = Array("!@#$%^&*-=|+~?")
            symbols.shuffle()
            let number = Int.random(in: 0..<100_000)
            notePassword = cap() + cap() + String(symbols.prefix(3)) + String(format: "%04d", number)
        case 5:
            beginBIP85PasswordPick()
        case 6:
            notePassword = SecureNotes.toggleCase(notePassword)
        default:
            break
        }
    }

    func createNoteFromQR(_ text: String) {
        guard text.count >= 5 else { return }
        guard var record else { return }
        let note = SecureNote(kind: .note, title: SecureNotesSupport.titleForScannedText(text), note: text)
        record.notes.append(note)
        self.record = record
        do { try persistRecord() }
        catch { present(error) }
        selectedNoteID = note.id
        statusMessage = "Saved."
        openMenu(.noteActions)
    }

    func showSelectedNoteQR() {
        guard let note = selectedNote else { return }
        let payload = note.kind == .password ? note.password : note.note
        guard !payload.isEmpty else {
            showStory(title: note.title, body: "Unable to display as QR.")
            return
        }
        qrPresentation = QRPresentation(title: note.title, payload: payload, sensitive: true)
    }

    func cancelPendingNoteQuickCreate() {
        pendingNoteQuickCreate = false
        pendingBagScan = false
        resetBBQrScan()
    }

    func resetBBQrScan() {
        bbqrCollector.reset()
        bbqrScanProgress = nil
    }

    func typeCharacter(_ value: String) {
        if screen == .poweredOff { return }
        // Kill key is checked before nickname dismiss (`actions.show_nickname`, `login.py`).
        if LoginUX.matchesKillKey(value, killKey: preferences.killKey),
           LoginUX.killKeyApplies(in: killKeyContext) {
            performKillWipe()
            return
        }
        if screen == .nicknameSplash {
            dismissNicknameSplash()
            return
        }
        if screen == .diceRoll || (screen == .entropyCollect && entropyKind == .diceMix),
           let first = value.first, "123456".contains(first) {
            addDiceRoll(first)
            return
        }
        if screen == .nfcReceive {
            if nfcReceiveNeedsStandIn, value == "1" {
                consumeNFCReceiveStandInFile()
            }
            return
        }
        if screen == .story {
            handleStoryKey(value)
            return
        }
        if screen == .listedFileRename, value == "\t" { return }
        if screen == .passphrase, value == "\t" {
            if textEntryIsKeyboardTest {
                // Keyboard Test types TAB as a character.
            } else if textEntryIsPushtxURL || textEntryIsWIF {
                return
            } else if teleportTextKind == .numericPassword || teleportTextKind == .paranoidPassword {
                return
            } else {
                completePassphraseBIP39()
                return
            }
        }
        if screen == .passphraseConfirm, value == "1" {
            confirmPassphrase(save: true)
            return
        }
        if screen == .backupPassword, value == "6", pendingNotesFileExport {
            exportCleartextBackup()
            return
        }
        if screen == .seedWords, value == "6", pendingMnemonic != nil {
            requestSkipSeedQuiz()
            return
        }
        if screen == .seedWords, value == "1" {
            showRecordWordsQR()
            return
        }
        if screen == .wordQuiz, !quizWrongPause, let digit = Int(value), (1...3).contains(digit),
           let quiz = wordQuiz, quiz.choices.indices.contains(digit - 1) {
            answerWordQuiz(quiz.choices[digit - 1])
            return
        }
        if screen == .addresses, value == "0" {
            // Firmware: (0) toggles change addresses on the list; signing via (0) exists
            // only on the single custom-path address (address_explorer.py).
            if customSingleAddress { startMessageSigningFromAddress() }
            else if addressAllowChange { toggleChangeAddresses() }
            return
        }
        if screen == .addresses, value == "1" { exportAddressCSV(destination: .sdCard); return }
        if screen == .addresses, value.lowercased() == "b" {
            exportAddressCSV(destination: .lowerSlot)
            return
        }
        if screen == .addresses, value == "2", preferences.virtualDiskMode != 0 {
            exportAddressCSV(destination: .virtDisk)
            return
        }
        if screen == .psbt, psbtReview != nil, value.lowercased() == "b", psbtInputMethod == "sd" {
            signCurrentPSBT(writeToLowerSlot: true)
            return
        }
        if screen == .psbt, psbtReview != nil, value == "2" {
            openMenu(.psbtExplorer)
            return
        }
        if screen == .psbt, psbtReview == nil {
            let key = value.lowercased()
            if key == "b" {
                requestPSBTImport()
                return
            }
            if key == "2" {
                // Firmware `import_export_prompt_decode`: (2) is Virtual Disk, not Demo PSBT.
                if virtualDiskEnabled { importPSBTFromVirtualDisk() }
                return
            }
            // Fall through so 7/9/0 still page the story (`ux_show_story` + `strict_escape`).
        }
        if screen == .psbtExplorer, value == "7" { pagePSBTExplorer(by: -1); return }
        if screen == .psbtExplorer, value == "9" { pagePSBTExplorer(by: 1); return }
        if screen == .psbtExplorer, value == "2" { promptPSBTExploreIndex(); return }
        if screen == .psbtExplorer, value == "4" { handleQRKey(); return }
        if handleSignedPSBTKey(value) { return }
        if screen == .walletExport, value == "1" {
            exportCurrentWalletText()
            return
        }
        if screen == .walletExport, value == "2", let kind = pendingExport {
            switch kind {
            case .xpubSegwit, .xpubClassic, .xpubWrapped:
                exportSLIP132.toggle()
                finishWalletExport(kind, account: exportAccount)
            default: break
            }
            return
        }
        if screen == .menu {
            activateMenuShortcut(value)
            return
        }
        if usesStoryPaging, screen != .brick, screen != .addressDetail,
           let command = FirmwareStoryPaging.digitCommand(value) {
            applyStoryNav(command)
            return
        }
        switch screen {
        case .brick:
            // Firmware: any key other than (6) drops into the calculator REPL (login.py).
            if LoginUX.brickKeyEntersCalculator(value) { openBrickedCalculator() }
        case .unlock:
            appendPINDigit(toUnlock: true, value)
        case .pinSetup:
            appendPINDigit(toUnlock: false, value)
        case .importSeed: customPathOrImportAppend(value)
        case .wordEntry: typeWordEntry(value)
        case .passphrase, .listedFileRename:
            if screen == .listedFileRename { errorMessage = nil }
            var incoming = value
            let limit: Int
            if screen == .listedFileRename { limit = 32 }
            else if textEntryIsPushtxURL { limit = 256 }
            else if textEntryIsWIF { limit = 52 }
            else if renamingMultisigIndex != nil { limit = 20 }
            else if renamingVaultSeedID != nil { limit = SeedVaultMenuCopy.renameMaxLength }
            else if textEntryIsKeyboardTest || textEntryIsBKPWOverride || textEntryIsNotesImportPassword || textEntryIsCustomBackupPassword { limit = DeveloperDebug.bkpwMaxLength }
            else if teleportTextKind == .numericPassword {
                incoming = String(value.filter(\.isNumber))
                limit = KeyTeleport.numericCodeLength
            } else if teleportTextKind == .paranoidPassword {
                limit = KeyTeleport.paranoidPasswordLength
            } else {
                incoming = BIP39Passphrase.sanitized(value)
                limit = BIP39Passphrase.maxLength
            }
            let room = max(0, limit - passphraseInput.count)
            if room > 0 { passphraseInput.append(contentsOf: incoming.prefix(room)) }
        case .diceRoll:
            if let first = value.first { addDiceRoll(first) }
        case .entropyCollect:
            if entropyKind == .mash { mashKey(value) }
            else if entropyKind == .coin { addCoinFlip(value) }
            else if entropyKind == .diceMix, let first = value.first { addDiceRoll(first) }
        case .calculator:
            let room = max(0, CalculatorLogin.maxInputLength - calculatorExpression.count)
            if room > 0 { calculatorExpression.append(contentsOf: value.prefix(room)) }
        case .serialREPL: serialREPLInput.append(contentsOf: value)
        case .messageSigning:
            let remaining = max(0, messageMaxLength - messageText.count)
            if remaining > 0 { messageText.append(contentsOf: value.prefix(remaining)) }
        case .accountNumber: accountPromptValue.append(contentsOf: value.filter(\.isNumber))
        case .typePasswordIndex:
            if let digit = value.first, value.count == 1 {
                typePasswordIndexText = TypePasswords.appendDigit(typePasswordIndexText, digit)
            }
        case .verifyBackup: backupPassword.append(contentsOf: value)
        case .hexEntry:
            hexEntryText = Self.normalizedHexEntry(hexEntryText + value)
        default: break
        }
    }

    private func handleStoryKey(_ value: String) {
        if handleBatchSignImportKey(value) { return }
        if handlePaperWalletStoryKey(value) { return }
        if handleSpendingStoryKey(value) { return }
        if handleCloneTapsignerStoryKey(value) { return }
        if handleXPRVStoryKey(value) { return }
        if handleWIFStoryKey(value) { return }
        if handleTrickStoryKey(value) { return }
        if handleKeyTeleportStoryKey(value) { return }
        if handleMultisigStoryKey(value) { return }
        if handleNotesStoryKey(value) { return }
        if story.onConfirm == .signedMessageExport {
            let key = value.lowercased()
            if key == "1" { exportSignedMessage(); return }
            if key == "b" { exportSignedMessageToCard(.microSD); return }
            if key == "2", virtualDiskEnabled { exportSignedMessageToCard(.virtDisk); return }
        }
        if let code = story.confirmCode, value == code {
            confirmStory()
            return
        }
        if story.onConfirm == .pasteNFCSeed, value == "1" {
            beginNFCSeedFileImport()
            return
        }
        if story.onConfirm == .nfcToolsStandIn, value == "1" {
            beginNFCStandInFileImport()
            return
        }
        if story.onConfirm == .nfcVerifiedAddress, value == "0" {
            startMessageSigningFromNFCVerifiedAddress()
            return
        }
        if story.onConfirm == .enrollImportedMultisig, value == "1" {
            if pendingNFCMultisig != nil {
                showNFCImportedMultisigXPUBs()
            } else {
                _ = handleMultisigStoryKey(value)
            }
            return
        }
        if story.onConfirm == .listedFileDetail {
            if value == "1" { beginListedFileRename(); return }
            if value == "4" { signListedFileDigest(); return }
            if value == "6" { deleteListedFile(); return }
            return
        }
        if story.onConfirm == .batchSignConfirm, value == "1" {
            skipCurrentBatchPSBT()
            return
        }
        if story.onConfirm == .showXPUBQR {
            if value == "1", pendingExport != .xpubMaster {
                accountPromptPurpose = .walletExport
                accountPromptValue = String(exportAccount)
                navigate(to: .accountNumber)
                return
            }
            if value == "2", pendingExport == .xpubSegwit || pendingExport == .xpubWrapped {
                exportSLIP132.toggle()
                showXPUBExportStory()
                return
            }
        }
        if story.onConfirm == .continueAddressExplorer, value == "6" {
            story.onConfirm = .hideAddressExplorerIntro
            confirmStory()
            return
        }
        if story.onConfirm == .continueExport, value == "1", pendingExport?.asksAccount == true {
            story.onConfirm = .exportPickAccount
            confirmStory()
            return
        }
        if story.onConfirm == .openKeyExpressionMenu, value == "1" {
            story.onConfirm = .exportPickAccount
            confirmStory()
            return
        }
        if story.onConfirm == .descriptorIntExt, value == "1" {
            descriptorCombined = false
            story.onConfirm = nil
            back()
            exportAddressTypes = AddressType.singlesigExportOrder
            openMenu(.exportAddressType)
            return
        }
        if story.onConfirm == .messageChange, value == "0" {
            messageChange = true
            story.onConfirm = nil
            promptMessageIndex()
            return
        }
        if story.onConfirm == .signedMessageQR, value == "0" {
            presentSignedMessageRFCQR()
            return
        }
        if story.onConfirm == .simpleTextQR, value == "0" {
            startQRSignMsg()
            return
        }
        if story.onConfirm == .continuePassphrase, value == "2" {
            preferences.skipPassphraseIntro = true
            persistPreferencesQuietly()
            confirmStory()
            return
        }
        if story.onConfirm == .skipBackupCache, value == "1" {
            story.onConfirm = .cacheBackupPassword
            confirmStory()
            return
        }
        if story.onConfirm == .backupFirstCopyWritten, value == "2" {
            exportAnotherBackupCopy()
            return
        }
        if story.onConfirm == .backupMoreCopies, value == "2" {
            exportAnotherBackupCopy()
            return
        }
        if story.onConfirm == .notesCustomPassword, value == "1" {
            story.onConfirm = nil
            if let previous = history.popLast() { screen = previous }
            beginCustomBackupPasswordEntry()
            return
        }
        if story.onConfirm == .skipVaultSave, value == "1" {
            savePendingOrCurrentToVault()
            let xfp = pendingEphemeralXFP() ?? rootKey?.fingerprintHex ?? "--------"
            showStory(title: "", body: SeedVaultMenuCopy.savedStory(xfp: xfp), onConfirm: .continueAfterVaultSave)
            return
        }
        if story.onConfirm == .deleteVaultSeedConfirm, value == "1", !pendingVaultDeleteIsActive {
            if let id = pendingVaultDeleteID {
                deleteVaultSeed(id, keepSettings: true)
            }
            return
        }
        if story.onConfirm == .restoreMasterConfirm, value == "1" {
            story.onConfirm = .restoreMasterPreserve
            confirmStory()
            return
        }
        if story.onConfirm == .xorSplitParts, let count = Int(value), (2...4).contains(count) {
            xorPendingPartCount = count
            showStory(
                title: SeedXORStories.splitIntoTitle(count),
                body: SeedXORStories.splitIntoParts(count),
                onConfirm: .xorSplitRNG
            )
            return
        }
        if story.onConfirm == .xorSplitRNG, value == "2" {
            performXORSplit(useRNG: true)
            return
        }
        if story.onConfirm == .xorShowParts, value == "4" {
            handleQRKey()
            return
        }
        if story.onConfirm == .xorRestoreWordCount {
            if value == "1" { xorDesiredWordCount = 12; continueXORRestoreAfterWordCount(); return }
            if value == "2" { xorDesiredWordCount = 18; continueXORRestoreAfterWordCount(); return }
        }
        if story.onConfirm == .xorRestoreInclude, value == "1", xorCanIncludeCurrent {
            continueXORRestoreAfterInclude(includeCurrent: true)
            return
        }
        if story.onConfirm == .xorRestoreVault, value == "2" {
            continueXORRestoreAfterVault(addVault: true)
            return
        }
        if story.onConfirm == .xorRestoreMore {
            if value == "1" {
                beginWordEntry(purpose: .xorPart, wordCount: xorDesiredWordCount)
                return
            }
            if value == "2", xorEntropyParts.count >= 2 {
                finishXORCombine()
                return
            }
        }
        if story.onConfirm == .confirmPassphrase, value == "1" {
            story.onConfirm = .savePassphrase
            confirmStory()
            return
        }
        if story.onConfirm == .bip85Reveal, value == "1" {
            exportBIP85Result()
            return
        }
        if story.onConfirm == .bip85Reveal, value == "0" {
            applyBIP85AsTemporary()
            return
        }
        if story.onConfirm == .bkpwOverride {
            if value == "0" {
                beginBKPWPasswordEntry()
                return
            }
            if value == "1", storedBackupPassword != nil {
                showStory(title: DeveloperDebug.confirmTitle, body: DeveloperDebug.bkpwDeleteConfirm,
                          onConfirm: .bkpwDelete)
                return
            }
            if value == "2", storedBackupPassword != nil {
                showStory(title: DeveloperDebug.confirmTitle, body: DeveloperDebug.bkpwShowConfirm,
                          onConfirm: .bkpwShow)
                return
            }
        }
        // Firmware `ux.py`: 0/HOME top, 7/PAGE_UP, 9/PAGE_DOWN after escape/confirm keys.
        if let command = FirmwareStoryPaging.digitCommand(value) {
            applyStoryNav(command)
        }
    }

    private func handleMenuShortcut(_ value: String) {
        // Firmware `menu.py` wait_choice: SPACE selects the current row.
        if value == " " {
            activateCurrentSelection()
            return
        }
        if currentMenu == .xorVaultPick, value == "1" {
            toggleXORVaultPick()
            return
        }
        if let digit = Int(value), (1...9).contains(digit), menuItems.indices.contains(digit - 1) {
            jumpMenu(to: digit - 1)
            return
        }
        let key = value.lowercased()
        if let index = menuItems.firstIndex(where: { firmwareLetterShortcut(for: $0.title) == key }) {
            jumpMenu(to: index)
            perform(menuItems[index].action)
            return
        }
        guard let letter = value.uppercased().first, letter.isLetter else { return }
        let count = menuItems.count
        guard count > 0 else { return }
        let start = (selectedMenuIndex + 1) % count
        for offset in 0..<count {
            let index = (start + offset) % count
            if menuItems[index].title.uppercased().first == letter {
                jumpMenu(to: index)
                return
            }
        }
    }

    /// Firmware `MenuItem(..., shortcut=)` letters (`flow.py`, `actions.py`).
    private func firmwareLetterShortcut(for title: String) -> String? {
        switch currentMenu {
        case .home:
            switch title {
            case "Ready To Sign": "r"
            case "Passphrase": "p"
            case "Address Explorer": "x"
            case "Secure Notes & Passwords": "n"
            case "Type Passwords": "e"
            case "Seed Vault": "v"
            case "Advanced/Tools": "t"
            case "Settings": "s"
            case "Restore Master": "m"
            default: nil
            }
        case .virgin, .emptyWallet:
            title == "Advanced/Tools" ? "t" : nil
        case .factory:
            switch title {
            case "DFU Upgrade": "u"
            case "Debug Functions": "f"
            case "Perform Selftest": "s"
            default: nil
            }
        case .advanced, .advancedVirgin, .advancedEmpty:
            switch title {
            case "Export Wallet": "x"
            case "Spending Policy": "s"
            case "Danger Zone": "z"
            default: nil
            }
        case .settings:
            title == "Multisig Wallets" ? "m" : nil
        default:
            nil
        }
    }

    private func appendPINDigit(toUnlock: Bool, _ value: String) {
        // Firmware accepts ENTER, space, '-', '_' and TAB to end a PIN part (login.py).
        if value == "-" || value == "_" || value == " " || value == "\t" {
            if toUnlock { unlock() } else { advancePINSetup() }
            return
        }
        let filtered = value.filter(\.isNumber)
        guard let raw = filtered.first else { return }
        let digit = toUnlock ? LoginUX.scrambledDigit(raw, map: scrambleDigitMap) : raw
        if toUnlock {
            if pinInput.count >= 6 { pinInput.removeLast() }
            pinInput.append(digit)
            return
        }
        if pinSetupPhase == .prefix || pinSetupPhase == .confirmPrefix {
            if pinPrefix.count >= 6 { pinPrefix.removeLast() }
            pinPrefix.append(digit)
        } else if pinSetupPhase == .suffix || pinSetupPhase == .confirmSuffix {
            if pinInput.count >= 6 { pinInput.removeLast() }
            pinInput.append(digit)
        } else if pinSetupPhase == .proveRead, digit == "6" {
            confirmPINWarningRead()
        }
    }

    private func customPathOrImportAppend(_ value: String) {
        importSeedText.append(contentsOf: value.lowercased())
    }

    func deleteCharacter() {
        switch screen {
        case .unlock:
            applyUnlockPINDelete()
        case .pinSetup:
            applyPINSetupDelete()
        case .importSeed: if !importSeedText.isEmpty { importSeedText.removeLast() }
        case .wordEntry: deleteWordEntryCharacter()
        case .passphrase, .listedFileRename:
            if screen == .listedFileRename { errorMessage = nil }
            if !passphraseInput.isEmpty { passphraseInput.removeLast() }
        case .diceRoll: if !diceRolls.isEmpty { diceRolls.removeLast() }
        case .entropyCollect:
            if entropyKind == .coin, !coinFlips.isEmpty { coinFlips.removeLast() }
            else if entropyKind == .diceMix, !diceRolls.isEmpty { diceRolls.removeLast() }
        case .calculator: if !calculatorExpression.isEmpty { calculatorExpression.removeLast() }
        case .serialREPL: if !serialREPLInput.isEmpty { serialREPLInput.removeLast() }
        case .messageSigning: if !messageText.isEmpty { messageText.removeLast() }
        case .accountNumber: if !accountPromptValue.isEmpty { accountPromptValue.removeLast() }
        case .typePasswordIndex:
            if !typePasswordIndexText.isEmpty { typePasswordIndexText.removeLast() }
        case .verifyBackup:
            if !backupPassword.isEmpty { backupPassword.removeLast() }
        case .hexEntry:
            if !hexEntryText.isEmpty { hexEntryText.removeLast() }
        default: break
        }
    }

    func applyEphemeralSeed(offerVault: Bool = true, summarizeUX: Bool = true) throws {
        guard record != nil else { throw SimulatorInputError.missingSeed }
        pendingEphemeralSummarizeUX = summarizeUX
        if offerVault, shouldOfferPendingEphemeralVault() {
            showStory(title: "", body: SeedVaultMenuCopy.offer, onConfirm: .skipVaultSave)
            return
        }
        try commitEphemeralFromPending(summarizeUX: summarizeUX)
    }

    private func continueAfterVaultOffer(saved: Bool) {
        _ = saved
        if pendingPassphraseAwaitingVault {
            finishPassphraseWallet()
            return
        }
        do {
            try commitEphemeralFromPending(summarizeUX: pendingEphemeralSummarizeUX)
        } catch { present(error) }
    }

    private func commitEphemeralFromPending(summarizeUX: Bool) throws {
        beginWorking(.applying, progress: 0)
        guard record != nil else {
            endWorking()
            throw SimulatorInputError.missingSeed
        }
        if let mnemonic = pendingMnemonic {
            ephemeralPhrase = mnemonic.phrase
            ephemeralXPRV = nil
            activeMnemonic = mnemonic
        } else if let xprv = pendingExtendedKey {
            do {
                _ = try Self.hdKey(fromExtendedPrivate: xprv, network: network)
            } catch {
                endWorking()
                throw error
            }
            ephemeralXPRV = xprv
            ephemeralPhrase = nil
            activeMnemonic = nil
            pendingExtendedKey = nil
        } else {
            endWorking()
            throw SimulatorInputError.missingSeed
        }
        activePassphrase = ""
        passphraseInput = ""
        pendingMnemonic = nil
        pendingEphemeral = false
        pendingNotes = []
        pendingPassphraseAwaitingVault = false
        do { try rebuildRoot() } catch {
            endWorking()
            throw error
        }
        history.removeAll()
        menuStack.removeAll()
        openMenu(.home, remember: false)
        endWorking()
        if summarizeUX {
            let xfp = rootKey?.fingerprintHex ?? "--------"
            showStory(
                title: SeedVaultMenuCopy.ephemeralAppliedTitle(xfp: xfp),
                body: SeedVaultMenuCopy.ephemeralAppliedStory()
            )
        }
    }

    private func shouldOfferPendingEphemeralVault() -> Bool {
        guard let newXFP = pendingEphemeralXFP() else { return false }
        return SeedVaultMenuCopy.shouldOfferVault(
            enabled: preferences.seedVaultEnabled,
            secretBlank: !(record?.hasSeed ?? false),
            deltaMode: deltaModeActive,
            hobbled: hobbledMode.isHobbled,
            alreadyVaulted: pendingSecretIsVaulted(),
            newXFP: newXFP,
            masterXFP: masterXFPHex()
        )
    }

    private func shouldOfferVaultForCurrentSecret() -> Bool {
        guard let xfp = rootKey?.fingerprintHex else { return false }
        return SeedVaultMenuCopy.shouldOfferVault(
            enabled: preferences.seedVaultEnabled,
            secretBlank: !(record?.hasSeed ?? false),
            deltaMode: deltaModeActive,
            hobbled: hobbledMode.isHobbled,
            alreadyVaulted: currentSecretIsVaulted(),
            newXFP: xfp,
            masterXFP: masterXFPHex()
        )
    }

    private func pendingEphemeralXFP() -> String? {
        if let mnemonic = pendingMnemonic, let key = try? HDKey(seed: mnemonic.seed(), network: network) {
            return key.fingerprintHex
        }
        if let xprv = pendingExtendedKey,
           let key = try? Self.hdKey(fromExtendedPrivate: xprv, network: network) {
            return key.fingerprintHex
        }
        return nil
    }

    private func masterXFPHex() -> String {
        if let stored = record?.settingsXFP, !stored.isEmpty {
            return SeedVaultMenuCopy.normalizedXFP(stored)
        }
        if let phrase = record?.mnemonic,
           let mnemonic = try? BIP39Mnemonic(phrase: phrase),
           let key = try? HDKey(seed: mnemonic.seed(), network: network) {
            return key.fingerprintHex
        }
        if let xprv = record?.extendedPrivateKey,
           let key = try? Self.hdKey(fromExtendedPrivate: xprv, network: network) {
            return key.fingerprintHex
        }
        return ""
    }

    private func pendingSecretIsVaulted() -> Bool {
        if let phrase = pendingMnemonic?.phrase,
           preferences.vaultedSeeds.contains(where: { $0.mnemonic == phrase }) {
            return true
        }
        if let xprv = pendingExtendedKey,
           preferences.vaultedSeeds.contains(where: { $0.extendedPrivateKey == xprv }) {
            return true
        }
        if let xfp = pendingEphemeralXFP() {
            let normalized = SeedVaultMenuCopy.normalizedXFP(xfp)
            return preferences.vaultedSeeds.contains {
                SeedVaultMenuCopy.normalizedXFP($0.fingerprint) == normalized
            }
        }
        return false
    }

    private func currentSecretIsVaulted() -> Bool {
        if let phrase = ephemeralPhrase,
           preferences.vaultedSeeds.contains(where: { $0.mnemonic == phrase }) {
            return true
        }
        if let xprv = ephemeralXPRV,
           preferences.vaultedSeeds.contains(where: { $0.extendedPrivateKey == xprv }) {
            return true
        }
        if let xfp = rootKey?.fingerprintHex {
            let normalized = SeedVaultMenuCopy.normalizedXFP(xfp)
            return preferences.vaultedSeeds.contains {
                SeedVaultMenuCopy.normalizedXFP($0.fingerprint) == normalized
            }
        }
        return false
    }

    private func savePendingOrCurrentToVault() {
        if pendingPassphraseAwaitingVault {
            savePassphraseWalletToVault()
            return
        }
        if let mnemonic = pendingMnemonic {
            let xfp = pendingEphemeralXFP() ?? fingerprint
            if preferences.vaultedSeeds.contains(where: { $0.mnemonic == mnemonic.phrase }) { return }
            let entry = VaultedSeed(
                fingerprint: xfp,
                mnemonic: mnemonic.phrase,
                label: "[\(SeedVaultMenuCopy.normalizedXFP(xfp))]",
                origin: ephemeralOrigin
            )
            preferences.vaultedSeeds.append(entry)
            persistPreferencesQuietly()
            return
        }
        if let xprv = pendingExtendedKey {
            let xfp = pendingEphemeralXFP() ?? fingerprint
            if preferences.vaultedSeeds.contains(where: { $0.extendedPrivateKey == xprv }) { return }
            let entry = VaultedSeed(
                fingerprint: xfp,
                mnemonic: "",
                label: "[\(SeedVaultMenuCopy.normalizedXFP(xfp))]",
                origin: ephemeralOrigin,
                extendedPrivateKey: xprv
            )
            preferences.vaultedSeeds.append(entry)
            persistPreferencesQuietly()
            return
        }
        saveCurrentEphemeralToVault()
    }

    private func savePassphraseWalletToVault() {
        guard let root = rootKey, let xprv = try? root.serializePrivate() else { return }
        if preferences.vaultedSeeds.contains(where: { $0.extendedPrivateKey == xprv }) { return }
        let xfp = root.fingerprintHex
        let entry = VaultedSeed(
            fingerprint: xfp,
            mnemonic: "",
            label: "[\(xfp)]",
            origin: ephemeralOrigin,
            extendedPrivateKey: xprv
        )
        preferences.vaultedSeeds.append(entry)
        persistPreferencesQuietly()
    }

    private func abortWithFirmwarePause() {
        story.onConfirm = nil
        if screen == .story, let previous = history.popLast() {
            screen = previous
        }
        Task { @MainActor in
            await dramaticPause(SeedDanger.abortedPause, seconds: 2)
        }
    }

    private func exportCleartextBackup() {
        let what = pendingNotesFileExport ? BackupFile.notesAndPasswords : BackupFile.moneyForFree
        showStory(title: "", body: BackupFile.cleartextConfirm(what: what),
                  onConfirm: .exportCleartext)
    }

    private func writeCleartextBackup() {
        do {
            let text = try currentBackupText()
            presentWrittenBackup(data: Data(text.utf8), filename: BackupFile.cleartextFilename,
                                 type: .plainText, allowCopies: true)
        } catch { present(error) }
    }

    private func presentWrittenBackup(data: Data, filename: String, type: UTType, allowCopies: Bool) {
        pendingBackupExportData = data
        pendingBackupExportFilename = filename
        pendingBackupExportType = type
        backupAllowCopies = allowCopies
        backupCopyIndex = 0
        prepareExport(data: data, filename: filename, type: type)
    }

    private func showBackupCopyStory() {
        let filename = pendingBackupExportFilename
        if backupCopyIndex == 0 {
            showStory(title: "", body: BackupFile.firstCopyWritten(filename),
                      onConfirm: .backupFirstCopyWritten)
        } else {
            showStory(title: "", body: BackupFile.subsequentCopyWritten(copyNumber: backupCopyIndex + 1,
                                                                       filename: filename),
                      onConfirm: .backupMoreCopies)
        }
    }

    private func exportAnotherBackupCopy() {
        guard backupAllowCopies, backupCopyIndex + 1 < BackupFile.maxCopies,
              let data = pendingBackupExportData else {
            clearPendingBackupExport()
            if screen == .story { back() }
            return
        }
        backupCopyIndex += 1
        if screen == .story { back() }
        prepareExport(data: data, filename: pendingBackupExportFilename, type: pendingBackupExportType)
    }

    private func clearPendingBackupExport() {
        pendingBackupExportData = nil
        backupCopyIndex = 0
        backupAllowCopies = true
    }

    func beginCustomBackupPasswordEntry() {
        textEntryIsCustomBackupPassword = true
        passphraseInput = ""
        navigate(to: .passphrase)
    }

    func commitCustomBackupPassword() {
        let password = passphraseInput
        guard password.count >= DeveloperDebug.bkpwMinLength else { return }
        backupPassword = password
        backupPasswordWords = []
        textEntryIsCustomBackupPassword = false
        passphraseInput = ""
        if pendingEncryptedNotesData != nil {
            decryptAndImportNotes()
        } else {
            decryptPendingRestore()
        }
    }

    func currentBackupText() throws -> String {
        guard let record else { throw SimulatorInputError.missingSeed }
        let network = rootKey?.network ?? record.network
        let phrase = ephemeralPhrase ?? (record.mnemonic.isEmpty ? nil : record.mnemonic)
        var mnemonic: String?
        let raw: Data
        if let phrase, let words = try? BIP39Mnemonic(phrase: phrase) {
            mnemonic = words.phrase
            raw = SecretStash.encode(entropy: words.entropy)
        } else if let xprv = ephemeralXPRV ?? record.extendedPrivateKey {
            let key = try Self.hdKey(fromExtendedPrivate: xprv, network: network)
            guard let privateKey = key.privateKey else { throw SimulatorInputError.missingSeed }
            raw = SecretStash.encode(chainCode: key.chainCode, privateKey: privateKey)
        } else {
            throw SimulatorInputError.missingSeed
        }
        let root: HDKey
        if let existing = rootKey {
            root = existing
        } else if let mnemonic, let words = try? BIP39Mnemonic(phrase: mnemonic) {
            root = try HDKey(seed: words.seed(), network: network)
        } else {
            throw SimulatorInputError.missingSeed
        }
        return try BackupFile.render(
            mnemonic: mnemonic,
            chain: network.ticker,
            chainName: network.displayName,
            xprv: try root.serializePrivate(),
            xpub: try root.neutered().serializePublic(),
            rawSecretHex: raw.hexString,
            settings: firmwareBackupSettings(record)
        )
    }

    private func firmwareBackupSettings(_ record: StoredWalletRecord) -> [(key: String, value: Any)] {
        var prefs = record.preferences
        prefs.sd2faNonces = []
        var rows: [(key: String, value: Any)] = []
        if prefs.secnapEnabled { rows.append((key: "secnap", value: true)) }
        rows.append((key: "rz", value: prefs.displayUnits.btcDecimalPlaces))
        rows.append((key: "fee_limit", value: prefs.maxNetworkFee.rawValue))
        if prefs.deletePSBTs { rows.append((key: "del", value: 1)) }
        if prefs.menuWrapping { rows.append((key: "wa", value: true)) }
        if prefs.aeStartIndexEnabled { rows.append((key: "aei", value: true)) }
        if prefs.alwaysShowHomeXFP { rows.append((key: "hmx", value: true)) }
        if prefs.skipAddressExplorerIntro { rows.append((key: "axskip", value: true)) }
        if prefs.skipPassphraseIntro { rows.append((key: "b39skip", value: true)) }
        if prefs.sighashWarnOnly { rows.append((key: "sighshchk", value: true)) }
        if prefs.seedVaultEnabled { rows.append((key: "seedvault", value: 1)) }
        if !prefs.vaultedSeeds.isEmpty {
            let seeds: [[String]] = prefs.vaultedSeeds.map { seed in
                let encoded: String
                if let xprv = seed.extendedPrivateKey,
                   let key = try? Self.hdKey(fromExtendedPrivate: xprv, network: record.network),
                   let priv = key.privateKey {
                    encoded = SecretStash.encode(chainCode: key.chainCode, privateKey: priv).hexString
                } else if let mnemonic = try? BIP39Mnemonic(phrase: seed.mnemonic) {
                    encoded = SecretStash.encode(entropy: mnemonic.entropy).hexString
                } else {
                    encoded = ""
                }
                return [seed.fingerprint, encoded, seed.label, seed.origin]
            }
            rows.append((key: "seeds", value: seeds))
        }
        if prefs.scrambleKeys { rows.append((key: "rngk", value: true)) }
        if !prefs.killKey.isEmpty { rows.append((key: "kbtn", value: prefs.killKey)) }
        if prefs.loginCountdownMinutes != 0 { rows.append((key: "lgto", value: prefs.loginCountdownMinutes)) }
        if prefs.b85Unlimited { rows.append((key: "b85max", value: true)) }
        rows.append((key: "idle_to", value: prefs.idleTimeoutSeconds))
        rows.append((key: "batt_to", value: prefs.idleTimeoutBatterySeconds))
        if prefs.nfcSharingEnabled { rows.append((key: "nfc", value: true)) }
        if let url = prefs.ptxurl { rows.append((key: "ptxurl", value: url)) }
        if !prefs.importedMultisigWallets.isEmpty {
            rows.append((key: "multisig", value: prefs.importedMultisigWallets.map { $0.firmwareStorageObject() }))
        }
        if prefs.fullMultisigAddressView { rows.append((key: "msas", value: true)) }
        if prefs.allowUnsortedMultisig { rows.append((key: "unsort_ms", value: true)) }
        if let pms = prefs.psbtMultisigTrust { rows.append((key: "pms", value: pms)) }
        if let du = prefs.du { rows.append((key: "du", value: du)) }
        if prefs.virtualDiskMode != 0 { rows.append((key: "vidsk", value: prefs.virtualDiskMode)) }
        if prefs.keyboardEmuEnabled { rows.append((key: "emu", value: true)) }
        if prefs.tested { rows.append((key: "tested", value: true)) }
        if !record.nickname.isEmpty { rows.append((key: "nick", value: record.nickname)) }
        if !record.notes.isEmpty {
            rows.append((key: "notes", value: record.notes.map { $0.firmwareRecord() }))
        }
        if !record.wifKeys.isEmpty {
            rows.append((key: "wifs", value: record.wifKeys.map { [$0.publicKeyHex, $0.privateKeyHex] }))
        }
        if !record.trickPins.isEmpty {
            var table: [String: [Int]] = [:]
            for slot in record.trickPins where !slot.hidden {
                table[slot.pin] = [slot.slotNum, Int(slot.flags.rawValue), Int(slot.arg)]
            }
            if !table.isEmpty { rows.append((key: "tp", value: table)) }
        }
        return rows
    }

    static func payloadFromClearBytes(_ data: Data) throws -> WalletBackupPayload {
        if let payload = try? JSONDecoder().decode(WalletBackupPayload.self, from: data),
           payload.format == "coldcard-q-swift-simulator-backup/1" {
            return payload
        }
        return try payloadFromBackupText(data)
    }

    private static func payloadFromBackupText(_ data: Data) throws -> WalletBackupPayload {
        guard let text = String(data: data, encoding: .utf8) else {
            throw BackupFileError.malformed
        }
        let values = BackupFile.parse(text)
        guard !values.isEmpty else { throw BackupFileError.malformed }
        let chain = BackupFile.stringValue(values, "chain") ?? "XTN"
        let network = BackupFile.network(fromChain: chain)
        var mnemonic = BackupFile.stringValue(values, "mnemonic") ?? ""
        var xprv = BackupFile.stringValue(values, "xprv")
        if let rawHex = BackupFile.stringValue(values, "raw_secret") {
            do {
                let raw = try BackupFile.deserializeSecret(rawHex)
                switch try SecretStash.decode(raw) {
                case .words(let entropy):
                    if mnemonic.isEmpty {
                        mnemonic = try BIP39Mnemonic(entropy: entropy).phrase
                    }
                case .xprv(let chainCode, let privateKey):
                    if xprv == nil || xprv?.isEmpty == true {
                        xprv = try HDKey.master(privateKey: privateKey, chainCode: chainCode,
                                                network: network).serializePrivate()
                    }
                case .masterSecret:
                    break
                }
            } catch {
                throw SimulatorInputError.missingSeed
            }
        } else if mnemonic.isEmpty, (xprv ?? "").isEmpty {
            throw BackupFileError.missingRawSecret
        }
        var prefs = SimulatorPreferences()
        var notes: [SecureNote] = []
        var wifKeys: [WIFStoreItem] = []
        var trickPins: [TrickPinSlot] = []
        let settings = BackupFile.settingValues(values)
        applyFirmwareSettings(settings, network: network, preferences: &prefs,
                              notes: &notes, wifKeys: &wifKeys, trickPins: &trickPins)
        let nickname = BackupFile.stringValue(settings, "nick") ?? ""
        return WalletBackupPayload(
            mnemonic: mnemonic,
            network: network,
            nickname: nickname,
            notes: notes,
            createdAt: Date(),
            preferences: prefs,
            wifKeys: wifKeys,
            trickPins: trickPins,
            extendedPrivateKey: mnemonic.isEmpty ? xprv : nil
        )
    }

    private static func applyFirmwareSettings(
        _ settings: [String: Any],
        network: BitcoinNetwork,
        preferences: inout SimulatorPreferences,
        notes: inout [SecureNote],
        wifKeys: inout [WIFStoreItem],
        trickPins: inout [TrickPinSlot]
    ) {
        if BackupFile.jsonBool(settings["secnap"]) { preferences.secnapEnabled = true }
        if let rz = BackupFile.jsonInt(settings["rz"]) {
            preferences.displayUnits = DisplayUnits.allCases.first { $0.btcDecimalPlaces == rz } ?? .btc
        }
        if let fee = BackupFile.jsonInt(settings["fee_limit"]),
           let matched = MaxNetworkFee(rawValue: fee) {
            preferences.maxNetworkFee = matched
        }
        if BackupFile.jsonBool(settings["del"]) { preferences.deletePSBTs = true }
        if BackupFile.jsonBool(settings["wa"]) { preferences.menuWrapping = true }
        if BackupFile.jsonBool(settings["aei"]) { preferences.aeStartIndexEnabled = true }
        if BackupFile.jsonBool(settings["hmx"]) { preferences.alwaysShowHomeXFP = true }
        if BackupFile.jsonBool(settings["axskip"]) { preferences.skipAddressExplorerIntro = true }
        if BackupFile.jsonBool(settings["b39skip"]) { preferences.skipPassphraseIntro = true }
        if BackupFile.jsonBool(settings["sighshchk"]) { preferences.sighashWarnOnly = true }
        if BackupFile.jsonBool(settings["seedvault"]) { preferences.seedVaultEnabled = true }
        if BackupFile.jsonBool(settings["rngk"]) { preferences.scrambleKeys = true }
        if let kbtn = settings["kbtn"] as? String { preferences.killKey = kbtn }
        if let lgto = BackupFile.jsonInt(settings["lgto"]) { preferences.loginCountdownMinutes = lgto }
        if BackupFile.jsonBool(settings["b85max"]) { preferences.b85Unlimited = true }
        if let idle = BackupFile.jsonInt(settings["idle_to"]) { preferences.idleTimeoutSeconds = idle }
        if let batt = BackupFile.jsonInt(settings["batt_to"]) { preferences.idleTimeoutBatterySeconds = batt }
        if BackupFile.jsonBool(settings["nfc"]) { preferences.nfcSharingEnabled = true }
        if let url = settings["ptxurl"] as? String { preferences.ptxurl = url }
        if BackupFile.jsonBool(settings["msas"]) { preferences.fullMultisigAddressView = true }
        if BackupFile.jsonBool(settings["unsort_ms"]) { preferences.allowUnsortedMultisig = true }
        if let pms = BackupFile.jsonInt(settings["pms"]) { preferences.psbtMultisigTrust = pms }
        if let du = BackupFile.jsonInt(settings["du"]) { preferences.du = du }
        if let vidsk = BackupFile.jsonInt(settings["vidsk"]) { preferences.virtualDiskMode = min(max(vidsk, 0), 2) }
        if BackupFile.jsonBool(settings["emu"]) { preferences.keyboardEmuEnabled = true }
        if BackupFile.jsonBool(settings["tested"]) { preferences.tested = true }
        if let rows = settings["notes"] as? [[String: Any]] {
            notes = rows.map { row in
                var mapped: [String: String] = [:]
                for (key, value) in row { mapped[key] = value as? String ?? "" }
                return SecureNote.fromFirmwareRecord(mapped)
            }
        }
        if let seeds = settings["seeds"] as? [[Any]] {
            preferences.vaultedSeeds = seeds.compactMap { row in
                guard row.count >= 4,
                      let xfp = row[0] as? String,
                      let encoded = row[1] as? String,
                      let label = row[2] as? String,
                      let origin = row[3] as? String,
                      let raw = try? BackupFile.deserializeSecret(encoded),
                      let kind = try? SecretStash.decode(raw) else { return nil }
                switch kind {
                case .words(let entropy):
                    guard let mnemonic = try? BIP39Mnemonic(entropy: entropy) else { return nil }
                    return VaultedSeed(fingerprint: xfp, mnemonic: mnemonic.phrase, label: label, origin: origin)
                case .xprv(let chainCode, let privateKey):
                    let xprv = try? HDKey.master(privateKey: privateKey, chainCode: chainCode,
                                                 network: network).serializePrivate()
                    return VaultedSeed(fingerprint: xfp, mnemonic: "", label: label, origin: origin,
                                       extendedPrivateKey: xprv)
                case .masterSecret:
                    return nil
                }
            }
        }
        if let wallets = settings["multisig"] as? [Any] {
            preferences.importedMultisigWallets = wallets.compactMap { try? MultisigWalletConfig.fromFirmwareStorage($0) }
        }
        if let wifs = settings["wifs"] as? [[Any]] {
            wifKeys = wifs.compactMap { row in
                guard row.count >= 2,
                      let pub = row[0] as? String,
                      let priv = row[1] as? String else { return nil }
                return WIFStoreItem(publicKeyHex: pub, privateKeyHex: priv)
            }
        }
        if let table = settings["tp"] as? [String: Any] {
            trickPins = table.compactMap { pin, raw in
                let parts = raw as? [Any] ?? []
                guard parts.count >= 3,
                      let slot = BackupFile.jsonInt(parts[0]),
                      let flags = BackupFile.jsonInt(parts[1]),
                      let arg = BackupFile.jsonInt(parts[2]) else { return nil }
                return TrickPinSlot(pin: pin, flags: TrickPinFlags(rawValue: UInt16(truncatingIfNeeded: flags)),
                                    arg: UInt16(truncatingIfNeeded: arg), slotNum: slot)
            }
        }
    }

    private func commitPINOnly(pin: String) throws {
        guard isValidPIN(pin) else { throw SimulatorInputError.invalidPIN }
        let salt = try SecureRandom.bytes(count: 16)
        let record = StoredWalletRecord(mnemonic: "", network: settingsNetwork,
                                        nickname: settingsNickname,
                                        pinSalt: salt, pinHash: SHA2.sha256(salt + Data(pin.utf8)),
                                        notes: [], createdAt: Date(), preferences: preferences)
        self.record = record
        try persistRecord()
        failedPINAttempts = 0
        history.removeAll()
        menuStack.removeAll()
        openMenu(.emptyWallet, remember: false)
    }

    private func commitPendingWallet(pin: String) throws {
        guard let mnemonic = pendingMnemonic else { throw SimulatorInputError.missingSeed }
        guard isValidPIN(pin) else { throw SimulatorInputError.invalidPIN }
        let salt = try SecureRandom.bytes(count: 16)
        let record = StoredWalletRecord(mnemonic: mnemonic.phrase, network: settingsNetwork,
                                        nickname: settingsNickname,
                                        pinSalt: salt, pinHash: SHA2.sha256(salt + Data(pin.utf8)),
                                        notes: pendingNotes, createdAt: Date(), preferences: preferences,
                                        extendedPrivateKey: nil, wifKeys: pendingWIFKeys ?? [])
        pendingWIFKeys = nil
        self.record = record
        activeMnemonic = mnemonic
        activePassphrase = ""
        passphraseInput = ""
        try persistRecord()
        try rebuildRoot()
        pendingMnemonic = nil
        pendingNotes = []
        failedPINAttempts = 0
        history.removeAll()
        menuStack.removeAll()
        openMenu(.home, remember: false)
    }

    private func commitPendingXPRV(pin: String) throws {
        guard let xprv = pendingExtendedKey else { throw SimulatorInputError.missingSeed }
        _ = try Self.hdKey(fromExtendedPrivate: xprv, network: settingsNetwork)
        guard isValidPIN(pin) else { throw SimulatorInputError.invalidPIN }
        let salt = try SecureRandom.bytes(count: 16)
        let record = StoredWalletRecord(mnemonic: "", network: settingsNetwork,
                                        nickname: settingsNickname,
                                        pinSalt: salt, pinHash: SHA2.sha256(salt + Data(pin.utf8)),
                                        notes: pendingNotes, createdAt: Date(), preferences: preferences,
                                        extendedPrivateKey: xprv, wifKeys: pendingWIFKeys ?? [])
        pendingWIFKeys = nil
        self.record = record
        pendingExtendedKey = nil
        activeMnemonic = nil
        activePassphrase = ""
        passphraseInput = ""
        try persistRecord()
        try rebuildRoot()
        pendingNotes = []
        failedPINAttempts = 0
        history.removeAll()
        menuStack.removeAll()
        openMenu(.home, remember: false)
    }

    func commitSeedOntoExistingPIN() throws {
        beginWorking(.applying, progress: 0)
        if let xprv = pendingExtendedKey {
            guard var record else {
                endWorking()
                throw SimulatorInputError.missingSeed
            }
            do {
                _ = try Self.hdKey(fromExtendedPrivate: xprv, network: settingsNetwork)
            } catch {
                endWorking()
                throw error
            }
            record.mnemonic = ""
            record.extendedPrivateKey = xprv
            record.notes = pendingNotes
            record.network = settingsNetwork
            record.nickname = settingsNickname.isEmpty ? record.nickname : settingsNickname
            self.record = record
            pendingExtendedKey = nil
            activeMnemonic = nil
            do {
                try persistRecord()
                try rebuildRoot()
            } catch {
                endWorking()
                throw error
            }
            pendingNotes = []
            history.removeAll()
            menuStack.removeAll()
            openMenu(.home, remember: false)
            endWorking()
            presentFirstTimeUXIfNeeded()
            return
        }
        guard var record, let mnemonic = pendingMnemonic else {
            endWorking()
            throw SimulatorInputError.missingSeed
        }
        record.mnemonic = mnemonic.phrase
        record.extendedPrivateKey = nil
        record.notes = pendingNotes
        applyPendingWIFKeys(to: &record)
        record.network = settingsNetwork
        record.nickname = settingsNickname.isEmpty ? record.nickname : settingsNickname
        self.record = record
        activeMnemonic = mnemonic
        do {
            try persistRecord()
            try rebuildRoot()
        } catch {
            endWorking()
            throw error
        }
        pendingMnemonic = nil
        pendingNotes = []
        history.removeAll()
        menuStack.removeAll()
        openMenu(.home, remember: false)
        endWorking()
        presentFirstTimeUXIfNeeded()
    }

    private func updatePIN(_ pin: String) throws {
        guard var record else { throw SimulatorInputError.invalidPIN }
        let salt = try SecureRandom.bytes(count: 16)
        record.pinSalt = salt
        record.pinHash = SHA2.sha256(salt + Data(pin.utf8))
        self.record = record
        try persistRecord()
    }

    func rebuildRoot() throws {
        guard let record else { throw SimulatorInputError.missingSeed }
        if let xprv = ephemeralXPRV {
            rootKey = try Self.hdKey(fromExtendedPrivate: xprv, network: record.network)
            activeMnemonic = nil
        } else if let active = activeMnemonic {
            rootKey = try HDKey(seed: active.seed(passphrase: activePassphrase), network: record.network)
        } else if let phrase = ephemeralPhrase {
            let mnemonic = try BIP39Mnemonic(phrase: phrase)
            activeMnemonic = mnemonic
            rootKey = try HDKey(seed: mnemonic.seed(passphrase: activePassphrase), network: record.network)
        } else if let xprv = record.extendedPrivateKey, !xprv.isEmpty {
            rootKey = try Self.hdKey(fromExtendedPrivate: xprv, network: record.network)
            activeMnemonic = nil
        } else if !record.mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let mnemonic = try BIP39Mnemonic(phrase: record.mnemonic)
            activeMnemonic = mnemonic
            rootKey = try HDKey(seed: mnemonic.seed(passphrase: activePassphrase), network: record.network)
        } else {
            throw SimulatorInputError.missingSeed
        }
        derivedAddresses = []
        currentPSBT = nil
        psbtReview = nil
        signedPSBTData = nil
        rememberMasterXFP()
    }

    func persistRecord() throws {
        guard var record else { return }
        record.preferences = preferences
        record.failedPINAttempts = failedPINAttempts
        record.isBricked = isBricked
        self.record = record
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try KeychainStore.save(encoder.encode(record))
    }

    func commitWalletRecord(_ record: StoredWalletRecord) {
        self.record = record
        try? persistRecord()
    }

    func presentBBQr(title: String, data: Data, fileType: BBQrFileType, sensitive: Bool = false) {
        do {
            let parts = try BBQr.encode(data, fileType: fileType)
            qrPresentation = QRPresentation(title: title, payloads: parts, sensitive: sensitive)
        } catch { present(error) }
    }

    func prepareExport(data: Data, filename: String, type: UTType,
                               successStory: (title: String, body: String)? = nil) {
        exportDocument = DataDocument(data: data)
        exportFilename = filename
        exportContentType = type
        pendingExportSuccessStory = successStory
        showFileExporter = true
    }

    /// Called from the app's `fileExporter` completion so firmware "file written" stories can follow.
    func noteExportCompleted(success: Bool) {
        if success, let sig = pendingDetachedSig {
            pendingDetachedSig = nil
            let story = pendingExportSuccessStory
            prepareExport(data: sig.0, filename: sig.1, type: .plainText, successStory: story)
            return
        }
        guard let story = pendingExportSuccessStory else {
            if pendingCloneIngestAfterExport {
                pendingCloneIngestAfterExport = false
                showStory(title: "", body: FirmwareCopy.cloneKeepPower, onConfirm: .cloneIngestPickFile)
                return
            }
            if success, pendingBackupExportData != nil, backupAllowCopies {
                showBackupCopyStory()
                return
            }
            if !success { clearPendingBackupExport() }
            return
        }
        pendingExportSuccessStory = nil
        if pendingCloneIngestAfterExport {
            pendingCloneIngestAfterExport = false
            showStory(title: "", body: FirmwareCopy.cloneKeepPower, onConfirm: .cloneIngestPickFile)
            return
        }
        if success {
            if screen == .story, self.story.onConfirm == .signedMessageExport {
                self.story = StoryPresentation(title: story.title, body: story.body)
                storyTop = 0
            } else {
                showStory(title: story.title, body: story.body)
            }
        }
    }

    /// Firmware `write_sig_file` over SHA256(file) + filename, using the export's derive / addr_fmt.
    func queueDetachedSignature(for data: Data, filename: String,
                                derive: String? = nil, addressType: AddressType = .legacy) {
        guard let root = rootKey else { return }
        let message = BitcoinMessageSigner.fileHashMessage(hashesAndNames: [(SHA2.sha256(data), filename)])
        let pathText = derive ?? "m/44h/\(root.network.coinType)h/0h/0/0"
        guard let path = try? DerivationPath(pathText),
              let signed = try? BitcoinMessageSigner.sign(message, root: root, path: path, type: addressType) else { return }
        pendingDetachedSig = (Data(signed.armored.utf8), BitcoinMessageSigner.signatureFilename(forInputFilename: filename))
    }

    func handleSceneBecameActive() {
        SimulatorCardStandin.ensureDirectories()
        applyFactoryStandInFromDefaults()
        refreshFactoryRootIfNeeded()
        if isUnlocked, preferences.virtualDiskMode == 2 {
            virtDiskMonitor.scanNow()
        }
    }

    /// Write a file onto a card stand-in and keep Enable & Auto from re-opening it.
    func writeCardStandin(_ data: Data, named filename: String, to volume: SimulatorCardStandin.Volume) throws -> URL {
        let url = try SimulatorCardStandin.write(data, named: filename, to: volume)
        if volume == .virtDisk { virtDiskMonitor.noteWritten(filename: filename) }
        return url
    }

    func syncVirtualDiskMonitor() {
        SimulatorCardStandin.ensureDirectories()
        if isUnlocked, preferences.virtualDiskMode == 2 {
            virtDiskMonitor.start()
        } else {
            virtDiskMonitor.stop()
        }
    }

    private func stopVirtualDiskMonitor() {
        virtDiskMonitor.stop()
    }

    private func handleAutoVirtualDiskPSBT(_ url: URL) {
        guard isUnlocked, rootKey != nil, preferences.virtualDiskMode == 2, !isWorking else { return }
        importPurpose = .psbt
        handleImportedFile(url)
    }

    private func presentListedFiles() {
        listedFilesAreNFCShare = false
        listedDiskFiles = SimulatorCardStandin.listFilesForPicker(vdiskEnabled: virtualDiskEnabled)
        guard !listedDiskFiles.isEmpty else {
            showStory(title: "", body: FirmwareCopy.noSuitableFiles)
            return
        }
        openMenu(.listedFiles)
    }

    private func inspectListedFile(id: String) {
        selectedListedFile = listedDiskFiles.first { $0.id == id }
        if pickingPushTxn, let file = selectedListedFile {
            pushTransaction(fromFile: file)
            return
        }
        if listedFilesAreNFCShare {
            shareListedFileViaNFC(id: id)
            return
        }
        if listedFilesAreNotesImport {
            guard let file = selectedListedFile, let data = try? Data(contentsOf: file.url) else { return }
            listedFilesAreNotesImport = false
            importNotes(data: data, filename: file.filename)
            return
        }
        presentListedFileDetail()
        if screen != .story { navigate(to: .story) }
    }

    private func presentListedFileDetail() {
        guard let file = selectedListedFile else { return }
        let data = (try? Data(contentsOf: file.url)) ?? Data()
        let digest = SHA2.sha256(data).hexString
        var body = "SHA256(\(file.filename))\n\n\(digest)\n\nPress (1) to rename file, "
        if hasSeed || tmpSeedActive {
            body += "(4) to sign file digest and export detached signature, "
        }
        body += "(6) to delete."
        story = StoryPresentation(title: "", body: body, onConfirm: .listedFileDetail)
    }

    private func beginListedFileRename() {
        guard let file = selectedListedFile else { return }
        passphraseInput = file.filename
        navigate(to: .listedFileRename)
    }

    private func signListedFileDigest() {
        guard hasSeed || tmpSeedActive, let file = selectedListedFile, let root = rootKey else { return }
        let data = (try? Data(contentsOf: file.url)) ?? Data()
        let message = BitcoinMessageSigner.fileHashMessage(hashesAndNames: [(SHA2.sha256(data), file.filename)])
        let coin = root.network.coinType
        guard let path = try? DerivationPath("m/44h/\(coin)h/0h/0/0"),
              let signed = try? BitcoinMessageSigner.sign(message, root: root, path: path, type: .legacy) else { return }
        let sigName = BitcoinMessageSigner.signatureFilename(forInputFilename: file.filename)
        do {
            _ = try writeCardStandin(Data(signed.armored.utf8), named: sigName, to: file.volume)
            showStory(title: "", body: "Signature file \(sigName) written.", onConfirm: .listedFileRestoreDetail)
        } catch {
            showStory(title: "Failure", body: error.localizedDescription, onConfirm: .listedFileRestoreDetail)
        }
    }

    private func deleteListedFile() {
        guard let file = selectedListedFile else { return }
        try? SimulatorCardStandin.securelyDelete(file)
        selectedListedFile = nil
        story.onConfirm = nil
        back()
    }

    private func performFormatVolume(_ volume: SimulatorCardStandin.Volume) {
        beginWorking(.formatting)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            do {
                try SimulatorCardStandin.wipe(volume)
                if volume == .virtDisk { virtDiskMonitor.resetAfterWipe() }
            } catch {
                endWorking()
                present(error)
                return
            }
            endWorking()
            back()
        }
    }

    func startIdleWatch() {
        noteUserActivity()
        Task { @MainActor in
            while isUnlocked {
                try? await Task.sleep(for: .seconds(5))
                if lockIfIdle() { return }
            }
        }
    }

    private func noteUserActivity() {
        lastUserActivity = Date()
    }

    private func lockIfIdle() -> Bool {
        guard isUnlocked else { return false }
        // iPhone ≈ Q on battery: `batt_idle_logout` uses `batt_to`, not USB `idle_to`.
        let seconds = preferences.idleTimeoutBatterySeconds
        guard seconds > 0 else { return false }
        if Date().timeIntervalSince(lastUserActivity) >= TimeInterval(seconds) {
            lock()
            statusMessage = "Idle timeout."
            return true
        }
        return false
    }

    private func refreshScrambleMap() {
        if preferences.scrambleKeys {
            var digits = Array("0123456789")
            digits.shuffle()
            scrambleDigitMap = Dictionary(uniqueKeysWithValues: zip(Array("0123456789"), digits))
        } else {
            scrambleDigitMap = [:]
        }
    }

    func scrambleHint() -> String {
        // Firmware remaps digits silently (`login.py`); never show the 0123456789 map.
        ""
    }

    func startLoginCountdown() {
        // Firmware `lgto` is minutes; display uses `pretty_delay` / `pretty_short_delay` on seconds.
        // Tick 60× faster so a 5-minute wait is ~5 seconds of wall clock.
        let minutes = loginCountdownOverrideMinutes ?? preferences.loginCountdownMinutes
        loginCountdownRemaining = max(1, minutes) * 60
        history.removeAll()
        menuStack.removeAll()
        screen = .loginCountdown
        Task { @MainActor in
            while loginCountdownRemaining > 0 {
                try? await Task.sleep(for: .milliseconds(1000 / 60))
                if screen != .loginCountdown { return }
                loginCountdownRemaining -= 1
            }
            if trickBrickAfterCountdown {
                enterBrickedState()
            } else {
                goToLockedRoot(showNickname: false)
            }
        }
    }

    func performKillWipe() {
        guard var record else { return }
        record.mnemonic = ""
        record.extendedPrivateKey = nil
        record.notes = []
        self.record = record
        try? persistRecord()
        activeMnemonic = nil
        ephemeralPhrase = nil
        ephemeralXPRV = nil
        pendingMnemonic = nil
        pendingExtendedKey = nil
        rootKey = nil
        pinInput = ""
        pinPrefix = ""
        unlockPhase = .prefix
        awaitingPostCountdownPIN = false
        goToLockedRoot()
        statusMessage = "Kill key: seed wiped."
    }

    func beginXORSplit() {
        if wipeIfDeltaMode() { return }
        guard wordBasedSeed else { return }
        showStory(title: "Seed XOR Split", body: SeedXORStories.splitIntro, onConfirm: .xorSplitParts)
    }

    func performXORSplit(useRNG: Bool) {
        guard let mnemonic = activeMnemonic ?? pendingMnemonic else { return }
        let entropy = mnemonic.entropy
        let partsCount = xorPendingPartCount
        let chk = mnemonic.words.last ?? ""
        Task { @MainActor in
            await dramaticPause(SeedXORStories.generatingPause, seconds: 2)
            do {
                let random: [Data]?
                if useRNG {
                    random = try (0..<(partsCount - 1)).map { _ in try SecureRandom.bytes(count: entropy.count) }
                } else {
                    random = nil
                }
                let parts = try SeedXOR.split(entropy, parts: partsCount, randomParts: random)
                xorEntropyParts = parts
                xorWordLists = try parts.map { try BIP39Mnemonic(entropy: $0).words }
                xorUsedRNG = useRNG
                xorChecksumWord = chk
                presentXORSplitParts(checksum: chk)
            } catch {
                present(error)
            }
        }
    }

    private func presentXORSplitParts(checksum: String) {
        xorChecksumWord = checksum
        let msg = SeedXORStories.recordParts(wordLists: xorWordLists, checksumWord: checksum)
        showStory(title: SeedXORStories.recordPartsTitle, body: msg, onConfirm: .xorShowParts, hintQR: true)
    }

    private func beginXORSplitQuiz() {
        xorQuizzingSplit = true
        xorQuizPartIndex = 0
        guard let first = xorWordLists.first else { return }
        startWordQuiz(words: first)
    }

    func beginXORRestore() {
        clearXORSession()
        xorForceTemporary = hasSeed || currentMenu == .temporarySeed
        showStory(title: "", body: SeedXORStories.restoreIntro(), onConfirm: .xorRestoreWordCount)
    }

    private func continueXORRestoreAfterWordCount() {
        if hasSeed {
            let currentCount = (activeMnemonic ?? pendingMnemonic)?.words.count
            xorCanIncludeCurrent = currentCount == xorDesiredWordCount && !hobbledMode.isHobbled
            showStory(
                title: "",
                body: SeedXORStories.restoreExistingSeed(canIncludeCurrent: xorCanIncludeCurrent),
                onConfirm: .xorRestoreInclude
            )
            return
        }
        xorCanIncludeCurrent = false
        continueXORRestoreAfterInclude(includeCurrent: false)
    }

    private func continueXORRestoreAfterInclude(includeCurrent: Bool) {
        if includeCurrent, xorCanIncludeCurrent, let mnemonic = activeMnemonic ?? pendingMnemonic {
            xorEntropyParts.append(mnemonic.entropy)
        }
        let matching = matchingXORVaultSeeds()
        if !matching.isEmpty, !hobbledMode.isHobbled {
            showStory(
                title: "",
                body: SeedXORStories.restoreVault(matchingCount: matching.count),
                onConfirm: .xorRestoreVault
            )
            return
        }
        continueXORRestoreAfterVault(addVault: false)
    }

    private func continueXORRestoreAfterVault(addVault: Bool) {
        if addVault {
            xorVaultCandidates = matchingXORVaultSeeds()
            xorVaultSelected = []
            openMenu(.xorVaultPick)
            return
        }
        if xorEntropyParts.count >= 2 {
            presentXORPartStatus()
            return
        }
        beginWordEntry(purpose: .xorPart, wordCount: xorDesiredWordCount)
    }

    func finishXORPart(words: [String]) {
        do {
            let mnemonic = try BIP39Mnemonic(phrase: words.joined(separator: " "))
            xorEntropyParts.append(mnemonic.entropy)
            presentXORPartStatus()
        } catch { present(error) }
    }

    private func presentXORPartStatus() {
        let count = xorEntropyParts.count
        var checksum: String?
        var zeroWarning = false
        if count >= 2 {
            let combined = SeedXOR.xor(xorEntropyParts)
            if let preview = try? BIP39Mnemonic(entropy: combined) {
                checksum = preview.words.last
                zeroWarning = combined.allSatisfy { $0 == 0 }
            }
        }
        let msg = SeedXORStories.restoreProgress(
            partsEntered: count,
            wordCount: xorDesiredWordCount,
            checksumWord: checksum,
            zeroWarning: zeroWarning
        )
        showStory(title: "", body: msg, onConfirm: .xorRestoreMore, hintQR: count >= 2)
    }

    private func finishXORCombine() {
        do {
            let parts = xorEntropyParts.count
            let entropy = try SeedXOR.combine(xorEntropyParts)
            let mnemonic = try BIP39Mnemonic(entropy: entropy)
            let checksum = mnemonic.words.last ?? ""
            pendingMnemonic = mnemonic
            ephemeralOrigin = SeedXORStories.ephemeralOrigin(parts: parts, checksumWord: checksum)
            clearXORSession()
            if !hasSeed, !xorForceTemporary {
                if hasPIN { try commitSeedOntoExistingPIN() }
                else { beginPINSetup(isChange: false) }
            } else {
                try applyEphemeralSeed()
            }
        } catch { present(error) }
    }

    private var xorVaultMenuItems: [SimulatorMenuItem] {
        xorVaultCandidates.enumerated().map { index, candidate in
            SimulatorMenuItem(
                id: "xor-vault-\(candidate.index)",
                title: SeedXORStories.vaultPickLabel(vaultIndex: candidate.index, fingerprint: candidate.fingerprint),
                checked: xorVaultSelected.contains(index),
                action: .command(.menuNoop)
            )
        }
    }

    func toggleXORVaultPick() {
        guard xorVaultCandidates.indices.contains(selectedMenuIndex) else { return }
        if xorVaultSelected.contains(selectedMenuIndex) {
            xorVaultSelected.remove(selectedMenuIndex)
        } else {
            xorVaultSelected.insert(selectedMenuIndex)
        }
    }

    func confirmXORVaultSelection() {
        let chosen = xorVaultSelected.sorted()
        if chosen.isEmpty {
            cancelXORVaultPick()
            return
        }
        for index in chosen where xorVaultCandidates.indices.contains(index) {
            xorEntropyParts.append(xorVaultCandidates[index].entropy)
        }
        leaveXORVaultMenu()
        presentXORPartStatus()
    }

    func cancelXORVaultPick() {
        leaveXORVaultMenu()
        beginWordEntry(purpose: .xorPart, wordCount: xorDesiredWordCount)
    }

    private func leaveXORVaultMenu() {
        guard screen == .menu, currentMenu == .xorVaultPick else { return }
        if let previous = history.popLast() {
            screen = previous
        }
        currentMenu = menuStack.popLast() ?? .seedXOR
        selectedMenuIndex = 0
        menuYPos = 0
    }

    private func matchingXORVaultSeeds() -> [(index: Int, fingerprint: String, entropy: Data)] {
        guard !hobbledMode.isHobbled else { return [] }
        return preferences.vaultedSeeds.enumerated().compactMap { offset, vault in
            let words = vault.mnemonic.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count == xorDesiredWordCount, let mnemonic = try? BIP39Mnemonic(phrase: vault.mnemonic) else {
                return nil
            }
            return (offset, vault.fingerprint, mnemonic.entropy)
        }
    }

    private func clearXORSession() {
        xorEntropyParts = []
        xorWordLists = []
        xorQuizzingSplit = false
        xorQuizPartIndex = 0
        xorVaultCandidates = []
        xorVaultSelected = []
        xorUsedRNG = false
        xorChecksumWord = ""
        xorCanIncludeCurrent = false
        wordQuiz = nil
    }

    private func leaveXORFlowToMenu() {
        clearXORSession()
        while let previous = history.popLast() {
            if previous == .menu {
                currentMenu = menuStack.popLast() ?? .seedXOR
                screen = .menu
                selectedMenuIndex = 0
                menuYPos = 0
                return
            }
        }
        openMenu(.seedXOR, remember: false)
    }

    func beginBIP85() {
        if wipeIfDeltaMode() { return }
        showStory(title: "", body: """
        Create Entropy for Other Wallets (BIP-85)

        This feature derives "entropy" based mathematically on this wallet's seed value. This will be displayed as a 12 or 24 word seed phrase, or formatted in other ways to make it easy to import into other wallet systems.

        You can recreate this value later, based only on the seed-phrase or backup of this Coldcard.

        There is no way to reverse the process, should the other wallet system be compromised, so the other wallet is effectively segregated from the Coldcard and yet still backed-up.
        """, onConfirm: .bip85Intro)
    }

    private func continueBIP85AfterIntro() {
        guard ephemeralPhrase != nil || tmpSeedActive else {
            openMenu(.deriveSeeds)
            return
        }
        let body = !activePassphrase.isEmpty
            ? FirmwareCopy.bip85PassphraseWrap
            : FirmwareCopy.bip85TmpSeedDerive
        showStory(title: "", body: body, onConfirm: .confirmBIP85TmpSeed)
    }

    func beginTypePasswords() {
        typePasswordIndexText = ""
        typePasswordDidSend = false
        typePasswordValue = nil
        typePasswordPath = nil
        typePasswordCachedIndex = nil
        navigate(to: .typePasswordIndex)
    }

    func submitTypePasswordIndex() {
        guard let root = rootKey else { return }
        let index = TypePasswords.parseIndex(typePasswordIndexText)
        if typePasswordCachedIndex == index, typePasswordValue != nil, typePasswordPath != nil {
            typePasswordDidSend = false
            storyTop = 0
            screen = .typePasswordConfirm
            return
        }
        do {
            beginWorking(.working)
            let result = try BIP85.derive(root: root, kind: .password, index: index)
            endWorking()
            typePasswordValue = result.qr
            typePasswordPath = result.path
            typePasswordCachedIndex = index
            typePasswordDidSend = false
            storyTop = 0
            screen = .typePasswordConfirm
        } catch {
            endWorking()
            present(error)
        }
    }

    func confirmTypePasswordSend() {
        if typePasswordDidSend {
            returnToTypePasswordIndex()
            return
        }
        guard let password = typePasswordValue else { return }
        UIPasteboard.general.string = TypePasswords.clipboardPayload(password: password)
        typePasswordDidSend = true
    }

    func cancelTypePasswordConfirm() {
        if !typePasswordDidSend {
            Task { await dramaticPause(FirmwareBusyTitle.aborted, seconds: FirmwareBusyTitle.abortedKeystrokesSeconds) }
        }
        returnToTypePasswordIndex()
    }

    private func returnToTypePasswordIndex() {
        typePasswordDidSend = false
        typePasswordIndexText = ""
        screen = .typePasswordIndex
    }

    private func clearTypePasswordState() {
        typePasswordIndexText = ""
        typePasswordValue = nil
        typePasswordPath = nil
        typePasswordCachedIndex = nil
        typePasswordDidSend = false
    }

    func beginBIP85PasswordPick() {
        bip85JustPick = true
        pendingBIP85Kind = .password
        accountPromptPurpose = .bip85Index
        accountPromptValue = "0"
        navigate(to: .accountNumber)
    }

    func revealBIP85(index: UInt32) {
        guard let root = rootKey else { return }
        do {
            beginWorking(.generating)
            let result = try BIP85.derive(root: root, kind: pendingBIP85Kind, index: index)
            endWorking()
            pendingBIP85Result = result
            if bip85JustPick {
                bip85JustPick = false
                notePassword = result.qr
                statusMessage = "BIP-85 password."
                return
            }
            var msg = result.display
            msg += "\n\nPath Used (index=\(index)):\n  \(result.path)"
            msg += "\n\nRaw Entropy:\n" + result.entropy.hexString
            switch result.kind {
            case .words12, .words18, .words24, .xprv:
                msg += "\n\n" + FirmwareCopy.bip85ExportPrompt
            default:
                msg += "\n\n" + FirmwareCopy.bip85ExportPromptNoSwitch
            }
            let title = result.derivedXFP.map { "[\($0)]" } ?? ""
            showStory(title: title, body: msg, onConfirm: .bip85Reveal)
        } catch {
            endWorking()
            present(error)
        }
    }

    private func exportBIP85Result() {
        guard let result = pendingBIP85Result else { return }
        let mode: String
        switch result.kind {
        case .words12, .words18, .words24: mode = "words"
        case .wif: mode = "wif"
        case .xprv: mode = "xprv"
        case .hex32, .hex64: mode = "hex"
        case .password: mode = "pw"
        }
        let filename = "drv-\(mode)-idx\(result.index).txt"
        let body = (story.body.isEmpty ? result.display : story.body) + "\n"
        let data = Data(body.utf8)
        queueDetachedSignature(for: data, filename: filename)
        prepareExport(data: data, filename: filename, type: .plainText,
                      successStory: (title: "Saved", body: "Filename is:\n\n\(filename)\n\nSignature filename is:\n\n\(BitcoinMessageSigner.signatureFilename(forInputFilename: filename))"))
    }

    private func applyBIP85AsTemporary() {
        guard let result = pendingBIP85Result else { return }
        let origin = "BIP85 Derived from [\(rootKey?.fingerprintHex ?? "--------")], index=\(result.index)"
        switch result.kind {
        case .words12, .words18, .words24:
            do {
                pendingMnemonic = try BIP39Mnemonic(entropy: result.entropy)
                pendingExtendedKey = nil
                ephemeralOrigin = origin
                try applyEphemeralSeed()
            } catch { present(error) }
        case .xprv:
            ephemeralOrigin = origin
            importExtendedKey(result.qr, temporary: true)
        default:
            showStory(title: "", body: FirmwareCopy.bip85ExportPromptNoSwitch)
        }
    }

    private func verifySiblingHashFiles(_ urls: [URL]) {
        let expected = pendingSiblingChecks
        pendingSiblingChecks = []
        var errors: [String] = []
        var warnings: [String] = []
        var checked = Set<String>()
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                warnings.append(name)
                continue
            }
            let digest = SHA2.sha256(data).hexString.lowercased()
            if let match = expected.first(where: { $0.filename == name }) {
                checked.insert(name)
                if match.digest.lowercased() != digest {
                    errors.append("\(name): got \(digest), expected \(match.digest)")
                }
            }
        }
        for item in expected where !checked.contains(item.filename) {
            warnings.append(item.filename)
        }
        var body = ""
        if errors.isEmpty && warnings.isEmpty {
            body = "All listed files match the signed SHA256 digests."
        } else {
            if !errors.isEmpty {
                body += "HASH MISMATCH\n" + errors.joined(separator: "\n") + "\n\n"
            }
            if !warnings.isEmpty {
                body += "Missing (not picked):\n" + warnings.joined(separator: "\n")
            }
        }
        showStory(title: errors.isEmpty ? "CORRECT" : "FAILURE", body: body)
    }

    func isValidPIN(_ pin: String) -> Bool {
        let parts = pin.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { (2...6).contains($0.count) && $0.allSatisfy(\.isNumber) }
    }

    func present(_ error: Error) { errorMessage = error.localizedDescription }

    func beginWorking(_ phase: BusyPhase = .wait, progress: Double? = nil) {
        busyTitle = phase.rawValue
        busyProgress = progress
        gpuBusyBar = false
        isWorking = true
    }

    /// Firmware `dis.busy_bar` — striped GPU bar only, calculator/prefix-word lookup.
    func beginGPUBusyBar() {
        busyTitle = ""
        busyProgress = nil
        gpuBusyBar = true
        isWorking = true
    }

    func endWorking() {
        isWorking = false
        gpuBusyBar = false
        busyTitle = ""
        busyProgress = nil
    }

    func dramaticPause(_ title: String, seconds: Double) async {
        busyTitle = title
        busyProgress = 0
        gpuBusyBar = false
        isWorking = true
        let steps = max(1, Int(seconds * 8))
        for step in 1...steps {
            busyProgress = Double(step) / Double(steps)
            try? await Task.sleep(nanoseconds: 125_000_000)
        }
        endWorking()
    }

    /// Firmware `sign_psbt_file` `dis.fullscreen('Reading...', 0)` + `progress_sofar`.
    func runReadingProgress(bytes: Int) async {
        beginWorking(.reading, progress: 0)
        let steps = min(8, max(2, max(bytes, 1) / 4096 + 1))
        for step in 1...steps {
            busyProgress = Double(step) / Double(steps)
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    /// Firmware `save_visualization` SFFile `message="Visualizing..."`.
    func runVisualizingProgress() async {
        beginWorking(.visualizing, progress: 0)
        busyProgress = 1
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    /// Firmware `ux_dramatic_pause('Aborted.', …)` after a refused confirm.
    private func popStoryAndPauseAborted(seconds: Double) {
        if let previous = history.popLast() { screen = previous }
        selectedMenuIndex = 0
        Task { await dramaticPause(FirmwareBusyTitle.aborted, seconds: seconds) }
    }

    private func rememberMasterXFP() {
        guard ephemeralPhrase == nil, ephemeralXPRV == nil, activePassphrase.isEmpty,
              var record, let hex = rootKey?.fingerprintHex else { return }
        if record.settingsXFP == hex { return }
        record.settingsXFP = hex
        self.record = record
        try? persistRecord()
    }

    func persistPINAttempts() {
        try? persistRecord()
    }

    private func beginDiceMixCollect() {
        diceRolls = ""
        entropyKind = .diceMix
        navigate(to: .entropyCollect)
    }

    private func finishDiceMixIfReady() {
        finishDiceRolls()
    }

    private func toggleMenuStoryIfDefault(_ menu: FirmwareMenu) -> String? {
        switch menu {
        case .fullAddressView where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.fullMultisigAddressView):
            FirmwareCopy.fullAddressView
        case .usbPort where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: preferences.usbPortEnabled):
            FirmwareCopy.usbPortStory
        case .virtualDisk where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: preferences.virtualDiskMode == 0):
            FirmwareCopy.virtualDiskStory
        case .nfcSharing where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.nfcSharingEnabled):
            FirmwareCopy.nfcSharingStory
        case .deletePSBTs where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.deletePSBTs):
            FirmwareCopy.deletePSBTsEnable
        case .keyboardEMU where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.keyboardEmuEnabled):
            FirmwareCopy.keyboardEMUEnable
        case .homeMenuXFP where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.alwaysShowHomeXFP):
            FirmwareCopy.homeMenuXFPStory
        case .menuWrapping where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.menuWrapping):
            FirmwareCopy.menuWrappingStory
        case .seedVaultSetting where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.seedVaultEnabled):
            FirmwareCopy.seedVaultEnable
        case .testnetMode where ToggleMenuStory.showsStoryOnEnter(
            isChain: true, chainIsBitcoin: network == .mainnet, settingKeyMissing: false
        ):
            FirmwareCopy.testnetModeEnable
        case .aeStartIndex where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.aeStartIndexEnabled):
            FirmwareCopy.aeStartIndexEnable
        case .b85IdxValues where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.b85Unlimited):
            FirmwareCopy.b85UnlimitedEnable
        case .sighashChecks where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.sighashWarnOnly):
            FirmwareCopy.sighashChecksEnable
        case .calculatorLogin where ToggleMenuStory.showsStoryOnEnter(settingKeyMissing: !preferences.calculatorLogin):
            FirmwareCopy.calculatorLogin
        case .microSD2FA where preferences.sd2faNonces.isEmpty: FirmwareCopy.microSD2FAIntro
        default: nil
        }
    }

    private func handleUnimplemented(_ name: String) {
        switch name {
        case "Coldcard Backup":
            restoreAsEphemeral = currentMenu == .temporarySeed || pendingEphemeral
            if hasSeed, !restoreAsEphemeral {
                showStory(title: name, body: FirmwareCopy.needClearSeed)
            } else {
                restoreBackupAllowsCleartext = false
                importPurpose = .backup
                showFileImporter = true
            }
        case "Import XPRV":
            scanExpectSecret = true
            pendingEphemeral = currentMenu == .temporarySeed || currentMenu == .temporarySeedImport
            if pendingEphemeral { ephemeralOrigin = FirmwareCopy.importedXPRVOrigin }
            showScanner = true
        case "Lock Down Seed":
            showStory(title: "", body: FirmwareCopy.lockDownSeed, onConfirm: .lockDownSeed, confirmCode: "4")
        case "Restore Bkup":
            // Firmware `restore_backup_dev`: restore even with a seed present (`tmp=not blank`).
            restoreAsEphemeral = hasSeed
            restoreBackupAllowsCleartext = true
            importPurpose = .backup
            showFileImporter = true
        case "Max whitelist":
            showStory(title: "", body: FirmwareCopy.whitelistMaxed)
        default:
            showStory(title: name, body: FirmwareCopy.platformLimit)
        }
    }

    func importExtendedKey(_ xprv: String, temporary: Bool) {
        do {
            _ = try Self.hdKey(fromExtendedPrivate: xprv, network: network)
        } catch {
            showStory(title: "FAILED", body: FirmwareCopy.xprvImportFailed)
            return
        }
        let asTemporary = temporary || pendingEphemeral
        if asTemporary {
            pendingMnemonic = nil
            pendingExtendedKey = xprv
            if ephemeralOrigin.isEmpty || ephemeralOrigin == "unknown origin" || ephemeralOrigin == "Import XPRV" {
                ephemeralOrigin = FirmwareCopy.importedXPRVOrigin
            }
            do { try applyEphemeralSeed() } catch { present(error) }
            return
        }
        if hasSeed {
            showStory(title: "Import XPRV", body: FirmwareCopy.needClearSeed)
            return
        }
        pendingExtendedKey = xprv
        pendingMnemonic = nil
        if hasPIN {
            do { try commitSeedOntoExistingPIN() } catch { present(error) }
        } else {
            beginPINSetup(isChange: false)
        }
    }

    private static func firstExtendedPrivateKey(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let token = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
            guard token.lowercased().contains("prv") else { continue }
            if (try? hdKey(fromExtendedPrivate: token, network: .testnet)) != nil { return token }
        }
        return nil
    }

    static func hdKey(fromExtendedPrivate string: String, network: BitcoinNetwork) throws -> HDKey {
        let body = try Base58.checkDecode(string.trimmingCharacters(in: .whitespacesAndNewlines))
        guard body.count == 78, body[45] == 0 else { throw BIP32Error.invalidKey }
        let version = body.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let chain = Data(body[13..<45])
        let priv = Data(body[46..<78])
        let mainnetVersions: Set<UInt32> = [0x0488ade4, 0x049d7878, 0x04b2430c]
        let detected = mainnetVersions.contains(version) ? BitcoinNetwork.mainnet : network
        return try HDKey.master(privateKey: priv, chainCode: chain, network: detected)
    }

    func beginLockDownSeed() {
        let masterHasWords = !(record?.mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        showStory(
            title: SeedDanger.lockDownTitle,
            body: SeedDanger.lockDownConfirmBody(
                isPassphraseWallet: !activePassphrase.isEmpty,
                masterHasWords: masterHasWords,
                currentHasWords: wordBasedSeed
            ),
            onConfirm: .lockDownSeed,
            confirmCode: SeedDanger.lockDownConfirmKey
        )
    }

    private func lockDownTemporarySeed() {
        guard var record, tmpSeedActive else { return }
        do {
            if !activePassphrase.isEmpty {
                guard let root = rootKey else { return }
                record.mnemonic = ""
                record.extendedPrivateKey = try root.serializePrivate()
            } else if let phrase = ephemeralPhrase {
                record.mnemonic = phrase
                record.extendedPrivateKey = nil
            } else if let xprv = ephemeralXPRV {
                record.mnemonic = ""
                record.extendedPrivateKey = xprv
            } else {
                return
            }
            preferences.vaultedSeeds = []
            preferences.savedPassphrases = []
            record.preferences = preferences
            if let hex = rootKey?.fingerprintHex {
                record.settingsXFP = hex
            }
            self.record = record
            ephemeralPhrase = nil
            ephemeralXPRV = nil
            pendingExtendedKey = nil
            activePassphrase = ""
            passphraseInput = ""
            try persistRecord()
            lock()
        } catch { present(error) }
    }

    /// Firmware `flow.py` ShortcutItem(KEY_NFC, predicate=nfc_enabled, menu=NFCToolsMenu).
    /// Off: the ShortcutItem stays registered but `predicate()` fails, so the key is a no-op.
    func openNFCTools() {
        guard preferences.nfcSharingEnabled else { return }
        guard screen == .menu else { return }
        if let index = menuItems.firstIndex(where: { $0.title == "NFC Tools" || $0.title == "NFC File Share" }) {
            selectedMenuIndex = index
            perform(menuItems[index].action)
            return
        }
        if currentMenu == .home {
            openMenu(.nfcTools)
        }
    }

    /// Firmware `menu.py`: `shortcut_key` matches RUN the item; first-letter search only highlights.
    func activateMenuShortcut(_ value: String) {
        handleMenuShortcut(value)
    }

    private static let qrMenuShortcutTitles: Set<String> = [
        "Scan Any QR Code", "Scan QR Code", "QR File Share", "Import from QR Scan", "Edit Phrase"
    ]
}

nonisolated func exportWalletData(kind: WalletExportKind, root: HDKey, account: UInt32,
                                  addressType: AddressType, descriptorCombined: Bool,
                                  wallets: [MultisigWalletConfig] = []) throws -> Data {
    switch kind {
    case .sparrow, .cove, .nunchuk, .fullyNoded, .theya, .bitcoinSafe, .genericJSON:
        return try WalletExporter.firmwareGenericJSON(root: root, account: account)
    case .blueWallet, .electrum:
        return try WalletExporter.electrumWallet(root: root, type: addressType, account: account,
                                                 labelPrefix: "Coldcard Import")
    case .bitcoinCore:
        return Data(try WalletExporter.bitcoinCore(root: root, account: account).utf8)
    case .wasabi:
        return try WalletExporter.wasabiWallet(root: root)
    case .bullBitcoin, .zeus, .descriptor:
        return Data(try WalletExporter.descriptorExport(root: root, type: addressType, account: account,
                                                        combined: descriptorCombined).utf8)
    case .unchained:
        return try WalletExporter.unchained(root: root, account: account)
    case .samouraiPostmix:
        return Data(try WalletExporter.descriptor(root: root, type: .nativeSegwit, account: 2_147_483_646).utf8)
    case .samouraiPremix:
        return Data(try WalletExporter.descriptor(root: root, type: .nativeSegwit, account: 2_147_483_645).utf8)
    case .keyExpression:
        return Data(try WalletExporter.keyExpression(root: root, type: .nativeSegwit, account: account).utf8)
    case .keyExpressionClassic:
        return Data(try WalletExporter.keyExpression(root: root, type: .legacy, account: account).utf8)
    case .keyExpressionWrapped:
        return Data(try WalletExporter.keyExpression(root: root, type: .wrappedSegwit, account: account).utf8)
    case .keyExpressionMultiWSH, .keyExpressionMultiSHWSH:
        // Firmware BIP-48 multisig paths: m/48'/coin'/account'/2' (P2WSH) and .../1' (P2SH-P2WSH).
        let script: UInt32 = kind == .keyExpressionMultiWSH ? 2 : 1
        let path = try DerivationPath("m/48'/\(root.network.coinType)'/\(account)'/\(script)'")
        return Data(try WalletExporter.keyExpression(root: root, path: path).utf8)
    case .dumpSummary:
        return Data(try WalletExporter.dumpSummary(root: root, wallets: wallets).utf8)
    case .xpubSegwit, .xpubClassic, .xpubWrapped, .xpubMaster, .xpubXFP:
        return Data()
    }
}

nonisolated enum SimulatorInputError: LocalizedError {
    case invalidPIN
    case pinMismatch
    case missingSeed

    var errorDescription: String? {
        switch self {
        case .invalidPIN: "Use the Coldcard format: 2–6 digits, a hyphen, and another 2–6 digits (for example, 12-12)."
        case .pinMismatch: "The two PINs do not match."
        case .missingSeed: "No seed has been prepared."
        }
    }
}

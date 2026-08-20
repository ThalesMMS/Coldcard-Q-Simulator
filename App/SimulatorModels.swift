import Foundation
import ColdcardCore

/// Firmware `Display.fullscreen` busy titles (`Wait...`, `Loading...`, …).
nonisolated enum BusyPhase: String, Equatable, Sendable {
    case wait = "Wait..."
    case loading = "Loading..."
    case saving = "Saving..."
    case generating = "Generating..."
    case validating = "Validating..."
    case formatting = "Formatting..."
    case working = "Working..."
    case pickingKey = "Picking key..."
    case rendering = "Rendering..."
    case reading = "Reading..."
    case visualizing = "Visualizing..."
    case applying = "Applying..."
    /// Firmware `bbqr.py` `dis.fullscreen('Decompressing...')`.
    case decompressing = "Decompressing..."
    case clearing = "Clearing..."
}

nonisolated enum SimulatorScreen: String, Hashable, Sendable {
    case menu
    case unlock
    case pinSetup
    case seedWords
    case wordQuiz
    case diceRoll
    case importSeed
    case passphrase
    case passphraseConfirm
    case addresses
    case addressDetail
    case accountNumber
    case psbt
    case psbtSigned
    case walletExport
    case messageSigning
    case noteEditor
    case backupPassword
    case verifyBackup
    case hexEntry
    case calculator
    case story
    case viewIdentity
    case brick
    case wordEntry
    case entropyCollect
    case psbtExplorer
    case loginCountdown
    /// Full-screen nickname shown before PIN (`actions.show_nickname`).
    case nicknameSplash
    /// Firmware `drv_entro.password_entry` BIP-85 index (`Password Index?`).
    case typePasswordIndex
    /// Firmware `send_keystrokes` confirm, then clipboard send + typed-keys confirmation.
    case typePasswordConfirm
    /// Firmware `ux_input_text` List Files rename (`actions.list_files`).
    case listedFileRename
    /// In-app stand-in for the serial MicroPython REPL after `dev_enable_repl`.
    case serialREPL
    /// Firmware `NFC.start_psbt_rx` → `start_nfc_rx` / `ux_animation`.
    case nfcReceive
    /// Firmware `q1.scan_and_bag` lockup (`Put into bag and seal now.`).
    case factoryBagged
    /// Firmware `actions.start_dfu` / unix `Enter bootloader (DFU)` until power.
    case factoryDFU
    /// Q `show_logout` / `clean_shutdown` power-down until the power key.
    case poweredOff
}

nonisolated enum FirmwareMenu: String, Hashable, Sendable {
    case virgin
    /// Firmware `FactoryMenu` while `version.is_factory_mode`.
    case factory
    case emptyWallet
    case home
    case advanced
    case advancedVirgin
    case advancedEmpty
    case dangerZone
    case seedFunctions
    case backup
    case fileManagement
    /// Firmware `file_picker` menu pushed by List Files (`actions.py`).
    case listedFiles
    /// Firmware `ready2sign` multi-file `file_picker(..., allow_batch=("[Sign All]", batch_sign))`.
    case readyToSignFiles
    case settings
    case loginSettings
    case buriedSettings
    case displayUnits
    case maxNetworkFee
    case deletePSBTs
    case testnetMode
    case sighashChecks
    case calculatorLogin
    case aeStartIndex
    case menuWrapping
    case homeMenuXFP
    case newSeed
    case seedDice
    case importExisting
    case passphrase
    case savedPassphrases
    case addressExplorer
    case applications
    case samourai
    case exportWallet
    case exportXPUB
    case exportKeyExpression
    case exportAddressType
    case messageAddressFormat
    case customPathFormat
    case keypath
    case notes
    case noteActions
    case noteGroup
    case noteGroupPicker
    case savedPassphraseActions
    case upgradeFirmware
    case temporarySeed
    case iAmDeveloper
    case debugFunctions
    case seedXOR
    case spendingPolicy
    case nfcTools
    case hardwareOnOff
    case idleTimeout
    case idleTimeoutBattery
    case lcdBrightnessBattery
    case keyboardEMU
    case seedVaultSetting
    case b85IdxValues
    case usbPort
    case virtualDisk
    case nfcSharing
    case loginCountdown
    case nfcPushTx
    case deriveSeeds
    case temporarySeedGenerate
    case temporarySeedImport
    case psbtExplorer
    case userEntropy
    case seedVault
    case seedVaultActions
    case scrambleKeys
    case killKey
    case microSD2FA
    case trickPINs
    case trickPINDetail
    case trickNewActions
    case trickWipeChoices
    case trickDuressChoices
    case trickCountdownChoices
    case trickWrongActions
    case trickCountdownPeriod
    case wifStore
    case wifStoreItem
    case ssspConfig
    case spendingPolicyEdit
    case spendingPolicyVelocity
    case spendingPolicyWhitelist
    case cccConfig
    case paperWallets
    case paperWalletTemplates
    case keyTeleportSend
    case keyTeleportNotes
    case keyTeleportVault
    case keyTeleportCosigners
    /// Firmware `xor_seed.py` Seed Vault `MenuSystem(..., multichoice=True)`.
    case xorVaultPick
    case multisigWallets
    case multisigWallet
    case transigUnusedPlaceholder
    case multisigDescriptors
    case trustPSBT
    case skipChecks
    case fullAddressView
    case unsortedMultisig
}

nonisolated enum NFCReadKind: String, Equatable, Sendable {
    case psbt
    case showAddress
    case verifyAddress
    case importMultisig
}

nonisolated enum PSBTInputChannel: Equatable, Sendable {
    case qr
    case nfc
    case sd
    case vdisk
    case kt
    case other
}

nonisolated enum ImportPurpose: Sendable {
    case psbt
    case batchPSBT
    case backup
    case verifyBackup
    case signText
    case notes
    case fileShare
    case verifySig
    case nfcVerifySig
    case siblingHashes
    case spendingWhitelist
    case wif
    case microSD2FA
    case tapsigner
    case cloneStartFile
    case cloneIngest
    case nfcSeed
    case pushTransaction
    case teleportPSBT
    case nfcShowAddress
    case nfcVerifyAddress
    case nfcImportMultisig
    case nfcSignMessage
    case xprv
    case multisig
    case multisigCreateXPUB
}

nonisolated enum NFCStandInKind: Equatable, Sendable {
    case psbt
    case ephemeralSeed
    case showAddress
    case verifyAddress
    case importMultisig
    case signMessage
    case verifySigFile
}

/// Firmware message-sign completion: `msg_signing_done` / `NFC.msg_sign_done` / `qr_msg_sign_done`.
nonisolated enum MessageSignDoneMode: Equatable, Sendable {
    case exportPrompt
    case nfcRFC
    case qrDone
}

nonisolated struct BatchPSBTItem: Equatable, Sendable {
    var name: String
    var data: Data
    var url: URL? = nil
}

nonisolated enum InterfaceMode: String, Sendable {
    case device
    case phone
}

nonisolated enum SecureNoteKind: String, Codable, Sendable {
    case note
    case password
}

nonisolated struct SecureNote: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: SecureNoteKind
    var title: String
    var username: String
    var password: String
    var site: String
    var note: String

    var group: String

    init(id: UUID = UUID(), kind: SecureNoteKind = .note, title: String, username: String = "",
         password: String = "", site: String = "", note: String = "", group: String = "") {
        self.id = id
        self.kind = kind
        self.title = title
        self.username = username
        self.password = password
        self.site = site
        self.note = note
        self.group = group
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        site = try container.decodeIfPresent(String.self, forKey: .site) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? ""
        if let kind = try container.decodeIfPresent(SecureNoteKind.self, forKey: .kind) {
            self.kind = kind
        } else {
            self.kind = (username.isEmpty && password.isEmpty) ? .note : .password
        }
    }

    /// Firmware `NoteContentBase.serialize` fields (`notes.py`).
    func firmwareRecord() -> [String: String] {
        if kind == .password {
            var record: [String: String] = ["title": title, "user": username]
            if !password.isEmpty { record["password"] = password }
            if !site.isEmpty { record["site"] = site }
            if !note.isEmpty { record["misc"] = note }
            if !group.isEmpty { record["group"] = group }
            return record
        }
        var record: [String: String] = ["title": title]
        if !note.isEmpty { record["misc"] = note }
        if !group.isEmpty { record["group"] = group }
        return record
    }

    static func fromFirmwareRecord(_ record: [String: String]) -> SecureNote {
        let isPassword = record.keys.contains("user")
        return SecureNote(kind: isPassword ? .password : .note,
                          title: record["title"] ?? "",
                          username: record["user"] ?? "",
                          password: record["password"] ?? "",
                          site: record["site"] ?? "",
                          note: record["misc"] ?? "",
                          group: record["group"] ?? "")
    }

    var canSignMisc: Bool {
        (2...BitcoinMessageSigner.maximumLength).contains(note.count)
    }

    func isB39PassApplicable(readOnly: Bool, relatedKeys: Bool, wordBased: Bool) -> Bool {
        SecureNotes.isB39PassApplicable(
            kind == .password ? password : note,
            readOnly: readOnly,
            relatedKeys: relatedKeys,
            wordBased: wordBased
        )
    }
}

nonisolated struct SavedPassphrase: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var fingerprint: String
    var phrase: String
}

nonisolated struct VaultedSeed: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var fingerprint: String
    var mnemonic: String
    var label: String
    var origin: String
    /// Firmware `SecretStash` xprv tmp seeds stored in Seed Vault.
    var extendedPrivateKey: String? = nil
}

/// Firmware `pa.hobbled_mode`: `True` after ACTIVATE, `2` during Test Drive (`ccc.py`).
nonisolated enum HobbledMode: Int, Equatable, Sendable {
    case off = 0
    case active = 1
    case testdrive = 2

    var isHobbled: Bool { self != .off }
    var isTestDrive: Bool { self == .testdrive }
}

nonisolated struct SSSPSettings: Codable, Equatable, Sendable {
    var enabled = false
    var wordCheck = false
    var allowNotes = false
    var relatedKeys = false
    var policy = SpendingPolicyLimits()
    var bypassPINSalt: Data?
    var bypassPINHash: Data?
}

nonisolated struct CCCRelatedWallet: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var requiredSignatures: Int
    var totalSigners: Int
    var keyBXFP: String
    var keyBXPUB: String
}

nonisolated struct CCCSettings: Codable, Equatable, Sendable {
    var mnemonic: String
    var xfp: String
    var xpub: String
    var policy = SpendingPolicyLimits()
    var relatedWallets: [CCCRelatedWallet] = []
}

nonisolated enum SpendingWeb2FAPending: Equatable, Sendable {
    case enroll
    case enrollMore
    case test
    case ssspSign
    case cccSign
}

nonisolated struct SpendingPolicyMenuSnapshot: Equatable, Sendable {
    var hobbled: HobbledMode = .off
    var ssspDefined = false
    var wordCheck = false
    var allowNotes = false
    var relatedKeys = false
    var cccDefined = false
    var cccXFP: String? = nil
    var cccRelated: [CCCRelatedWallet] = []
    var lastViolation: String? = nil
    var policy = SpendingPolicyLimits()
    var notesReadOnly = false
}

typealias ImportedMultisigWallet = MultisigWalletConfig

nonisolated struct SimulatorPreferences: Codable, Equatable, Sendable {
    var secnapEnabled = false
    var displayUnits: DisplayUnits = .btc
    var maxNetworkFee: MaxNetworkFee = .ten
    var deletePSBTs = false
    var menuWrapping = false
    var calculatorLogin = false
    var aeStartIndexEnabled = false
    var alwaysShowHomeXFP = false
    var skipAddressExplorerIntro = false
    var skipPassphraseIntro = false
    var sighashWarnOnly = false
    var lastBackupPassword: [String] = []
    var savedPassphrases: [SavedPassphrase] = []
    var seedVaultEnabled = false
    var lastAddressType: AddressType?
    var lastAddressIndex: UInt32 = 0
    var vaultedSeeds: [VaultedSeed] = []
    var scrambleKeys = false
    var killKey = ""
    var loginCountdownMinutes = 0
    var b85Unlimited = false
    var idleTimeoutSeconds = 4 * 3600
    var idleTimeoutBatterySeconds = 10 * 60
    var nfcSharingEnabled = false
    /// Firmware `ptxurl`. Empty/nil disables Push Tx.
    var ptxurl: String?
    var importedMultisigWallets: [ImportedMultisigWallet] = []
    /// Firmware settings `msas`.
    var fullMultisigAddressView = false
    /// Firmware settings `unsort_ms`.
    var allowUnsortedMultisig = false
    /// Firmware settings `pms`. Nil uses verify-if-wallets-exist / offer-otherwise.
    var psbtMultisigTrust: Int?
    var usbPortEnabled = true
    /// Firmware settings `du`. `nil` means unset so First-Time UX may run once.
    var du: Int? = nil
    /// Firmware `vidsk`: 0 = off, 1 = enable, 2 = enable & auto.
    var virtualDiskMode = 0
    var keyboardEmuEnabled = false
    /// Firmware settings `tested` — factory selftest completed.
    var tested = false
    /// Bootrom factory flag analogue (`callgate.get_factory_mode` / unix `-f`).
    /// Effective factory mode is this flag with no programmed bag number (`version.py`).
    var factoryModeFlag = false
    /// SE bag number analogue (`callgate.get_bag_number`). Nil/empty = unprogrammed.
    var bagNumber: String?
    /// Firmware settings `bkpw` — stored backup-file password override.
    var bkpw: String?
    /// Firmware settings `sssp`.
    var sssp: SSSPSettings?
    /// Firmware settings `ccc`.
    var ccc: CCCSettings?
    /// Firmware settings `lfr` (last spending-policy fail reason).
    var spendingLastFail: String?
    /// Firmware settings `sd2fa` — enrolled MicroSD 2FA card nonces.
    var sd2faNonces: [String] = []
    /// Firmware settings `ktrx` — hex private key for the current Key Teleport receive attempt.
    var keyTeleportRxKeyHex: String?
    /// Firmware settings `ovc` — encoded segwit prevout amounts (`history.OutptValueCache`).
    var ovc: [String] = []

    private enum CodingKeys: String, CodingKey {
        case secnapEnabled, displayUnits, maxNetworkFee, deletePSBTs, menuWrapping, calculatorLogin
        case aeStartIndexEnabled, alwaysShowHomeXFP, skipAddressExplorerIntro, skipPassphraseIntro
        case sighashWarnOnly, lastBackupPassword, savedPassphrases, seedVaultEnabled
        case lastAddressType, lastAddressIndex, vaultedSeeds
        case scrambleKeys, killKey, loginCountdownMinutes, b85Unlimited
        case idleTimeoutSeconds, idleTimeoutBatterySeconds, nfcSharingEnabled, usbPortEnabled, virtualDiskMode
        case du
        case virtualDiskEnabled
        case keyboardEmuEnabled, tested, bkpw
        case factoryModeFlag, bagNumber
        case ptxurl, importedMultisigWallets, fullMultisigAddressView, allowUnsortedMultisig, psbtMultisigTrust
        case sssp, ccc, spendingLastFail, sd2faNonces
        case keyTeleportRxKeyHex
        case ovc
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case seclapEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        secnapEnabled = try container.decodeIfPresent(Bool.self, forKey: .secnapEnabled)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .seclapEnabled) ?? false
        displayUnits = try container.decodeIfPresent(DisplayUnits.self, forKey: .displayUnits) ?? .btc
        maxNetworkFee = try container.decodeIfPresent(MaxNetworkFee.self, forKey: .maxNetworkFee) ?? .ten
        deletePSBTs = try container.decodeIfPresent(Bool.self, forKey: .deletePSBTs) ?? false
        menuWrapping = try container.decodeIfPresent(Bool.self, forKey: .menuWrapping) ?? false
        calculatorLogin = try container.decodeIfPresent(Bool.self, forKey: .calculatorLogin) ?? false
        aeStartIndexEnabled = try container.decodeIfPresent(Bool.self, forKey: .aeStartIndexEnabled) ?? false
        alwaysShowHomeXFP = try container.decodeIfPresent(Bool.self, forKey: .alwaysShowHomeXFP) ?? false
        skipAddressExplorerIntro = try container.decodeIfPresent(Bool.self, forKey: .skipAddressExplorerIntro) ?? false
        skipPassphraseIntro = try container.decodeIfPresent(Bool.self, forKey: .skipPassphraseIntro) ?? false
        sighashWarnOnly = try container.decodeIfPresent(Bool.self, forKey: .sighashWarnOnly) ?? false
        lastBackupPassword = try container.decodeIfPresent([String].self, forKey: .lastBackupPassword) ?? []
        savedPassphrases = try container.decodeIfPresent([SavedPassphrase].self, forKey: .savedPassphrases) ?? []
        seedVaultEnabled = try container.decodeIfPresent(Bool.self, forKey: .seedVaultEnabled) ?? false
        lastAddressType = try container.decodeIfPresent(AddressType.self, forKey: .lastAddressType)
        lastAddressIndex = try container.decodeIfPresent(UInt32.self, forKey: .lastAddressIndex) ?? 0
        vaultedSeeds = try container.decodeIfPresent([VaultedSeed].self, forKey: .vaultedSeeds) ?? []
        scrambleKeys = try container.decodeIfPresent(Bool.self, forKey: .scrambleKeys) ?? false
        killKey = try container.decodeIfPresent(String.self, forKey: .killKey) ?? ""
        loginCountdownMinutes = try container.decodeIfPresent(Int.self, forKey: .loginCountdownMinutes) ?? 0
        b85Unlimited = try container.decodeIfPresent(Bool.self, forKey: .b85Unlimited) ?? false
        idleTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .idleTimeoutSeconds) ?? 4 * 3600
        idleTimeoutBatterySeconds = try container.decodeIfPresent(Int.self, forKey: .idleTimeoutBatterySeconds) ?? 10 * 60
        nfcSharingEnabled = try container.decodeIfPresent(Bool.self, forKey: .nfcSharingEnabled) ?? false
        ptxurl = try container.decodeIfPresent(String.self, forKey: .ptxurl)
        importedMultisigWallets = try container.decodeIfPresent([ImportedMultisigWallet].self, forKey: .importedMultisigWallets) ?? []
        fullMultisigAddressView = try container.decodeIfPresent(Bool.self, forKey: .fullMultisigAddressView) ?? false
        allowUnsortedMultisig = try container.decodeIfPresent(Bool.self, forKey: .allowUnsortedMultisig) ?? false
        psbtMultisigTrust = try container.decodeIfPresent(Int.self, forKey: .psbtMultisigTrust)
        usbPortEnabled = try container.decodeIfPresent(Bool.self, forKey: .usbPortEnabled) ?? true
        du = try container.decodeIfPresent(Int.self, forKey: .du)
        if let mode = try container.decodeIfPresent(Int.self, forKey: .virtualDiskMode) {
            virtualDiskMode = min(max(mode, 0), 2)
        } else if let enabled = try container.decodeIfPresent(Bool.self, forKey: .virtualDiskEnabled) {
            virtualDiskMode = enabled ? 1 : 0
        }
        keyboardEmuEnabled = try container.decodeIfPresent(Bool.self, forKey: .keyboardEmuEnabled) ?? false
        tested = try container.decodeIfPresent(Bool.self, forKey: .tested) ?? false
        factoryModeFlag = try container.decodeIfPresent(Bool.self, forKey: .factoryModeFlag) ?? false
        bagNumber = try container.decodeIfPresent(String.self, forKey: .bagNumber)
        bkpw = try container.decodeIfPresent(String.self, forKey: .bkpw)
        sssp = try container.decodeIfPresent(SSSPSettings.self, forKey: .sssp)
        ccc = try container.decodeIfPresent(CCCSettings.self, forKey: .ccc)
        spendingLastFail = try container.decodeIfPresent(String.self, forKey: .spendingLastFail)
        sd2faNonces = try container.decodeIfPresent([String].self, forKey: .sd2faNonces) ?? []
        keyTeleportRxKeyHex = try container.decodeIfPresent(String.self, forKey: .keyTeleportRxKeyHex)
        ovc = try container.decodeIfPresent([String].self, forKey: .ovc) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(secnapEnabled, forKey: .secnapEnabled)
        try container.encode(displayUnits, forKey: .displayUnits)
        try container.encode(maxNetworkFee, forKey: .maxNetworkFee)
        try container.encode(deletePSBTs, forKey: .deletePSBTs)
        try container.encode(menuWrapping, forKey: .menuWrapping)
        try container.encode(calculatorLogin, forKey: .calculatorLogin)
        try container.encode(aeStartIndexEnabled, forKey: .aeStartIndexEnabled)
        try container.encode(alwaysShowHomeXFP, forKey: .alwaysShowHomeXFP)
        try container.encode(skipAddressExplorerIntro, forKey: .skipAddressExplorerIntro)
        try container.encode(skipPassphraseIntro, forKey: .skipPassphraseIntro)
        try container.encode(sighashWarnOnly, forKey: .sighashWarnOnly)
        try container.encode(lastBackupPassword, forKey: .lastBackupPassword)
        try container.encode(savedPassphrases, forKey: .savedPassphrases)
        try container.encode(seedVaultEnabled, forKey: .seedVaultEnabled)
        try container.encodeIfPresent(lastAddressType, forKey: .lastAddressType)
        try container.encode(lastAddressIndex, forKey: .lastAddressIndex)
        try container.encode(vaultedSeeds, forKey: .vaultedSeeds)
        try container.encode(scrambleKeys, forKey: .scrambleKeys)
        try container.encode(killKey, forKey: .killKey)
        try container.encode(loginCountdownMinutes, forKey: .loginCountdownMinutes)
        try container.encode(b85Unlimited, forKey: .b85Unlimited)
        try container.encode(idleTimeoutSeconds, forKey: .idleTimeoutSeconds)
        try container.encode(idleTimeoutBatterySeconds, forKey: .idleTimeoutBatterySeconds)
        try container.encode(nfcSharingEnabled, forKey: .nfcSharingEnabled)
        try container.encodeIfPresent(ptxurl, forKey: .ptxurl)
        try container.encode(importedMultisigWallets, forKey: .importedMultisigWallets)
        try container.encode(fullMultisigAddressView, forKey: .fullMultisigAddressView)
        try container.encode(allowUnsortedMultisig, forKey: .allowUnsortedMultisig)
        try container.encodeIfPresent(psbtMultisigTrust, forKey: .psbtMultisigTrust)
        try container.encode(usbPortEnabled, forKey: .usbPortEnabled)
        try container.encodeIfPresent(du, forKey: .du)
        try container.encode(virtualDiskMode, forKey: .virtualDiskMode)
        try container.encode(keyboardEmuEnabled, forKey: .keyboardEmuEnabled)
        try container.encode(tested, forKey: .tested)
        try container.encode(factoryModeFlag, forKey: .factoryModeFlag)
        try container.encodeIfPresent(bagNumber, forKey: .bagNumber)
        try container.encodeIfPresent(bkpw, forKey: .bkpw)
        try container.encodeIfPresent(sssp, forKey: .sssp)
        try container.encodeIfPresent(ccc, forKey: .ccc)
        try container.encodeIfPresent(spendingLastFail, forKey: .spendingLastFail)
        try container.encode(sd2faNonces, forKey: .sd2faNonces)
        try container.encodeIfPresent(keyTeleportRxKeyHex, forKey: .keyTeleportRxKeyHex)
        try container.encode(ovc, forKey: .ovc)
    }
}

nonisolated enum PINSetupPhase: String, Equatable, Sendable {
    case warning
    case proveRead
    case prefix
    case suffix
    case confirmPrefix
    case confirmSuffix
}

nonisolated enum PINSetupPurpose: Equatable, Sendable {
    case wallet
    case changeMain
    case ssspBypass
    case trickNew
    case trickChange
}

nonisolated enum UnlockPhase: String, Equatable, Sendable {
    case prefix
    case suffix
    case confirmRiskyAttempt
}

nonisolated enum NoteEditorMode: Equatable, Sendable {
    case createNote
    case createPassword
    case editNote
    case editPasswordMetadata
    case changePassword
}

nonisolated enum WordEntryPurpose: Equatable, Sendable {
    case importSeed
    case backupPassword
    case notesImportPassword
    case xorPart
    case ssspFirstLast
    case cccKeyC
    case cccChallenge
}

nonisolated enum EntropyCollectKind: Equatable, Sendable {
    case mash
    case coin
    case diceMix
}

nonisolated enum PSBTExploreKind: Equatable, Sendable {
    case inputs
    case outputs
}

nonisolated enum AccountNumberPurpose: Equatable, Sendable {
    case addressExplorer
    case addressStartIndex
    case messageSigning
    case messageIndex
    case walletExport
    case psbtExploreIndex
    case keypathIndex
    case bip85Index
    case spendingMagnitude
    case web2FACode
    case trickWrongCount
    case multisigXPUB
    case multisigCreateAccount
    case multisigCreateM
}

nonisolated enum WalletExportKind: String, CaseIterable, Sendable {
    case sparrow, cove, bitcoinCore, nunchuk, bullBitcoin, blueWallet, electrum
    case wasabi, fullyNoded, unchained, theya, bitcoinSafe, zeus
    case samouraiPostmix, samouraiPremix, descriptor, genericJSON
    case keyExpression, keyExpressionClassic, keyExpressionWrapped
    case keyExpressionMultiWSH, keyExpressionMultiSHWSH
    case dumpSummary
    case xpubSegwit, xpubClassic, xpubWrapped, xpubMaster, xpubXFP

    /// Entries of the firmware "Key Expression" step-2 menu (`key_expression_skeleton`).
    static let keyExpressionKinds: [WalletExportKind] = [
        .keyExpression, .keyExpressionClassic, .keyExpressionWrapped,
        .keyExpressionMultiWSH, .keyExpressionMultiSHWSH
    ]

    var menuTitle: String {
        switch self {
        case .sparrow: "Sparrow"
        case .cove: "Cove"
        case .bitcoinCore: "Bitcoin Core"
        case .nunchuk: "Nunchuk"
        case .bullBitcoin: "Bull Bitcoin"
        case .blueWallet: "Blue Wallet"
        case .electrum: "Electrum Wallet"
        case .wasabi: "Wasabi Wallet"
        case .fullyNoded: "Fully Noded"
        case .unchained: "Unchained"
        case .theya: "Theya"
        case .bitcoinSafe: "Bitcoin Safe"
        case .zeus: "Zeus"
        case .samouraiPostmix: "Samourai Postmix"
        case .samouraiPremix: "Samourai Premix"
        case .descriptor: "Descriptor"
        case .genericJSON: "Generic JSON"
        case .keyExpression: "Segwit P2WPKH"
        case .keyExpressionClassic: "Classic P2PKH"
        case .keyExpressionWrapped: "P2SH-Segwit"
        case .keyExpressionMultiWSH: "Multi P2WSH"
        case .keyExpressionMultiSHWSH: "Multi P2SH-P2WSH"
        case .dumpSummary: "Dump Summary"
        case .xpubSegwit: "Segwit (BIP-84)"
        case .xpubClassic: "Classic (BIP-44)"
        case .xpubWrapped: "P2WPKH/P2SH (BIP-49)"
        case .xpubMaster: "Master XPUB"
        case .xpubXFP: "Current XFP"
        }
    }

    var asksAccount: Bool {
        switch self {
        case .wasabi, .samouraiPostmix, .samouraiPremix, .xpubMaster, .xpubXFP, .dumpSummary, .bullBitcoin:
            false
        default:
            true
        }
    }

    var needsAddressTypeMenu: Bool {
        switch self {
        case .electrum, .blueWallet, .descriptor, .zeus: true
        default: false
        }
    }

    var firmwarePrompt: String? {
        switch self {
        case .electrum:
            // Firmware `electrum_export_story`: single `\n` after "computer." then address-type line.
            "This saves a skeleton Electrum wallet file. You can then open that file in the wallet without ever connecting this Coldcard to a computer.\nChoose an address type for the wallet on the next screen."
        case .blueWallet:
            "This saves a skeleton Blue wallet file. You can then open that file in the wallet without ever connecting this Coldcard to a computer.\nChoose an address type for the wallet on the next screen."
        case .bitcoinCore:
            "This saves commands and instructions into a file, including the public keys (xpub). You can then run the commands in Bitcoin Core's console window, without ever connecting this Coldcard to a computer."
        case .wasabi:
            "This saves a skeleton Wasabi wallet file. You can then open that file in Wasabi without ever connecting this Coldcard to a computer."
        case .unchained:
            // Firmware trailing space before `PICK_ACCOUNT` (`unchained_capital_export`).
            "This saves multisig XPUB information required to setup on the Unchained platform. "
        case .genericJSON:
            "Saves JSON file, with XPUB values that are needed to watch typical single-signer UTXO associated with this Coldcard."
        case .sparrow, .cove, .nunchuk, .fullyNoded, .theya, .bitcoinSafe:
            "This saves a JSON file to use with \(menuTitle) Wallet. Works for both single signature and multisig wallets."
        case .descriptor:
            "This saves a ranged xpub descriptor"
        case .zeus:
            "This saves a ranged xpub descriptor for Zeus Wallet"
        case .samouraiPostmix:
            "This saves a ranged xpub descriptor for Samourai POST-MIX account."
        case .samouraiPremix:
            "This saves a ranged xpub descriptor for Samourai PRE-MIX account."
        case .dumpSummary:
            "Saves a text file with a summary of the *public* details of your wallet. For example, this gives the XPUB (extended public key) that you will need to import other wallet software to track balance."
        default:
            nil
        }
    }

    /// Firmware `ux_show_story` has no title; Dump Summary uses `ux_confirm` ("Are you SURE ?!?").
    var firmwareIntroTitle: String { self == .dumpSummary ? "Are you SURE ?!?" : "" }

    /// Unique intro + `PICK_ACCOUNT` + `SENSITIVE_NOT_SECRET` as firmware concatenates them.
    var firmwareIntroStory: String {
        var parts: [String] = []
        if let firmwarePrompt { parts.append(firmwarePrompt) }
        if asksAccount { parts.append(FirmwareCopy.pickAccount) }
        parts.append(FirmwareCopy.sensitiveNotSecret)
        return parts.joined(separator: "\n\n")
    }

    /// Firmware `export_contents` title used in the SD "file written" story.
    var firmwareExportContentsTitle: String {
        switch self {
        case .dumpSummary: "Summary"
        case .electrum: "Electrum wallet"
        case .blueWallet: "Blue wallet"
        case .wasabi: "Wasabi wallet"
        case .genericJSON: "Generic Export"
        case .sparrow, .cove, .nunchuk, .fullyNoded, .theya, .bitcoinSafe:
            "\(menuTitle) Wallet"
        case .unchained: "Unchained"
        case .bitcoinCore: "Bitcoin Core"
        case .descriptor, .zeus, .samouraiPostmix, .samouraiPremix, .bullBitcoin: "Descriptor"
        case .keyExpression, .keyExpressionClassic, .keyExpressionWrapped,
             .keyExpressionMultiWSH, .keyExpressionMultiSHWSH: "Key Expression"
        default: menuTitle
        }
    }

    func signatureAccount(exportAccount: UInt32) -> UInt32 {
        switch self {
        case .samouraiPostmix: 2_147_483_646
        case .samouraiPremix: 2_147_483_645
        case .wasabi, .dumpSummary: 0
        default: exportAccount
        }
    }

    func signatureFormat(addressType: AddressType, account: UInt32, coinType: UInt32) -> WalletExportSignatureFormat? {
        switch self {
        case .xpubSegwit, .xpubClassic, .xpubWrapped, .xpubMaster, .xpubXFP, .bullBitcoin:
            nil
        case .genericJSON, .sparrow, .cove, .nunchuk, .fullyNoded, .theya, .bitcoinSafe:
            .generic
        case .electrum, .blueWallet:
            .electrum(addressType)
        case .wasabi:
            .wasabi
        case .unchained:
            .unchained
        case .bitcoinCore:
            .bitcoinCore
        case .dumpSummary:
            .dumpSummary
        case .descriptor, .zeus, .samouraiPostmix, .samouraiPremix:
            .descriptor(self == .samouraiPostmix || self == .samouraiPremix ? .nativeSegwit : addressType)
        case .keyExpression:
            .keyExpression(derive: "m/84h/\(coinType)h/\(account)h", addressType: .nativeSegwit)
        case .keyExpressionClassic:
            .keyExpression(derive: "m/44h/\(coinType)h/\(account)h", addressType: .legacy)
        case .keyExpressionWrapped:
            .keyExpression(derive: "m/49h/\(coinType)h/\(account)h", addressType: .wrappedSegwit)
        case .keyExpressionMultiWSH:
            .keyExpression(derive: "m/48h/\(coinType)h/\(account)h/2h", addressType: .legacy)
        case .keyExpressionMultiSHWSH:
            .keyExpression(derive: "m/48h/\(coinType)h/\(account)h/1h", addressType: .legacy)
        }
    }
}

nonisolated struct WordQuizRound: Equatable, Sendable {
    var wordIndex: Int
    var choices: [String]
    var remaining: [Int]
}

nonisolated struct StoredWalletRecord: Codable, Equatable, Sendable {
    var formatVersion = 2
    var mnemonic: String
    var network: BitcoinNetwork
    var nickname: String
    var pinSalt: Data
    var pinHash: Data
    var notes: [SecureNote]
    var createdAt: Date
    var preferences: SimulatorPreferences
    /// Firmware SE `num_fails`; survives process death like the secure element counter.
    var failedPINAttempts = 0
    var isBricked = false
    /// Master secret stored as an extended private key instead of BIP-39 words.
    var extendedPrivateKey: String? = nil
    /// Firmware `settings['xfp']` shown on the status line even while locked.
    var settingsXFP: String? = nil
    /// Firmware settings key `wifs`: compressed pubkey hex + privkey hex pairs.
    var wifKeys: [WIFStoreItem] = []
    /// Firmware SE2 trick-PIN slots (`trick_pins.py` settings key `tp` plus slot secrets).
    var trickPins: [TrickPinSlot] = []

    var hasSeed: Bool {
        !mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(extendedPrivateKey ?? "").isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, mnemonic, network, nickname, pinSalt, pinHash, notes, createdAt
        case preferences, failedPINAttempts, isBricked, extendedPrivateKey, settingsXFP, wifKeys, trickPins
    }

    init(formatVersion: Int = 2, mnemonic: String, network: BitcoinNetwork, nickname: String,
         pinSalt: Data, pinHash: Data, notes: [SecureNote], createdAt: Date,
         preferences: SimulatorPreferences = SimulatorPreferences(),
         failedPINAttempts: Int = 0, isBricked: Bool = false,
         extendedPrivateKey: String? = nil, settingsXFP: String? = nil, wifKeys: [WIFStoreItem] = [],
         trickPins: [TrickPinSlot] = []) {
        self.formatVersion = formatVersion
        self.mnemonic = mnemonic
        self.network = network
        self.nickname = nickname
        self.pinSalt = pinSalt
        self.pinHash = pinHash
        self.notes = notes
        self.createdAt = createdAt
        self.preferences = preferences
        self.failedPINAttempts = failedPINAttempts
        self.isBricked = isBricked
        self.extendedPrivateKey = extendedPrivateKey
        self.settingsXFP = settingsXFP
        self.wifKeys = wifKeys
        self.trickPins = trickPins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        mnemonic = try container.decode(String.self, forKey: .mnemonic)
        network = try container.decode(BitcoinNetwork.self, forKey: .network)
        nickname = try container.decode(String.self, forKey: .nickname)
        pinSalt = try container.decode(Data.self, forKey: .pinSalt)
        pinHash = try container.decode(Data.self, forKey: .pinHash)
        notes = try container.decodeIfPresent([SecureNote].self, forKey: .notes) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        preferences = try container.decodeIfPresent(SimulatorPreferences.self, forKey: .preferences) ?? SimulatorPreferences()
        failedPINAttempts = try container.decodeIfPresent(Int.self, forKey: .failedPINAttempts) ?? 0
        isBricked = try container.decodeIfPresent(Bool.self, forKey: .isBricked) ?? false
        extendedPrivateKey = try container.decodeIfPresent(String.self, forKey: .extendedPrivateKey)
        settingsXFP = try container.decodeIfPresent(String.self, forKey: .settingsXFP)
        wifKeys = try container.decodeIfPresent([WIFStoreItem].self, forKey: .wifKeys) ?? []
        trickPins = try container.decodeIfPresent([TrickPinSlot].self, forKey: .trickPins) ?? []
    }
}

nonisolated struct WalletBackupPayload: Codable, Equatable, Sendable {
    var format = "coldcard-q-swift-simulator-backup/1"
    var mnemonic: String
    var network: BitcoinNetwork
    var nickname: String
    var notes: [SecureNote]
    var createdAt: Date
    // Firmware backs up every user setting and replays it on restore (backups.py).
    var preferences: SimulatorPreferences? = nil
    var wifKeys: [WIFStoreItem] = []
    var trickPins: [TrickPinSlot] = []
    var extendedPrivateKey: String? = nil
}

/// Clone archive stand-in: CryptoKit backup envelope plus the writer's compressed pubkey.
nonisolated struct SimulatorClonePackage: Codable, Equatable, Sendable {
    var format = "coldcard-q-swift-simulator-clone/1"
    var writerPubkeyHex: String
    var encryptedBackup: Data
}

nonisolated struct BackupEnvelope: Codable, Equatable, Sendable {
    var format = "coldcard-q-swift-simulator-encrypted/1"
    var kdf = "PBKDF2-HMAC-SHA256"
    var iterations: Int
    var salt: Data
    var sealedBox: Data
    /// Firmware 7z inner name `<bip39word><0-999>.txt` (or `.json` for notes).
    var innerFilename: String? = nil
}

/// LCD fill used by the Q selftest (`selftest.test_lcd` / `test_gpu`).
typealias SelftestFill = QSelftest.LCDFill

nonisolated enum ScanHandlingResult: Equatable, Sendable {
    case complete
    case continueScanning(String)
}

nonisolated struct QRPresentation: Identifiable, Equatable, Sendable {
    let id = UUID()
    var title: String
    var payloads: [String]
    var sensitive: Bool
    var captions: [String]

    init(title: String, payload: String, sensitive: Bool, captions: [String] = []) {
        self.title = title
        self.payloads = [payload]
        self.sensitive = sensitive
        self.captions = captions
    }

    init(title: String, payloads: [String], sensitive: Bool, captions: [String] = []) {
        self.title = title
        self.payloads = payloads.isEmpty ? [""] : payloads
        self.sensitive = sensitive
        self.captions = captions
    }

    var payload: String { payloads.first ?? "" }
    var pagesLabeledQR: Bool { !captions.isEmpty }
}

nonisolated struct StoryPresentation: Equatable, Sendable {
    var title: String
    var body: String
    var confirmCode: String? = nil
    var onConfirm: StoryConfirmAction? = nil
    var hintQR: Bool = false
    var hintNFC: Bool = false
}

nonisolated enum StoryConfirmAction: String, Equatable, Sendable {
    case enableSecureNotes
    case confirmPassphrase
    case savePassphrase
    case destroySeed
    case wipeSimulator
    case continuePINWarning
    case continueAddressExplorer
    case hideAddressExplorerIntro
    case continueRiskyPIN
    case retryPINConfirm
    case continueCustomPath
    case continueDice
    case deleteNote
    case verifySiblingHashes
    case reuseBackupPassword
    case cacheBackupPassword
    case skipBackupCache
    case backupFirstCopyWritten
    case backupMoreCopies
    case notesCustomPassword
    case enableSighashWarn
    case enableDeletePSBTs
    case enableKeyboardEMU
    case enableSeedVault
    case enableAEStartIndex
    case enableB85Unlimited
    case clearOVCache
    case clearAddressCache
    case approveMessageSign
    case continueExport
    case exportPickAccount
    case descriptorIntExt
    case openKeyExpressionMenu
    case messageChange
    case signedMessageExport
    case signedMessageQR
    case simpleTextQR
    case continuePassphrase
    case continueViewSeedWords
    case continueExportSeedQR
    case applyMainnet
    case openTemporarySeed
    case exportCleartext
    case addToSeedVault
    case skipVaultSave
    case continueAfterVaultSave
    case deleteVaultSeedConfirm
    case uxAborted
    case continueMash
    case continueCoin
    case continueDiceRolling
    case skipQuiz
    case throwAwayWords
    case abortDice
    /// Mix-in dice/coin bias: untitled `bad_msg`, then back to the method menu (`seed.py`).
    case entropyBiasRetry
    case beginChangePINOld
    case enableCalculatorLogin
    case confirmPasswordChange
    case exportNotesFile
    case importNotesSource
    case notesCustomPWD
    case beginNickname
    case confirmNoteEdits
    case exportNotesSignature
    case batchSignConfirm
    /// After a signed export in `_batch_sign`, dismiss the filename story and show the next file.
    case batchSignAfterExport
    /// Firmware `_batch_sign` `import_export_prompt("PSBTs", is_import=True, no_nfc=True, no_qr=True)`.
    case batchSignImport
    case destroySeedAgain
    case nukeDeviceBrick
    case confirmRestoreBackup
    case confirmDeleteSavedPassphrase
    case restoreMasterConfirm
    case restoreMasterPreserve
    case applyTestnet
    case applyRegtest
    case xorSplitParts
    case xorSplitRNG
    case xorRestoreWordCount
    case xorRestoreInclude
    case xorRestoreVault
    case xorRestoreMore
    case xorShowParts
    case xorStopForgetSplit
    case xorAbortRestore
    case bip85Reveal
    case bip85Intro
    case confirmBIP85TmpSeed
    case showXPUBQR
    case acceptTerms
    case continueAfterBag
    case continuePINPrefix
    case continueToggleChooser
    case pickScramble
    case pickKillKey
    case abortWordEntry
    case lockDownSeed
    case continuePushtxSetup
    case enableNFCForFeature
    case retryPushtxURLEdit
    case continuePushTxnPicker
    case pickPushTxnFromFiles
    case enrollImportedMultisig
    case nfcShowAddress
    case nfcVerifiedAddress
    case nfcToolsStandIn
    case pasteNFCSeed
    case continueSelftest
    case shipWithoutBag
    case resumeBagScan
    case openDeveloperMenu
    case openSerialREPL
    case reflashGPU
    case bkpwOverride
    case bkpwDelete
    case bkpwShow
    case warmResetAfterCrash
    case formatRamDisk
    case formatSDCard
    case listedFileDetail
    case listedFileRestoreDetail
    case ssspEnable
    case ssspActivate
    case ssspTestDrive
    case ssspRemove
    case ssspToggleWords
    case ssspToggleNotes
    case ssspToggleRelatedKeys
    case cccEnable
    case cccGenerateKeyC
    case cccImportKeyC12
    case cccImportKeyC24
    case cccImportKeyCVault
    case cccRemove
    case cccRemoveFunds
    case disableWeb2FA
    case enableWeb2FA
    case cloneStartWriteKey
    case cloneIngestPickFile
    case cloneWriteConfirmTmp
    case cloneWritePickStart
    case tapsignerImportSource
    case importXPRVSource
    case tapsignerHaveCard
    case tapsignerRetryKey
    case enableNFCFor2FA
    case cccProceedWithoutSignature
    case cccLoadKeyC
    case cccBuild2ofN
    case cccVaultReminder
    case openWIFStore
    case deleteWIF
    case clearAllWIF
    case importVisualizedWIF
    case wifImportPrompt
    case wifSignImport
    case trickDismiss
    case trickSaveProposed
    case trickOpenWipeMenu
    case trickOpenDuressMenu
    case trickOpenDuressAfterWipe
    case trickOpenCountdownMenu
    case trickContinueAddIfWrong
    case trickConfirmDeleteAll
    case trickConfirmDeleteAllDuress
    case trickConfirmDelete
    case trickConfirmHide
    case trickConfirmActivate
    case trickConfirmDeleteAllPolicy
    case trickDuressDetails
    case trickCountdownDetails
    case openPaperWallets
    case paperWalletSave
    case paperWalletDone
    case keyTeleportReusePubkey
    case keyTeleportSendWarning
    case keyTeleportShareMaster
    case keyTeleportShareBackup
    case keyTeleportShowPayload
    case keyTeleportRetryPassword
    case keyTeleportPickPSBTFile
    case enrollMicroSD2FA
    case removeMicroSD2FA
    case continueTrustPSBT
    case continueSkipChecks
    case continueUnsortedMultisig
    case continueExportXPUB
    case continueElectrumExport
    case addOwnAirgappedKey
    case showPendingMultisigXpubs
    case importMultisigPrompt
    case createAirgappedSource
    case createAirgappedFormat
    case exportPrettyDescriptor
    case confirmDeleteMultisig
    case none
}

nonisolated struct ExportPayload: Equatable, Sendable {
    var data: Data = Data()
    var filename: String = "coldcard-export"
    var contentTypeIdentifier: String = "public.data"
}

nonisolated struct SimulatorMenuItem: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String? = nil
    var checked = false
    var simulatorOnly = false
    var action: SimulatorMenuAction

    /// Paper wallet address format is a firmware `chooser=` on the row, not a submenu.
    var isPaperWalletFormatChooser: Bool {
        if case .command(.setPaperWalletSegwit) = action { return true }
        return false
    }
}

nonisolated enum SimulatorMenuAction: Equatable, Sendable {
    case openMenu(FirmwareMenu)
    case command(SimulatorCommand)
}

/// Address-list export destinations from `export_prompt_builder('address summary file')`.
nonisolated enum AddressExportDestination: Equatable, Sendable {
    /// (1) SD Card → Files picker.
    case sdCard
    /// (B) lower physical slot → Documents/MicroSD stand-in.
    case lowerSlot
    /// (2) Virtual Disk folder when VD is on.
    case virtDisk
}

nonisolated enum SimulatorCommand: Equatable, Sendable {
    case officialDemo
    case choosePIN
    case bagNumber
    case bagMeNow
    case shipWithoutBag
    case factoryDFU
    case readyToSign
    case nfcSignPSBT
    case signAllReadyToSign
    case signReadyToSignPSBT(String)
    case scanAnyQR
    case secureLogout
    case viewIdentity
    case selftest
    case generateSeed(Int)
    case diceSeed(Int)
    case importWords(Int)
    case restoreBackup
    case restoreBackupBlocked
    case enableSecureNotes
    case viewSeedWords
    case exportSeedQR
    case destroySeed
    case lockDownSeed
    case nukeDevice
    case setNetwork(BitcoinNetwork)
    case setDisplayUnits(DisplayUnits)
    case setMaxFee(MaxNetworkFee)
    case setDeletePSBTs(Bool)
    case setKeyboardEMU(Bool)
    case setMenuWrapping(Bool)
    case setCalculatorLogin(Bool)
    case setSighashChecks(warnOnly: Bool)
    case clearOVCache
    case clearAddressCache
    case setAEStartIndex(Bool)
    case setAlwaysShowHomeXFP(Bool)
    case changeMainPIN
    case setNickname
    case testLoginNow
    case microSD2FAAddCard
    case microSD2FACheckCard
    case microSD2FARemoveCard(String)
    case backupSystem
    case verifyBackup
    case cloneColdcard
    case cloneStart
    case importTapsignerBackup
    case importXPRV
    case signTextFile
    case batchSignPSBT
    case listFiles
    case inspectListedFile(String)
    case verifySigFile
    case shareFileQR(bbqr: Bool)
    case pickAddressType(AddressType)
    case changeAccount
    case customPath
    case keypathDeeper(String)
    case keypathDone(String)
    case applicationWasabi
    case samouraiPostmix
    case samouraiPremix
    case changeStartIndex
    case export(WalletExportKind)
    case pickExportAddressType(AddressType)
    case pickMessageAddressType(AddressType)
    case pickCustomPathFormat(AddressType)
    case restoreMaster
    case beginKeyExpression
    case newNote
    case newPassword
    case exportAllNotes
    case sortNotes
    case importNotes
    case openNote(UUID)
    case viewNote
    case viewPassword
    case disableSecureNotes
    case applyNotePassphrase
    case openNoteGroup(String)
    case pickNoteGroup(String)
    case newNoteGroup
    case generateNotePassword(Int)
    case editNote
    case changeNotePassword
    case deleteNote
    case exportNote
    case signNote
    case editPhrase
    case restoreSavedPassphrase(UUID)
    case deleteSavedPassphrase(UUID)
    case openSavedPassphrase(UUID)
    case sendPassword
    case showVersion
    case keyExpressionCustomPath
    case signMessageFromAddress
    case generateEphemeralSeed(Int)
    case diceEphemeralSeed(Int)
    case importEphemeralWords(Int)
    case scanEphemeralQR
    case setSeedVault(Bool)
    case signMessage
    case explorePSBTInputs
    case explorePSBTOutputs
    case exportAddressCSV
    /// Address-list export: (1) Files/SD, (B) Documents lower-slot stand-in, (2) VirtDisk.
    case mashEntropy
    case coinEntropy
    case diceMixEntropy
    case addCurrentTmpToVault
    case useVaultSeed(UUID)
    case deleteVaultSeed(UUID)
    case renameVaultSeed(UUID)
    case openVaultSeed(UUID)
    case showVaultSeedDetail(UUID)
    case menuCancel
    case xorSplit
    case xorRestore
    case drvEntro
    case drvEntroKind(Int)
    case typePasswords
    case setScrambleKeys(Bool)
    case setKillKey(String)
    case setLoginCountdown(Int)
    case setB85Unlimited(Bool)
    case setIdleTimeout(Int)
    case setIdleTimeoutBattery(Int)
    case setNFCSharing(Bool)
    case setUSBPort(Bool)
    case setVirtualDisk(Int)
    case formatRamDisk
    case formatSDCard
    case nfcFileShare
    case importEphemeralNFC
    case nfcShowAddress
    case nfcVerifyAddress
    case nfcImportMultisig
    case nfcPushTransaction
    case setPushtxURL(String?)
    case editPushtxURL
    case keyboardTest
    case bbqrDemo
    case nfcTest
    case clearTested
    case debugAssert
    case debugExcept
    case checkFirewallRead
    case serialREPL
    case reflashGPU
    case warmReset
    case restoreDeveloperBackup
    case bkpwOverride
    case unimplemented(String)
    /// Firmware `MenuItem` with no handler (title-only / already-chosen no-op).
    case menuNoop
    case openSSSP
    case openCCC
    case ssspEditPolicy
    case ssspWordCheck
    case ssspAllowNotes
    case ssspRelatedKeys
    case ssspLastViolation
    case ssspRemovePolicy
    case ssspTestDrive
    case ssspActivate
    case exitTestDrive
    case setSpendingMagnitude
    case setSpendingVelocity
    case pickSpendingVelocity(Int)
    case openSpendingWhitelist
    case scanWhitelistQR
    case importWhitelistFile
    case clearSpendingWhitelist
    case inspectWhitelistAddress(String)
    case deleteWhitelistAddress(String)
    case toggleSpendingWeb2FA
    case testSpending2FA
    case enrollMore2FA
    case cccShowIdent
    case cccExportXPUBs
    case cccBuild2ofN
    case cccLoadKeyC
    case cccRemove
    case cccLastViolation
    case cccResetBlockHeight
    case importWIF
    case openWIFItem(Int)
    case wifDetail
    case wifDescriptors
    case wifAddresses
    case wifSignMSG
    case deleteWIF
    case exportAllWIF
    case clearAllWIF
    case trickAddNew
    case trickAddIfWrong
    case trickDeleteAll
    case openTrickPIN(String)
    case trickHide
    case trickDelete
    case trickChangePIN
    case trickActivateWallet
    case trickDuressDetails
    case trickCountdownDetails
    case trickPickAction(String, UInt16, UInt16)
    case trickOpenWipeMenu
    case trickOpenDuressMenu(Bool)
    case trickOpenCountdownMenu
    case setTrickCountdown(Int)
    case startPaperWallets
    case pickPaperWalletPDF
    case setPaperWalletSegwit(Bool)
    case paperWalletUseDice
    case generatePaperWallet
    case selectPaperWalletTemplate(String)
    case keyTeleportStart
    case teleportMultisigPSBT
    case keyTeleportQuickNote
    case keyTeleportPickNote(UUID)
    case keyTeleportExportAllNotes
    case keyTeleportPickVault(UUID)
    case keyTeleportShareMaster
    case keyTeleportShareBackup
    case keyTeleportPickCosigner(String)
    case keyTeleportSignSelf
    case noneSetupYet
    case openMultisigWallet(Int)
    case importMultisig
    case exportMultisigXPUB
    case createAirgapped
    case trustPSBTMenu
    case skipChecksMenu
    case fullAddressViewMenu
    case unsortedMultisigMenu
    case setTrustPSBT(Int)
    case setSkipChecks(Bool)
    case setFullAddressView(Bool)
    case setUnsortedMultisig(Bool)
    case viewMultisigDetail
    case renameMultisig
    case deleteMultisig
    case exportMultisigColdcard
    case exportMultisigElectrum
    case viewMultisigDescriptor
    case exportMultisigDescriptor
    case exportMultisigBitcoinCore
    case exploreMultisig(Int)
}

enum SecureNotesSupport {
    static let oneLineLimit = SecureNotes.oneLineLimit
    static let passwordLimit = SecureNotes.passwordLimit

    static func titleForScannedText(_ got: String) -> String {
        SecureNotes.titleForScannedText(got)
    }
}

enum FirmwareCopy {
    static let okKey = "ENTER"
    static let cancelKey = "CANCEL"
    static let pinPrefixPrompt = LoginUX.pinPrefixPrompt
    static let pinSuffixPrompt = LoginUX.pinSuffixPrompt
    static let confirmPINValue = LoginUX.confirmPINFooter
    static let choosePIN = LoginUX.choosePINStory
    static let changeMainPIN = """
    You will be changing the main PIN used to unlock your Coldcard.

    THERE IS ABSOLUTELY NO WAY TO RECOVER A FORGOTTEN PIN!

    Write it down.
    """
    static let wrongOldPIN = "You provided an incorrect value for the existing PIN."
    static let nicknameIntro = "You can give this Coldcard a nickname and it will be shown before login."
    static let scrambleKeysIntro = "When entering PIN, randomize the order of the key numbers, so that cameras and shoulder-surfers are defeated."
    static let killKeyIntro = "If you press this key at any point during login, your seed phrase will be immediately wiped."
    static let microSD2FASimulatorNote = "This simulator uses a .2fa file in Documents/MicroSD as the card. The Files picker can insert a token saved elsewhere."
    static var microSD2FAIntro: String {
        MicroSD2FA.introStory(includeQExtra: true) + "\n\n" + microSD2FASimulatorNote
    }
    static let usbPortStory = "Blocks any data over USB port. Useful when your plan is air-gap usage."
    static let virtualDiskStory = """
    Coldcard can emulate a virtual disk drive (4MB) where new PSBT files can be saved. Signed PSBT files (transactions) will also be saved here.

    In "auto" mode, selects PSBT as soon as written.
    """
    /// Firmware `wipe_vdisk` confirm (`actions.py`).
    static let formatRamDisk = "Erases and reformats shared RAM disk. This is a secure erase that blanks every byte."
    /// Firmware `wipe_sd_card` confirm (`actions.py`).
    static let formatSDCard = "Erases and reformats MicroSD card. This is not a secure erase but more of a quick format."
    /// Firmware `file_picker` empty result (`actions.py`).
    static let noSuitableFiles = "No suitable files found. \n\nMaybe insert (another) SD card and try again?"
    static let listedFileRenameFailedPrefix = "Failed to rename the file. "
    /// Firmware `ux_input_text` default prompt (`ux_q1.py`).
    static let uxInputTextPrompt = "Enter value"
    /// Firmware `ux_input_text` min_len error (`ux_q1.py`).
    static func uxInputTextNeedCharacters(_ minLen: Int) -> String {
        "Need \(minLen) characters at least."
    }
    /// Firmware short `ux_input_text` footer when `num_lines <= 2` (`ux_q1.py`).
    static let uxInputTextDoneFooter = "CANCEL or ENTER when done."
    static let nfcSharingStory = """
    NFC (Near Field Communications) allows a phone to "tap" to send and receive data with the Coldcard.
    """
    static let pushTxIntro = """
    When this is enabled, immediately after transaction signing, you can tap any NFC-enabled phone on the COLDCARD and your newly-signed transaction will be immediately broadcast on the public network.

    You must choose a provider by URL here, or give your own URL.

    Your phone's IP address vs. transaction details could be linked by the service. Make sure your phone is not in airplane mode. Requires NFC.
    """
    static let nfcRequiredToEnable = "This feature requires NFC to be enabled. ENTER to enable."
    static let nfcStandInHint = "Core NFC is not available on this device. Files and paste are the iOS stand-in. The phone still cannot emulate a Coldcard-style tag."
    static let nfcSeedStandIn = """
    Core NFC is not available on this device. Files and paste are the iOS stand-in. The phone still cannot emulate a Coldcard-style tag.

    ENTER to paste seed words, (1) to import a file.
    """
    static let nfcTapPrompt = "Tap phone to screen, or CANCEL."
    static let nfcTxnTooLarge = "Transaction is too large to share via NFC"
    static let nfcPSBTTooLarge = "PSBT is too large to share via NFC"
    static let nfcSeedImportFailedPrefix = "Failed to import temporary seed via NFC.\n\n"
    static let nfcSeedMissing = "Unable to find seed words"
    static let nfcAddressPathMissing = "Expected address and derivation path."
    static let nfcAddressMissing = "Unable to find address from NFC data."
    static let nfcMultisigMissing = "Unable to find multisig descriptor."
    static let noMultisigYet = "You don't have any multisig wallets yet."
    static let needSeedForMultisig = "You must have wallet seed before creating multisig wallets."
    static let trustPSBT = """
    This setting controls what the Coldcard does \
    with the co-signer public keys (XPUB) that may \
    be provided inside a PSBT file. Three choices:

    - Verify Only. Do not import the xpubs found, but do \
    verify the correct wallet already exists on the Coldcard.

    - Offer Import. If it's a new multisig wallet, offer to import \
    the details and store them as a new wallet in the Coldcard.

    - Trust PSBT. Use the wallet data in the PSBT as a temporary,
    multisig wallet, and do not import it. This permits some \
    deniability and additional privacy.

    When the XPUB data is not provided in the PSBT, regardless of the above, \
    we require the appropriate multisig wallet to already exist \
    on the Coldcard. Default is to 'Offer' unless a multisig wallet already \
    exists, otherwise 'Verify'.
    """
    static let skipChecks = """
    With many different wallet vendors and implementors involved, it can \
    be hard to create a PSBT consistent with the many keys involved. \
    With this setting, you can \
    disable the more stringent verification checks your Coldcard normally provides.

    USE AT YOUR OWN RISK. These checks exist for good reason! Signed txn may \
    not be accepted by network.

    This settings lasts only until power down.

    Press (4) to confirm entering this DANGEROUS mode.
    """
    static let unsortedMultisig = """
    Enable this to allow import and operation with "multi(...)" unsorted multisig wallets that DO NOT follow BIP-67. It is of CRUCIAL importance to backup multisig descriptor for unsorted wallets in order to preserve key ordering. Many popular wallets like Sparrow and Electrum do NOT support "multi(...)".

    USE AT YOUR OWN RISK. Disabling BIP-67 is discouraged!

    Press (4) to confirm allowing "multi(...)"
    """
    static let fullAddressView = "When enabled, full multisig addresses are shown without censorship. You MUST verify all addresses with your coordinator software, BEFORE sending to them, because COLDCARD cannot know if other co-signers will accept the address."
    static let createAirgappedSD = """
    Insert SD card (or eject SD card to use Virtual Disk) with exported XPUB files from at least one other Coldcard. A multisig wallet will be constructed using those keys and this device.

    Default is P2WSH addresses (segwit) or press (1) for P2SH-P2WSH.
    """
    static func deleteMultisig(_ name: String) -> String {
        "Delete this multisig wallet (\(name))?\n\nFunds may be impacted."
    }
    static func unsortedMustRemove(_ names: [String]) -> String {
        let listed = "[" + names.map { "'\($0)'" }.joined(separator: ", ") + "]"
        return "Remove already saved multi(...) wallets first.\n\n\(listed)"
    }
    static func exportMultisigXPUB(coinType: UInt32) -> String {
        """
        This feature creates a small file containing \
        the extended public keys (XPUB) you would need to join \
        a multisig wallet.

        Public keys for BIP-48 conformant paths are used:

        P2SH-P2WSH:
           m/48h/\(coinType)h/{acct}h/1h
        P2WSH:
           m/48h/\(coinType)h/{acct}h/2h

        ENTER to continue. CANCEL to abort.
        """
    }
    static func electrumExport(_ background: String) -> String {
        "This saves a skeleton Electrum wallet file. You can then open that file in the wallet without ever connecting this Coldcard to a computer.\n"
            + background
            + sensitiveNotSecret
    }
    /// Firmware `nfc.start_msg_sign` filter failure (`nfc.py`). Typo is upstream.
    static let nfcSignMessageMissing = "Unable to find correctly formated message to sign."
    /// Firmware `NFC.verify_sig_nfc` filter failure (`nfc.py`).
    static let nfcSignedMessageMissing = "Unable to find signed message."
    static let nfcNoTagData = "No tag data was written?"
    static let nfcShowAddressFailed = "Failed to show address.\n\n"
    static let nfcVerifyFailed = "Ownership search failed.\n\n"
    static let nfcImportFailed = "Failed to import.\n\n"
    static let showAddressCompare = "Compare this payment address to the one shown on your other, less-trusted, software."
    static let nfcSavedPause = "Saved."
    static let nfcToolsStandIn = """
    Core NFC is not available on this device. Files and paste are the iOS stand-in. The phone still cannot emulate a Coldcard-style tag.

    ENTER to paste, (1) to import a file, QR to scan.
    """
    static let nfcTxnMissing = "Unable to find any suitable files for this operation. The filename must end in txn."
    static let enterPushtxURL = "Enter URL"
    static let pushTxTooBig = "too big"
    static let pushTxHTTPHint = "This simulator sends HTTP(S) GET to your ptxurl (Testnet appends &n=XTN). It does not emulate a Coldcard-style NFC tag."
    static let homeMenuXFPStory = """
    Forces display of XFP (seed fingerprint) at top of main menu. Normally, XFP is shown only when temporary seed is active.

    Master seed is displayed as <XFP>, temporary seeds as [XFP].
    """
    static let menuWrappingStory = "When enabled, allows scrolling past menu top/bottom (wrap around). By default, this only happens in menus whose length is greater than 10."
    static let termsOfSale = """
    By using this product, you are accepting our Terms of Sale and Use.

    Read the full document at:
      coldcard.com/legal

    Press ENTER to accept terms and continue.
    """
    static let wordEntryAbort = SeedCreation.wordEntryAbort
    static let scanAnyQRPrompt = "Scan any QR code, or CANCEL"
    static let scanSecretQRPrompt = "Scan XPRV or Seed Words, or CANCEL"
    static let loginCountdownTitle = LoginUX.countdownTitle
    static let loginCountdownMustWait = LoginUX.countdownMustWait
    static let identityQRHint = "Press QR to show QR code of xpub."
    static let identityTemporarySeed = "Temporary seed is in effect."
    static let identityPassphrase = "BIP-39 passphrase is in effect."
    static let xprvImportFailed = "Sorry, wasn't able to find a valid extended private key to import. It should be at the start of a line, and probably starts with 'xprv'."
    static let importedXPRVOrigin = FirmwareImportPrompt.importedXPRVOrigin
    static let scanXPRVPrompt = FirmwareImportPrompt.scanXPRVPrompt
    static let xprvNFCMissing = FirmwareImportPrompt.xprvNFCMissing
    static let xprvFileNoneMsg = FirmwareImportPrompt.xprvFileNoneMsg
    static func xprvImportPrompt(virtualDiskEnabled: Bool, nfcEnabled: Bool) -> String {
        FirmwareImportPrompt.qImportPrompt(
            title: FirmwareImportPrompt.extendedPrivateKeyFileTitle,
            slotBOnly: false,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: nfcEnabled
        )
    }
    static let selftestPass = QSelftest.passBody
    static let selftestFailPrefix = "Test failed:\n"
    static let mainnetNotHardwareWallet = "MAINNET does not make this app a hardware wallet. Do not protect real funds with it."
    /// Firmware `ux._import_prompt_builder` for Q Ready To Sign (`slot_b_only=True`).
    /// Simulator (B) is the Files stand-in for lower-slot MicroSD; copy stays Q wording.
    static func psbtEmptyImportPrompt(virtualDiskEnabled: Bool, nfcEnabled: Bool) -> String {
        FirmwareImportPrompt.qImportPrompt(
            title: "PSBT",
            slotBOnly: true,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: nfcEnabled
        )
    }
    static let bip85ExportPrompt = "Press (1) to save data to SD Card, QR to show QR code, (0) to switch to derived secret."
    static let bip85ExportPromptNoSwitch = "Press (1) to save data to SD Card, QR to show QR code."
    static var lockDownSeed: String {
        SeedDanger.lockDownConfirmBody(isPassphraseWallet: false, masterHasWords: true, currentHasWords: true)
    }
    static let mashCollectPrompt = SeedCreation.mashPrompt
    static let mashCollectDone = SeedCreation.mashDone
    static let diceCollectPrompt = SeedCreation.diceMixPrompt
    static let diceCollectDone = SeedCreation.diceMixDone
    static let coinCollectPrompt = SeedCreation.coinPrompt
    static let coinCollectDone = SeedCreation.coinDone
    static var passphraseApplyFooter: String { BIP39Passphrase.applyFooter }
    static let restoreBackupAsMaster = "Above is the master fingerprint of the seed stored in the backup. Press ENTER to continue, and load backup as master seed. Press CANCEL to abort."
    static let restoreBackupAsTemporary = "Above is the master fingerprint of the seed stored in the backup. Press ENTER to continue, and load backup as temporary seed. Press CANCEL to abort."
    static let entropyStartFromStory = "Press ENTER to start, CANCEL to exit."
    static let calculatorLogin = "Boots into calculator mode. Enter your PIN as formula to login, or 12- to see prefix words. Normal calculator math works too."
    static let notesExportFootnotes = SecureNotes.qrExportWarning
    static let notesCleartextWarning = SecureNotes.cleartextConfirm
    static let notesCleartext = notesCleartextWarning
    static let notesDelete = "Everything about this note/password will be lost."
    static let brickCalculator = LoginUX.brickCalculatorLine
    static let proveRead = """
    There is ABSOLUTELY NO WAY to 'reset the PIN' or 'factory reset' the Coldcard if you forget the PIN.

    DO NOT FORGET THE PIN CODE.

    Press (6) to prove you read to the end of this message.
    """
    static let pinMismatch = """
    You gave two different PIN codes and they don't match.

    Press (2) to try the second one again, CANCEL to give up for now.
    """
    static let diceOnlyWarning = """
    These dice rolls will be the only source of randomness for your seed. No hardware-generated randomness is mixed in.

    The hash shown while rolling is SECRET. Anyone who sees or photographs the final hash can recreate your wallet and steal the funds.

    Keep the screen hidden from people and cameras. If you verify the hash elsewhere, use only a trusted offline device and erase all traces afterward.
    """
    static let entropyStartPrompt = "Press ENTER to start, CANCEL to exit."
    static let entropyContinuePrompt = "Press ENTER to continue, CANCEL to exit."
    static let mashEntropyTitle = "Mash Keys"
    static let coinEntropyTitle = "Coin Flips"
    static let diceMixEntropyTitle = "Dice Rolls"
    static let diceOnlyWarningTitle = "WARNING"
    /// Firmware `seed.py` `new_from_dice` vs `generate_seed_with_user_entropy` story + OK/X prompt.
    static func diceEntropyWarning(mixWithTRNG: Bool) -> (title: String, body: String) {
        if mixWithTRNG {
            return (diceMixEntropyTitle, diceMixEntropy + "\n\n" + entropyStartPrompt)
        }
        return (diceOnlyWarningTitle, diceOnlyWarning + "\n\n" + entropyContinuePrompt)
    }
    static var mashEntropyStory: String { mashEntropy + "\n\n" + entropyStartPrompt }
    static var coinEntropyStory: String { coinEntropy + "\n\n" + entropyStartPrompt }
    static let badDice = SeedCreation.badDiceMessage
    static let skipQuizConfirm = "Skipping the quiz means you might have recorded the seed wrong and will be crying later."
    static let throwAwayWords = "Throw away those words and stop this process?"
    static let throwAwayQuiz = "Throw away those words and stop this process? Press CANCEL to see the word list again and restart the quiz."
    static let skipQuizHint = SeedCreation.skipQuizHint
    static let signTextFileHint = "Must be txt file with one msg line, optionally followed by a subkey derivation path on a second line and/or address format on third line. JSON msg signing format also supported"
    static let descriptorIntExt = "To export receiving and change descriptors in one descriptor (<0;1> notation) press ENTER, press (1) to export receiving and change descriptors separately."
    static let keyExpressionIntro = "This saves a extended key expression."
    static let messageChange = "Press (0) to use internal/change address, ENTER to use external/receive address."
    static let signedMessageQR = "Press ENTER to export signature QR only, (0) to export full RFC template, CANCEL if done."
    /// Firmware `ux_visualize_textqr` (`ux_q1.py`).
    static func simpleTextQR(_ text: String) -> (title: String, body: String, canSign: Bool) {
        let vis = BitcoinMessageSigner.simpleTextQRDisplay(text)
        var body = "\(vis.shown)\n\nAbove is text that was scanned. "
        if vis.canSign { body += " Press (0) to sign the text. " }
        return ("Simple Text", body, vis.canSign)
    }
    static let seedWordsFooter = "Please check and double check your notes. There will be a test!"
    static func seedWordsNotes(ephemeral: Bool) -> String {
        ephemeral ? "Please check and double check your notes." : seedWordsFooter
    }
    static let quizGiveUp = SeedCreation.quizGiveUp
    static let disclaimerLicense = "Coldcard source/assets retain the Coinkite MIT + Commons Clause notice."
    static let psbtEmptyIntro = ReadyToSign.emptyIntro
    static let psbtEmptyFootnotes = ReadyToSign.emptyFootnotes
    static func psbtEmpty(virtualDiskEnabled: Bool, nfcEnabled: Bool) -> String {
        ReadyToSign.emptyStory(virtualDiskEnabled: virtualDiskEnabled, nfcEnabled: nfcEnabled)
    }
    static let psbtNoSuitableFiles = "Unable to find any suitable files for this operation. The filename must end in psbt."
    /// Q `_batch_sign` per-file prompt (`actions.py`): `OK`/`X` are ENTER/CANCEL.
    static func batchSignPrompt(filename: String) -> String {
        "Sign \(filename) ??\n\nPress \(okKey) to sign, (1) to skip this PSBT, \(cancelKey) to quit and exit."
    }
    static let nfcPSBTMissing = "Could not find PSBT in what was written."
    static let psbtEmptySimulatorNote = "Simulator mapping: Files app replaces lower-slot MicroSD (B). QR scans a PSBT. (2) reads Documents/VirtDisk when Virtual Disk is enabled."
    static func psbtApproveFooter(noun: String) -> String {
        PSBT.approvalFooter(noun: noun)
    }
    static let psbtApprove = psbtApproveFooter(noun: "transaction")
    static let brickNote = "This simulator cannot brick a secure element. Use Calculator Login from Login Settings before the attempt limit."
    static let addressExplorerIntro = """
    The following menu lists the first payment address produced by various common wallet systems.

    Choose the address that your desktop or mobile wallet has shown you as the first receive address.

    WARNING: Please understand that exceeding the gap limit of your wallet, or choosing the wrong address on the next screen may make it very difficult to recover your funds.

    Press (4) to start or (6) to hide this message forever.
    """
    static let sensitiveNotSecret = """
    The file created is sensitive--in terms of privacy--but should not compromise your funds directly.
    """
    static let pickAccount = "Press ENTER to continue. Press (1) to enter a non-zero account number."
    static let cacheBackupPassword = "Would you like to use these same words next time you perform a backup? Press (1) to save them into this Coldcard for next time."
    static let muchDangerCustomPathBody = """
    DO NOT DEPOSIT to this address unless you are 100% certain that some other software will be able to generate a valid PSBT for signing the UTXO, and also that specific path details will not get lost.

    This is for gurus only! You may have created a Bitcoin blackhole.

    Press (3) if you really understand and accept these risks.
    """
    static let platformLimit = "Not available on iOS. See README Deliberate limitations."
    static let nfcSessionUnavailable = "This device cannot start an NFC reader session. On a physical iPhone the same NDEF text record is written to a tag."
    static let temporarySeedWarning = """
    Temporary seed is a secret completely separate from the master seed, typically held in device RAM and not persisted between reboots in the Secure Element. Enable the Seed Vault feature to store these secrets longer-term.
    """
    static let viewSeedWordsWarning = """
    The next screen will show the secret seed words (or extended private key).

    Anyone with knowledge of the secret can control all funds in this wallet.
    """
    static let destroySeedFirst = SeedDanger.destroyFirstBody
    static let destroySeedAgain = SeedDanger.destroyAgainBody
    static let nukeDeviceFirst = """
    Wipe Seed & Brick device? This will wipe the seed, purge all related settings, and makes ewaste from this device.
    """
    static let nukeDeviceBrick = """
    Brick device?

    By design, there is no way to reset or recover the secure element, and its contents become forever inaccessible.

    Press (1) to prove you read to the end of this message and accept all consequences.
    """
    static let nukeDeviceSimulatorNote = "Simulator: erases the local Keychain record instead of bricking hardware."
    static let exportSeedQRWarning = """
    The next screen will show the seed words in a QR code.

    Anyone with knowledge of those words can control all funds in this wallet.
    """
    static let messageSignFooter = "Press ENTER to continue, otherwise CANCEL to cancel."
    static let ftux = FirstTimeUX.story
    static let ftuxSimulatorNote = "On this iOS simulator those hardware ports do not exist; the message is shown for firmware fidelity."
    static let riskyPINFooter = "Press ENTER to continue, CANCEL to stop for now."
    static let mashEntropy = """
    Only the timing between presses is credited as entropy. Key choices are also mixed in, but are not counted, so repeating one key is valid. Do not enter a PIN or words.

    Each press after the first adds one timing gap, credited with two bits. Press at least 65 keys. You may keep mashing to add more timing entropy.

    Use unpredictable gaps when possible. After 65 presses, press ENTER/OK when done.
    """
    static let coinEntropy = """
    Physical coin flips will be mixed into the seed.

    Flip a real coin again before every entry. Press 1 for heads or 0 for tails. Do not alternate, choose results, or use an app or computer. Reflip unclear results.

    You must enter at least 128 coin flips.
    """
    static let diceMixEntropy = """
    Physical die rolls will be mixed into the seed.

    Use a real six-sided die and roll it again before every entry. Enter only the result shown. Do not make up rolls or use an app or computer. Reroll unclear or cocked rolls.

    You must enter at least 50 dice rolls.
    """
    static let badCoin = "Distribution of coin flips is not random. Heads or tails occurred more than 65% of the time."
    static let addToSeedVault = "Add to Seed Vault?"
    static var seedVaultOffer: String { SeedVaultMenuCopy.offer }
    static let deletePSBTsEnable = """
    PSBT files (on SDCard) will be blanked & deleted after they are used. The signed transaction will be named <TXID>.txn, so the file name does not leak information.

    MS-DOS tools should not be able to find the PSBT data (ie. undelete), but forensic tools which take apart the flash chips of the SDCard may still be able to find the data or filenames.
    """
    static let keyboardEMUEnable = """
    This mode adds a top-level menu item for typing deterministically-generated passwords (BIP-85), directly into an attached USB computer (as an emulated keyboard).
    """
    static var seedVaultEnable: String { SeedVaultMenuCopy.enableStory }
    static let sighashChecksEnable = """
    If you disable sighash flag restrictions, and ignore the warnings, funds can be stolen by specially crafted PSBT or MitM.

    Keep blocked unless you intend to sign special transactions.
    """
    static let testnetModeEnable = "Testnet must only be used by developers because correctly- crafted transactions signed on Testnet could be broadcast on Mainnet."
    static let aeStartIndexEnable = """
    Enable this option to add new menu item to Address Explorer allowing override of start index. By default start index is zero.

    WARNING: Some wallets will not recognize addresses that are past their gap limit and your deposits will seem to disappear.
    """
    static let b85UnlimitedEnable = """
    Allow unlimited indexes for BIP-85 derivations?

    DANGER: If you forget this index number, getting your funds back will be a difficult search problem.
    """
    static let enableSecureNotes = """
    Enable this feature to store short text notes and passwords inside the Coldcard.

    The notes are encrypted along with your other settings and will be backed-up with them.

    Press ENTER to enable and get started otherwise CANCEL.
    """
    static let bagNumberBody = """
    Your new Coldcard should have arrived SEALED in a bag with the above number. Please take a moment to confirm the number and look for any signs of tampering.

    Take pictures and contact support@coinkite if you have concerns.
    """
    /// Firmware `actions.show_bag_number` when `callgate.get_bag_number()` is empty.
    static let unbaggedTitle = "UNBAGGED!"
    /// Firmware `q1.scan_and_bag` scanner prompt.
    static let scanBagBarcodePrompt = "Scan barcode on new bag."
    static let cannotBagTitle = "Cannot Bag"
    static let cannotBagNotTested = "Not tested yet"
    static let cannotBagBadMode = "Bad mode"
    static let badScanTitle = "Bad Scan"
    static let putIntoBagAndSeal = "Put into bag and seal now."
    static let shipWithoutBagConfirm = "Not recommended! DO NOT USE for units going to paying customers."
    static let shipWithoutBagValue = "NOT BAGGED"
    static let noBagDoneTitle = "No Bag. DONE"
    /// Unix `machine.bootloader` / `start_dfu` one-way call.
    static let enterBootloaderDFU = "Enter bootloader (DFU)"
    /// Unix `version.get_mpy_version()[1]` / `docs/menu-tree.txt` Factory row.
    static let factoryVersionRel = "5.x.x"
    static var factoryVersionMenuTitle: String { "Version: \(factoryVersionRel)" }
    static let needClearSeed = """
    You must clear the wallet seed before restoring a backup because it replaces the seed value and the old seed would be lost.

    Visit the advanced menu and choose 'Destroy Seed'.
    """
    static let cloneStartInsert = """
    Insert a MicroSD card and press ENTER to start. A small file with an ephemeral public key will be written.
    """
    static let cloneKeepPower = """
    Keep power on this Coldcard, and take MicroSD card to source Coldcard. Select Advanced/Tools > Backup > Clone Coldcard to write to card. Bring that card back and press ENTER to complete clone process.
    """
    static let cloneFileNotFound = "Clone file not found. ENTER to try again, CANCEL to stop."
    static let cloneWriteNeedStart = """
    Start this process on the other Coldcard, which will write a file onto MicroSD card as the first step.

    Insert that card and try again here.
    """
    static let cloneWriteDone = """
    Done.

    Take this MicroSD card back to other Coldcard and continue from there.
    """
    static func cloneTmpInEffect(what: String, passphraseActive: Bool) -> String {
        let name = passphraseActive ? "BIP-39 passphrase" : "temporary seed"
        return "A \(name) is in effect, so \(what) will be of that seed."
    }
    static let tapsignerHaveCard = """
    Make sure to have your TAPSIGNER handy as you will need to provide 'Backup Password' from the back of the card in the next step.

    Press ENTER to continue CANCEL to cancel.
    """
    static let tapsignerKeyPrompt = "Backup Password (32 hex digits)"
    static func tapsignerImportPrompt(virtualDiskEnabled: Bool, nfcEnabled: Bool) -> String {
        FirmwareImportPrompt.qImportPrompt(
            title: "TAPSIGNER encrypted backup file",
            slotBOnly: false,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: nfcEnabled
        )
    }
    static let tapsignerNFCUnavailable = "Core NFC is unavailable here. Use Files or QR."
    static let tapsignerNoAESFile = "No TAPSIGNER backup (.aes) found."
    static let clearOVCache = """
    Clear history of segwit UTXO input values we have seen already. This data protects you against specific attacks. Use this only if certain a false-positive has occurred in the detection logic.
    """
    static let clearOVCacheSimulatorNote = "The simulator keeps no persistent outpoint-value history; nothing is stored between sessions."
    static let clearAddressCache = "Clear cached addresses used in ownership search. Harmless to erase, just costs time."
    static let diceNotEnoughRollsFooter = "Press ENTER to add more dice rolls. CANCEL to exit"
    /// Firmware `add_dice_rolls` when `enforce=True` (`new_from_dice`). Mix-in dice has no this story.
    static func diceOnlyNotEnough(count: Int, bits: Int, words: Int, needed: Int) -> String {
        """
        Not enough dice rolls!!!

        You only provided \(count) dice rolls, and each roll adds only 2.585 bits of entropy. For \(bits)-bit security, which is considered the minimum for \(words) word seeds, you need at least \(needed) rolls.

        \(diceNotEnoughRollsFooter)
        """
    }
    static let paperWalletIntro = """
    Coldcard will pick a random private key (which has no relation to your seed words), and record the corresponding payment address and private key (WIF) into a text file, creating a so-called "paper wallet".

    If you have a special PDF template file, it can also make a pretty version of the same data.

    Another option is to roll a D6 die many times to generate the key.

    CAUTION: Paper wallets carry MANY RISKS and should only be used for SMALL AMOUNTS.
    """
    static let paperWalletNoTemplates = """
    You don't have any PDF templates to choose from, but plain text wallet files can still be made. Visit the Coldcard website to get some interesting templates.
    """
    static let paperWalletSavePrompt = "Press (1) to save paper wallet file to SD Card, press (2) to save to VDisk."
    static let paperWalletSaveSDOnly = "Press (1) to save paper wallet file to SD Card."
    static func paperWalletDiceNotEnough(count: Int) -> String {
        """
        Not enough dice rolls!!!

        You only provided \(count) dice rolls, and each roll adds only 2.585 bits of entropy. For 256-bit security you need at least 99 rolls.

        \(diceNotEnoughRollsFooter)
        """
    }
    static var seedVaultDisableBlocked: String { SeedVaultMenuCopy.disableBlocked }
    static let bip85PassphraseWrap = "You have a BIP-39 passphrase set right now and so it will be wrapped into the new secret."
    static let bip85TmpSeedDerive = "You have a temporary seed active - deriving from temporary."
    static let ssspIntro = """
    You can define a "spending policy" which stops you from signing \
    transactions unless conditions are met.
    Spending policies can restrict: magnitude (BTC out), \
    velocity (blocks between txn), address whitelisting, \
    and/or require confirmation by 2FA phone app.

    When active, your COLDCARD \
    is locked into a special mode that restricts seed access, backups, settings and other features.

    First step is to define a new PIN code that is used when you want to bypass or \
    disable this feature.
    """
    static let cccIntro = """
    Adds an additional seed to your Coldcard, and enforces a "spending policy" whenever \
    it signs with that key. Spending policies can restrict: magnitude (BTC out), \
    velocity (blocks between txn), address whitelisting, and/or require confirmation by 2FA phone app.

    Assuming the use of a 2-of-3 multisig wallet, keys are as follows:

    A=Coldcard (master seed), B=Backup Key (offline/recovery), C=Spending Policy Key.

    Spending policy cannot be viewed or changed without knowledge of key C.
    """
    static let cccKeyCStory = """
    Press ENTER to generate a new 12-word seed phrase to be used \
    as the Coldcard Co-Signing Secret (key C).

    Or press (1) to import existing 12-words or (2) for 24-words import.
    """
    static let cccKeyCStoryWithVault = """
    Press ENTER to generate a new 12-word seed phrase to be used \
    as the Coldcard Co-Signing Secret (key C).

    Or press (1) to import existing 12-words or (2) for 24-words import. Press (6) to import from Seed Vault.
    """
    static let cccEnabledChallenge = "Spending policy cannot be viewed, changed nor disabled, unless you have the seed words for key C."
    static let cccVaultBypass = """
    You have a copy of the CCC key C in the Seed Vault, so \
    you may proceed to change settings now.

    You must delete that key from the vault once \
    setup and debug is finished, or all benefit of this feature is lost!
    """
    static let cccVaultLeaveReminder = "Key C is in your Seed Vault. If you are done with setup, you MUST delete it from the Vault!"
    static let cccWrongWords = "Sorry, those words are incorrect."
    static let ssspWrongWords = "Sorry, those words are incorrect."
    static let pinAlreadyInUsePrefix = "That PIN ("
    static let pinAlreadyInUseSuffix = ") is already in use. All PIN codes must be unique."
    static let ssspWordCheckStory = "To change Spending Policy, in addition to special PIN, you must provide the first and last seed words."
    static let ssspAllowNotesStory = "Allow (read-only) access to secure notes and passwords? Otherwise, they are inaccessible."
    static let ssspRelatedKeysStory = "Allow access to BIP-39 passphrase wallets based on master seed, and Seed Vault (read-only). Single Spending Policy applies to all."
    static let ssspRemoveConfirm = "Bypass PIN will be removed, and all spending policy settings forgotten."
    static let ssspTestDriveConfirm = "See what COLDCARD operation will look like with Spending Policy enabled."
    static let ssspNoBypassPIN = "You have no Spending Policy bypass PIN defined, so changes to this COLDCARD cannot be made past this point. Only option will be to destroy seed and reload everything."
    static let cccRemoveConfirm = "Key C will be lost, and policy settings forgotten. This unit will only be able to partly sign transactions. To completely remove this wallet, proceed to the multisig menu and remove related wallet entries."
    static let cccRemoveFunds = "Funds in related wallet/s may be impacted."
    static let cccLoadKeyCStory = "Loads the CCC controlled seed (key C) as a Temporary Seed and allows easy use of all Coldcard features on that key.\n\nIf you save into Seed Vault, access to CCC Config menu is quick and easy."
    static let cccBuild2ofNStory = """
    Builds simple 2-of-N multisig wallet, with this Coldcard's main secret (key A), \
    the CCC policy-controlled key C, and at least one other device, as key B.

    You will need to export the XPUB from another Coldcard and place it on an SD Card, or \
    be ready to show it as a QR, before proceeding.
    """
    static let web2FAStory = """
    When enabled, any spend (signing) requires \
    use of mobile 2FA application (TOTP RFC-6238). Shared-secret is picked now, \
    and loaded on your phone via QR code.

    WARNING: You will not be able to sign transactions if you do not have an NFC-enabled \
    phone with Internet access and 2FA app holding the correct shared-secret.
    """
    static let disableWeb2FAConfirm = "Disable web 2FA check? Effect is immediate."
    static let web2FADisabled = "Web 2FA has been disabled. If you re-enable it, a new secret will be generated, so it is safe to remove it from your phone at this point."
    static let nfcRequiredFor2FA = "This feature requires NFC to be enabled. ENTER to enable."
    static let velocityRequiresMagnitude = "Velocity limit requires a per-transaction magnitude to be set. This has been set to 1BTC as a starting value."
    static let whitelistMaxed = "Max 25 items in whitelist. Please make room first."
    static let whitelistClearConfirm = "Remove all addresses from the whitelist?"
    static let spendingPolicyUnlockNext = "Spending Policy Unlock: Please provide Main PIN next."
    static let cccProceedAnyway = "Will not add CCC signature. Proceed anyway?"
    static let spendingPolicyViolation = "Spending Policy violation."
    static let twoFAFailed = "2FA Failed"
    static let web2FACorrect = "Correct code was given."
    static let web2FAFailed = "Failed or aborted."
    static let web2FATitle = "Web 2FA"
    static let txMagnitudeTitle = "TX Magnitude"
    static let txMagnitudeUnchanged = "Did not change"
    static let txMagnitudeCleared = "No check for maximum transaction size will be done. "
    static let txMagnitudeClearedVelocity = "Velocity check also disabled. "
    static let ssspTitle = "Spending Policy"
    static let cccStoryTitle = "Coldcard Co-Signing"
    static let cccEnabledTitle = "CCC Enabled"
    static let reminderTitle = "REMINDER"
    static let lastViolationClearHint = "The most recent policy check failed because of:\n\n"
    static let lastViolationPress4 = "\n\nPress (4) to clear."
    static let cccLastViolationPress4 = "\n\nPress (4) to clear last fail reason."
    static let spendingPolicyDisabledWarning = "Spending Policy defined but disabled."
    /// Firmware `ux_q1.scan_anything` (`title='Sorry'`).
    static let spendingPolicyQRBlockedTitle = ScanAnything.hobbledBlockedTitle
    /// Firmware `ux_q1.scan_anything` hobbled rejection.
    static let spendingPolicyQRBlocked = ScanAnything.hobbledBlockedBody
    static let cccPolicyWarning = "Violates spending policy. Won't sign."
    static let alreadyInWhitelistPrefix = "Already in whitelist:\n\n"
    static func pinAlreadyInUse(_ pin: String) -> String {
        pinAlreadyInUsePrefix + pin + pinAlreadyInUseSuffix
    }
    static func txMagnitudeSet(_ rendered: String) -> String {
        "You have set the maximum per-transaction: \n\n  \(rendered)"
    }
    static func ssspActivateWithPIN(_ pin: String, wordCheck: Bool) -> String {
        var msg = "To return to normal unlimited spending mode, you will need to enter the special pin (\(pin)), then the Main PIN"
        if wordCheck { msg += ", followed by the first and last seed words" }
        return msg + "."
    }
    static func ssspLastViolation(height: UInt32?, reason: String) -> String {
        var msg = ""
        if let height { msg += "Last height:\n\n\(height)\n\n" }
        return msg + lastViolationClearHint + reason + lastViolationPress4
    }
    static func cccLastViolation(height: UInt32?, defaultHeight: UInt32, reason: String) -> String {
        var msg = ""
        var extra = ""
        if let height {
            msg += "CCC height:\n\n\(height)\n\n"
            if height != defaultHeight {
                extra = "Press (1) to clear block height. "
            }
        }
        return msg + lastViolationClearHint + reason + "\n\n" + extra + "Press (4) to clear last fail reason."
    }
    static func cccIdent(xfp: String, xpub: String) -> String {
        "Key C:\n\nXFP (Master Fingerprint):\n\n  \(xfp)\n\nMaster Extended Public Key:\n\n  \(xpub) "
    }
    static func whitelistAdded(_ addresses: [String]) -> String {
        if addresses.count == 1 {
            return "Added new address to whitelist:\n\n\(addresses[0])"
        }
        return "Added \(addresses.count) new addresses to whitelist:\n\n" + addresses.joined(separator: "\n")
    }
    static let wifStoreIntro = """
    Individual private keys, encoded as WIF (Wallet Import Format) keys can be imported and used for signing. Any PSBT that uses a WIF stored here will be signed as normal, but warning is shown. Remove all imported keys to disable WIF store signing
    """
    static let wifDeleteConfirm = "Delete WIF key?"
    static let wifClearAll = "Remove all saved WIF keys?"
    static let wifSaved = "Saved to WIF Store."
    static let wifImportManualKey0 = "to input WIF manually"
    static func wifImportPrompt(virtualDiskEnabled: Bool, nfcEnabled: Bool) -> String {
        var prompt = "Press (1) to import WIF private key from SD Card, (B) for lower slot"
        if virtualDiskEnabled {
            prompt += ", press (2) to import from Virtual Disk"
        }
        if nfcEnabled {
            prompt += ", press NFC to import via NFC"
        }
        prompt += ", QR to scan QR code, (0) \(wifImportManualKey0)."
        return prompt
    }
    static func wifSignImportPrompt(virtualDiskEnabled: Bool, nfcEnabled: Bool) -> String {
        var prompt = "Press (1) to import message from SD Card, (B) for lower slot"
        if virtualDiskEnabled {
            prompt += ", press (2) to import from Virtual Disk"
        }
        if nfcEnabled {
            prompt += ", press NFC to import via NFC"
        }
        prompt += ", QR to scan QR code, (0) to input message manually."
        return prompt
    }

    static let trickAddIfWrongIntro = """
    After N incorrect PIN attempts, this feature will be triggered. It can wipe the seed phrase, and/or brick the Coldcard. Regardless of this (or any other setting) the Coldcard will always brick after 13 failed PIN attempts.
    """
    static let trickBrickSelf = "Become a brick instantly and forever."
    static let trickWipeSeed = "Wipe the seed and maybe do more. See next menu."
    static let trickDuressWallet = "Goes directly to a specific duress wallet. No side effects."
    static let trickLookBlank = "Look and act like a freshly- wiped Coldcard but don't affect actual seed."
    static let trickJustReboot = "Reboot when this PIN is entered. Doesn't do anything else."
    static let trickDeltaMode = """
    Advanced! Logs into REAL seed and allows attacker to do most things, but will produce incorrect signatures when signing PSBT files. Wipes seed if they try to do certain actions that might reveal the seed phrase, but still a somewhat riskier mode.

    For this mode only, trick PIN must be same length as true PIN and differ only in final 4 positions (ignoring dash).
    """
    static let trickPolicyUnlock = "Adds (another?) Spending Policy unlock PIN."
    static let trickPolicyUnlockWipe = "Pretends correct Spending Policy unlock PIN given, but silently wipes seed before asking for main PIN."
    static let trickWipeReboot = "Seed is wiped and Coldcard reboots without notice."
    static let trickSilentWipe = "Seed is silently wiped and Coldcard acts as if PIN code was just wrong."
    static let trickWipeToWallet = "Seed is silently wiped, and Coldcard logs into a duress wallet. Select type of wallet on next menu."
    static let trickSayWipedStop = "Seed is wiped and a message is shown."
    static let trickWipeCountdown = "Seed is wiped at start of countdown."
    static let trickCountdownBrick = "Does the countdown, then system is bricked."
    static let trickJustCountdown = "Shows countdown, has no effect on seed."
    static let trickLegacyWallet = """
    Uses duress wallet created on Mk3 Coldcard, using a fixed derivation.

    Recommended only for existing UTXO compatibility.
    """
    static let trickWipeStopWrong = "Seed is wiped and a message is shown."
    static let trickLastChance = "Wipe seed, then give one more try and then brick if wrong PIN."
    static let trickWrongJustReboot = "Reboot when this happens. Doesn't do anything else."
    static let trickNeedSeedAndPIN = "Please set true PIN and wallet seed before creating trick pins."
    static let trickNotANewValue = "That isn't a new value"
    static func trickPINInUse(_ pin: String) -> String {
        "That PIN (\(pin)) is already in use. All PIN codes must be unique."
    }
    static let trickRememberedPIN = "Hmm. I remember that PIN now."
    static let trickDeleteAll = "Remove ALL TRICK PIN codes and special wrong-pin handling?"
    static let trickDeleteAllPolicy = "You will not be able to bypass spending policy anymore."
    static let trickDeleteAllDuress = "Any funds on the duress wallet(s) have been moved already?"
    static let trickHideDelta = """
    Delta mode PIN will be hidden if trick PIN menu is shown to attacker, and we need to update this record if the main PIN is changed, so we don't support hiding this item.
    """
    static let trickHidePolicy = "It will still be possible to change or disable the spending policy if this PIN is known."
    static let trickHideWrong = "This will hide what happens with wrong PINs from the menus but it will still be in effect."
    static func trickHidePIN(_ pin: String) -> String {
        """
        This will hide the PIN from the menus but it will still be in effect.

        You can restore it by trying to re-add the same PIN (\(pin)) again later.
        """
    }
    static let trickDeleteDuress = "Any funds on this duress wallet have been moved already?"
    static let trickDeletePolicy = "Changes to the spending policy will not be possible anymore."
    static let trickDeleteWrong = "Remove special handling of wrong PINs?"
    static func trickDeletePIN(_ pin: String) -> String {
        "Removing trick PIN:\n  \(pin)\n\nOk?"
    }
    static let trickActivateWallet = """
    This will temporarily load the secrets associated with this trick wallet so you may perform transactions with it.
    """
    static let trickSpendingUnlockNext = "Spending Policy Unlock: Please provide Main PIN next."
    static let trickWipedLockup = "Seed is wiped."
    static let trickSaved = "Saved."
    static let trickChanged = "Changed."
    static let trickWrongAttemptsTitle = "#of wrong attempts"
    static func trickLoginCountdown(_ label: String) -> String {
        "Pretends a login countdown timer (\(label)) is in effect. Can wipe seed or brick system or do nothing."
    }
    static func trickBIP85(_ wordCount: Int) -> String {
        let base = TrickPins.bip85IndexBase(wordCount: wordCount)
        return "This PIN will lead to a functional 'duress' wallet using seed words produced by the standard BIP-85 process. Index number is \(base + 1)...\(base + 3) for #1..#3 duress wallets. Same number of seed words as your true seed."
    }
    static func trickLegacyDuressDetails(_ pin: String) -> String {
        """
        The legacy duress wallet will be activated if '\(pin)' is provded. You probably created this on an older Mk2 or Mk3 Coldcard. Wallet is XPRV-based and derived from a fixed path.
        """
    }
    static func trickBIP85DuressDetails(words: Int, index: Int, pin: String) -> String {
        "BIP-85 derived wallet (\(words) words), with index #\(index), is provided if '\(pin)'."
    }
}

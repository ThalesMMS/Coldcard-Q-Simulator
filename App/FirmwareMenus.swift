import Foundation
import ColdcardCore

enum FirmwareMenuCatalog {
    static func title(for menu: FirmwareMenu) -> String {
        switch menu {
        case .virgin, .factory, .emptyWallet, .home: ""
        case .advanced, .advancedVirgin, .advancedEmpty: "Advanced/Tools"
        case .dangerZone: "Danger Zone"
        case .seedFunctions: "Seed Functions"
        case .backup: "Backup"
        case .fileManagement: "File Management"
        case .listedFiles, .readyToSignFiles: ""
        case .settings: "Settings"
        case .loginSettings: "Login Settings"
        case .buriedSettings: "Buried Settings"
        case .displayUnits: "Display Units"
        case .maxNetworkFee: "Max Network Fee"
        case .deletePSBTs: "Delete PSBTs"
        case .testnetMode: "Testnet Mode"
        case .sighashChecks: "Sighash Checks"
        case .calculatorLogin: "Calculator Login"
        case .aeStartIndex: "AE Start Index"
        case .menuWrapping: "Menu Wrapping"
        case .homeMenuXFP: "Home Menu XFP"
        case .newSeed: "New Seed Words"
        case .seedDice: "Advanced"
        case .importExisting: "Import Existing"
        case .passphrase: "Passphrase"
        case .savedPassphrases: "Restore Saved"
        case .addressExplorer: "Address Explorer"
        case .applications: "Applications"
        case .samourai: "Samourai"
        case .exportWallet: "Export Wallet"
        case .exportXPUB: "Export XPUB"
        case .exportKeyExpression: "Key Expression"
        // Firmware pushes these untitled (`menu.py` / `actions.py`).
        case .exportAddressType, .customPathFormat, .messageAddressFormat,
             .psbtExplorer, .userEntropy, .noteGroupPicker, .keypath, .xorVaultPick: ""
        case .notes: "Secure Notes & Passwords"
        // Firmware nested `MenuSystem` uses the parent row label, not a generic title.
        case .noteActions: ""
        case .noteGroup: "Group"
        case .savedPassphraseActions: ""
        case .upgradeFirmware: "Upgrade Firmware"
        case .temporarySeed: "Temporary Seed"
        case .iAmDeveloper: "I Am Developer."
        case .debugFunctions: "Debug Functions"
        case .seedXOR: "Seed XOR"
        case .spendingPolicy: "Spending Policy"
        case .nfcTools: "NFC Tools"
        case .hardwareOnOff: "Hardware On/Off"
        case .idleTimeout: "Idle Timeout"
        case .idleTimeoutBattery: "Idle Timeout (on battery)"
        case .lcdBrightnessBattery: "LCD Brightness (on battery)"
        case .keyboardEMU: "Keyboard EMU"
        case .seedVaultSetting: "Seed Vault"
        case .b85IdxValues: "B85 Idx Values"
        case .usbPort: "USB Port"
        case .virtualDisk: "Virtual Disk"
        case .nfcSharing: "NFC Sharing"
        case .loginCountdown: "Login Countdown"
        case .nfcPushTx: "NFC Push Tx"
        case .deriveSeeds: BIP85MenuCopy.kindMenuTitle
        case .scrambleKeys: "Scramble Keys"
        case .killKey: "Kill Key"
        case .microSD2FA: "MicroSD 2FA"
        case .trickPINs: ""
        case .trickPINDetail, .trickNewActions, .trickWipeChoices, .trickDuressChoices,
             .trickCountdownChoices, .trickWrongActions: ""
        case .trickCountdownPeriod: "Login Countdown"
        case .temporarySeedGenerate: "Generate Words"
        case .temporarySeedImport: "Import Words"
        case .seedVault: "Seed Vault"
        case .seedVaultActions: ""
        case .wifStore: "WIF Store"
        case .wifStoreItem: ""
        case .ssspConfig, .spendingPolicyEdit: "Spending Policy"
        case .spendingPolicyVelocity: "Velocity"
        case .spendingPolicyWhitelist: "Whitelist"
        case .cccConfig: "Co-Sign Multisig (CCC)"
        case .paperWallets: "Paper Wallets"
        case .paperWalletTemplates: ""
        // Firmware `SecretPickerMenu` is untitled; note/vault choosers use the parent row.
        case .keyTeleportSend: ""
        case .keyTeleportNotes: "Single Note / Password"
        case .keyTeleportVault: "From Seed Vault"
        case .keyTeleportCosigners: ""
        case .multisigWallets: "Multisig Wallets"
        // Firmware `MultisigMenu` / `make_ms_wallet_menu` / choosers are untitled.
        case .multisigWallet, .multisigDescriptors, .trustPSBT, .skipChecks,
             .fullAddressView, .unsortedMultisig: ""
        default: menu.rawValue
        }
    }

    static func items(menu: FirmwareMenu, secnapEnabled: Bool, hasSeed: Bool,
                      notes: [SecureNote], selectedNote: SecureNote?,
                      savedPassphrases: [SavedPassphrase],
                      selectedSavedPassphrase: SavedPassphrase?,
                      addressPreviews: [AddressType: String],
                      accountNumber: UInt32, startIndex: UInt32,
                      aeStartIndexEnabled: Bool,
                      displayUnits: DisplayUnits, maxFee: MaxNetworkFee,
                      deletePSBTs: Bool, menuWrapping: Bool,
                      calculatorLogin: Bool, alwaysShowHomeXFP: Bool,
                      sighashWarnOnly: Bool,
                      network: BitcoinNetwork,
                      seedVaultEnabled: Bool,
                      ephemeralActive: Bool,
                      vaultedSeeds: [VaultedSeed],
                      selectedVaultSeed: VaultedSeed?,
                      exportAddressTypes: [AddressType] = AddressType.singlesigExportOrder,
                      selectedNoteGroup: String? = nil,
                      homeXFP: String? = nil,
                      tmpSeedActive: Bool = false,
                      wordBasedSeed: Bool = false,
                      hasPassphrase: Bool = false,
                      keypathAtRoot: Bool = true,
                      keypathCPath: String = "m",
                      keypathLeaf: UInt32 = 0,
                      keypathRanged: Bool = true,
                      scrambleKeys: Bool = false,
                      killKey: String = "",
                      loginCountdownMinutes: Int = 0,
                      b85Unlimited: Bool = false,
                      idleTimeoutSeconds: Int = 4 * 3600,
                      idleTimeoutBatterySeconds: Int = 10 * 60,
                      nfcSharingEnabled: Bool = false,
                      usbPortEnabled: Bool = true,
                      virtualDiskEnabled: Bool = false,
                      virtualDiskMode: Int? = nil,
                      keyboardEmuEnabled: Bool = false,
                      hasPushtxURL: Bool = false,
                      ptxurl: String? = nil,
                      listedFiles: [ListedDiskFile] = [],
                      spending: SpendingPolicyMenuSnapshot = SpendingPolicyMenuSnapshot(),
                      sd2faNonces: [String] = [],
                      wifKeys: [WIFStoreItem] = [],
                      selectedWIFIndex: Int? = nil,
                      trickTable: TrickPinTable = TrickPinTable(),
                      selectedTrickPIN: String? = nil,
                      proposedTrickPIN: String = "",
                      proposedTrickWrongCount: Int = 1,
                      sessionPIN: String = "",
                      masterWordCount: Int = 24,
                      paperWalletIsSegwit: Bool = false,
                      paperWalletMakingPDF: Bool = false,
                      paperWalletTemplates: [ListedDiskFile] = [],
                      multisig: MultisigMenuSnapshot = MultisigMenuSnapshot()) -> [SimulatorMenuItem] {
        let hasRealSecret = hasSeed && !tmpSeedActive
        // Firmware `has_secrets()`: SE master or any RAM tmp (`pa.tmp_value`), including BIP-39 passphrase.
        let hasSecrets = hasSeed || tmpSeedActive || ephemeralActive
        let vdiskMode = virtualDiskMode ?? (virtualDiskEnabled ? 1 : 0)
        switch menu {
        case .virgin:
            return [
                item("Choose PIN Code", .command(.choosePIN)),
                item("Advanced/Tools", .openMenu(.advancedVirgin)),
                item("Bag Number", .command(.bagNumber))
            ]
        case .factory:
            return [
                item("Bag Me Now", .command(.bagMeNow)),
                item(FirmwareCopy.factoryVersionMenuTitle, .command(.showVersion)),
                item("DFU Upgrade", .command(.factoryDFU)),
                item("Ship W/O Bag", .command(.shipWithoutBag)),
                item("Debug Functions", .openMenu(.debugFunctions)),
                item("Perform Selftest", .command(.selftest))
            ]
        case .emptyWallet:
            return [
                item("New Seed Words", .openMenu(.newSeed)),
                item("Import Existing", .openMenu(.importExisting)),
                item("Migrate Coldcard", .command(.cloneStart)),
                item("Key Teleport (start)", .command(.keyTeleportStart)),
                item("Advanced/Tools", .openMenu(.advancedEmpty)),
                item("Settings", .openMenu(.settings))
            ]
        case .home:
            if spending.hobbled.isHobbled {
                return hobbledHome(secnapEnabled: secnapEnabled, wordBasedSeed: wordBasedSeed,
                                   keyboardEmuEnabled: keyboardEmuEnabled, hasSecrets: hasSecrets,
                                   seedVaultEnabled: seedVaultEnabled, homeXFP: homeXFP,
                                   nfcSharingEnabled: nfcSharingEnabled, spending: spending)
            }
            var rows: [SimulatorMenuItem] = []
            if let homeXFP {
                rows.append(item(homeXFP, .command(.readyToSign)))
            }
            rows.append(item("Ready To Sign", .command(.readyToSign)))
            if wordBasedSeed {
                rows.append(item("Passphrase", .openMenu(.passphrase)))
            }
            rows.append(item("Scan Any QR Code", .command(.scanAnyQR)))
            rows.append(item("Address Explorer", .openMenu(.addressExplorer)))
            if secnapEnabled {
                rows.append(item("Secure Notes & Passwords", .openMenu(.notes)))
            }
            if TypePasswords.isHomeItemVisible(keyboardEmuEnabled: keyboardEmuEnabled, hasSecrets: hasSecrets) {
                rows.append(item("Type Passwords", .command(.typePasswords)))
            }
            if seedVaultEnabled && hasSecrets {
                rows.append(item("Seed Vault", .openMenu(.seedVault)))
            }
            rows.append(item("Advanced/Tools", .openMenu(.advanced)))
            rows.append(item("Settings", .openMenu(.settings)))
            if tmpSeedActive {
                rows.append(item("Restore Master", .command(.restoreMaster)))
            }
            return rows
        case .advanced:
            if spending.hobbled.isHobbled {
                return hobbledAdvanced(nfcSharingEnabled: nfcSharingEnabled, hasRealSecret: hasRealSecret,
                                       spending: spending, hasMultisigWallets: !multisig.wallets.isEmpty)
            }
            var rows: [SimulatorMenuItem] = [
                item("Backup", .openMenu(.backup)),
                item("Export Wallet", .openMenu(.exportWallet))
            ]
            if !tmpSeedActive {
                rows.append(item("Upgrade Firmware", .openMenu(.upgradeFirmware)))
            }
            rows.append(item("File Management", .openMenu(.fileManagement)))
            if !secnapEnabled {
                rows.append(item("Secure Notes & Passwords", .command(.enableSecureNotes)))
            } else {
                rows.append(item("Secure Notes & Passwords", .openMenu(.notes)))
            }
            rows.append(item("Derive Seeds (BIP-85)", .command(.drvEntro)))
            rows.append(item("View Identity", .command(.viewIdentity)))
            rows.append(item("Temporary Seed", .openMenu(.temporarySeed)))
            rows.append(item("Key Teleport (start)", .command(.keyTeleportStart)))
            if hasRealSecret {
                rows.append(item("Spending Policy", .openMenu(.spendingPolicy)))
            }
            rows.append(item("Paper Wallets", .command(.startPaperWallets)))
            rows.append(item("WIF Store", .openMenu(.wifStore)))
            if nfcSharingEnabled {
                rows.append(item("NFC Tools", .openMenu(.nfcTools)))
            }
            rows.append(item("Danger Zone", .openMenu(.dangerZone)))
            return rows
        case .advancedVirgin:
            return [
                item("View Identity", .command(.viewIdentity)),
                item("Paper Wallets", .command(.startPaperWallets)),
                item("Perform Selftest", .command(.selftest))
            ]
        case .advancedEmpty:
            return [
                item("View Identity", .command(.viewIdentity)),
                item("Temporary Seed", .openMenu(.temporarySeed)),
                item("Upgrade Firmware", .openMenu(.upgradeFirmware)),
                item("File Management", .openMenu(.fileManagement)),
                item("Key Teleport (start)", .command(.keyTeleportStart)),
                item("Paper Wallets", .command(.startPaperWallets)),
                item("Perform Selftest", .command(.selftest)),
                item("I Am Developer.", .openMenu(.iAmDeveloper))
            ]
        case .dangerZone:
            var rows: [SimulatorMenuItem] = [
                item("Debug Functions", .openMenu(.debugFunctions)),
                item("Seed Functions", .openMenu(.seedFunctions)),
                item("I Am Developer.", .openMenu(.iAmDeveloper))
            ]
            if hasRealSecret {
                rows.append(item("Seed Vault", .openMenu(.seedVaultSetting), checked: seedVaultEnabled))
            }
            rows.append(contentsOf: [
                item("Perform Selftest", .command(.selftest)),
                limited("Set High-Water"),
                item("Clear OV cache", .command(.clearOVCache)),
                item("Clear Address cache", .command(.clearAddressCache)),
                // Firmware `ToggleMenuItem(..., invert=True)`: check when Default: Block (`sighshchk` unset/0).
                item("Sighash Checks", .openMenu(.sighashChecks), checked: !sighashWarnOnly),
                item("Testnet Mode", .openMenu(.testnetMode), checked: network != .mainnet)
            ])
            if hasSecrets {
                rows.append(item("AE Start Index", .openMenu(.aeStartIndex), checked: aeStartIndexEnabled))
                rows.append(item("B85 Idx Values", .openMenu(.b85IdxValues), checked: b85Unlimited))
            }
            rows.append(contentsOf: [
                limited("Settings Space"),
                limited("MCU Key Slots"),
                limited("Bless Firmware"),
                limited("Wipe LFS"),
                item("Nuke Device", .command(.nukeDevice))
            ])
            return rows
        case .sighashChecks:
            return [
                item("Default: Block", .command(.setSighashChecks(warnOnly: false)), checked: !sighashWarnOnly),
                item("Warn", .command(.setSighashChecks(warnOnly: true)), checked: sighashWarnOnly)
            ]
        case .seedFunctions:
            var rows = [
                item("View Seed Words", .command(.viewSeedWords)),
                item("Seed XOR", .openMenu(.seedXOR))
            ]
            if hasRealSecret {
                rows.append(item("Destroy Seed", .command(.destroySeed)))
            }
            if tmpSeedActive {
                rows.append(item("Lock Down Seed", .command(.lockDownSeed)))
            }
            if wordBasedSeed {
                rows.append(item("Export SeedQR", .command(.exportSeedQR)))
            }
            return rows
        case .seedXOR:
            var xor: [SimulatorMenuItem] = []
            if wordBasedSeed { xor.append(item("Split Existing", .command(.xorSplit))) }
            xor.append(item("Restore Seed XOR", .command(.xorRestore)))
            return xor
        case .upgradeFirmware:
            var rows: [SimulatorMenuItem] = [
                item("Show Version", .command(.showVersion)),
                limited("From MicroSD")
            ]
            if vdiskMode != 0 {
                rows.append(limited("From VirtDisk"))
            }
            return rows
        case .temporarySeed:
            var tmpRows: [SimulatorMenuItem] = []
            if !spending.hobbled.isHobbled {
                tmpRows.append(item("Generate Words", .openMenu(.temporarySeedGenerate)))
            }
            tmpRows.append(contentsOf: [
                item("Import from QR Scan", .command(.scanEphemeralQR)),
                item("Import Words", .openMenu(.temporarySeedImport)),
                item("Import XPRV", .command(.importXPRV)),
                item("Tapsigner Backup", .command(.importTapsignerBackup)),
                item("Coldcard Backup", .command(.restoreBackup)),
                item("Restore Seed XOR", .command(.xorRestore))
            ])
            return tmpRows
        case .temporarySeedGenerate:
            return [
                item("12 Words", .command(.generateEphemeralSeed(12))),
                item("24 Words", .command(.generateEphemeralSeed(24))),
                item("12 Word Dice Roll", .command(.diceEphemeralSeed(12))),
                item("24 Word Dice Roll", .command(.diceEphemeralSeed(24)))
            ]
        case .temporarySeedImport:
            var rows: [SimulatorMenuItem] = [
                item("12 Words", .command(.importEphemeralWords(12))),
                item("18 Words", .command(.importEphemeralWords(18))),
                item("24 Words", .command(.importEphemeralWords(24)))
            ]
            if nfcSharingEnabled {
                rows.append(item("Import via NFC", .command(.importEphemeralNFC)))
            }
            return rows
        case .iAmDeveloper:
            var rows = [
                item("Serial REPL", .command(.serialREPL)),
                item("Warm Reset", .command(.warmReset)),
                item("Restore Bkup", .command(.restoreDeveloperBackup))
            ]
            if hasSecrets {
                rows.append(item("BKPW Override", .command(.bkpwOverride)))
            }
            rows.append(item("Reflash GPU", .command(.reflashGPU)))
            return rows
        case .debugFunctions:
            return [
                item("Keyboard Test", .command(.keyboardTest)),
                item("BBQr Demo", .command(.bbqrDemo)),
                item("NFC Test", .command(.nfcTest)),
                item("Clear Tested", .command(.clearTested)),
                item("Debug: assert", .command(.debugAssert)),
                item("Debug: except", .command(.debugExcept)),
                item("Check: BL FW", .command(.checkFirewallRead)),
                item("Warm Reset", .command(.warmReset))
            ]
        case .spendingPolicy:
            // Q `version.supports_hsm = False`: omit `HSM Mode` and `User Management` (`flow.py`).
            var policy: [SimulatorMenuItem] = []
            if hasRealSecret { policy.append(item("Single-Signer", .command(.openSSSP))) }
            if !tmpSeedActive { policy.append(item("Co-Sign Multisig (CCC)", .command(.openCCC))) }
            return policy
        case .nfcTools:
            var rows: [SimulatorMenuItem] = [
                item("Sign PSBT", .command(.nfcSignPSBT)),
                item("Show Address", .command(.nfcShowAddress)),
                item("Sign Message", .command(.signMessage)),
                item("Verify Sig File", .command(.verifySigFile)),
                item("Verify Address", .command(.nfcVerifyAddress)),
                item("File Share", .command(.nfcFileShare))
            ]
            if !spending.hobbled.isHobbled {
                rows.append(item("Import Multisig", .command(.nfcImportMultisig)))
            }
            if hasPushtxURL {
                rows.append(item("Push Transaction", .command(.nfcPushTransaction)))
            }
            return rows
        case .deriveSeeds:
            return BIP85Kind.allCases.map { item($0.menuTitle, .command(.drvEntroKind($0.rawValue))) }
        case .seedVaultSetting:
            return [
                item("Default Off", .command(.setSeedVault(false)), checked: !seedVaultEnabled),
                item("Enable", .command(.setSeedVault(true)), checked: seedVaultEnabled)
            ]
        case .b85IdxValues:
            return [
                item("Default Off", .command(.setB85Unlimited(false)), checked: !b85Unlimited),
                item("Unlimited", .command(.setB85Unlimited(true)), checked: b85Unlimited)
            ]
        case .hardwareOnOff:
            // Firmware `ToggleMenuItem.is_chosen`: USB invert=True → check when ON; VD/NFC check when enabled.
            return [
                item("USB Port", .openMenu(.usbPort), checked: usbPortEnabled),
                item("Virtual Disk", .openMenu(.virtualDisk), checked: vdiskMode != 0),
                item("NFC Sharing", .openMenu(.nfcSharing), checked: nfcSharingEnabled)
            ]
        case .usbPort:
            return [
                item("Default On", .command(.setUSBPort(true)), checked: usbPortEnabled),
                item("Disable USB", .command(.setUSBPort(false)), checked: !usbPortEnabled)
            ]
        case .virtualDisk:
            return [
                item("Default Off", .command(.setVirtualDisk(0)), checked: vdiskMode == 0),
                item("Enable", .command(.setVirtualDisk(1)), checked: vdiskMode == 1),
                item("Enable & Auto", .command(.setVirtualDisk(2)), checked: vdiskMode == 2)
            ]
        case .nfcSharing:
            return [
                item("Default Off", .command(.setNFCSharing(false)), checked: !nfcSharingEnabled),
                item("Enable NFC", .command(.setNFCSharing(true)), checked: nfcSharingEnabled)
            ]
        case .idleTimeout:
            return [
                item(" 2 minutes", .command(.setIdleTimeout(120)), checked: idleTimeoutSeconds == 120),
                item(" 5 minutes", .command(.setIdleTimeout(300)), checked: idleTimeoutSeconds == 300),
                item("15 minutes", .command(.setIdleTimeout(900)), checked: idleTimeoutSeconds == 900),
                item(" 1 hour", .command(.setIdleTimeout(3600)), checked: idleTimeoutSeconds == 3600),
                item(" 4 hours", .command(.setIdleTimeout(4 * 3600)), checked: idleTimeoutSeconds == 4 * 3600),
                item(" 8 hours", .command(.setIdleTimeout(8 * 3600)), checked: idleTimeoutSeconds == 8 * 3600),
                item(" Never", .command(.setIdleTimeout(0)), checked: idleTimeoutSeconds == 0)
            ]
        case .idleTimeoutBattery:
            return [
                item(" 30 seconds", .command(.setIdleTimeoutBattery(30)), checked: idleTimeoutBatterySeconds == 30),
                item(" 60 seconds", .command(.setIdleTimeoutBattery(60)), checked: idleTimeoutBatterySeconds == 60),
                item(" 2 minutes", .command(.setIdleTimeoutBattery(120)), checked: idleTimeoutBatterySeconds == 120),
                item(" 5 minutes", .command(.setIdleTimeoutBattery(300)), checked: idleTimeoutBatterySeconds == 300),
                item("10 minutes", .command(.setIdleTimeoutBattery(600)), checked: idleTimeoutBatterySeconds == 600),
                item("15 minutes", .command(.setIdleTimeoutBattery(900)), checked: idleTimeoutBatterySeconds == 900),
                item("30 minutes", .command(.setIdleTimeoutBattery(1800)), checked: idleTimeoutBatterySeconds == 1800),
                item(" 1 hour", .command(.setIdleTimeoutBattery(3600)), checked: idleTimeoutBatterySeconds == 3600),
                item(" 4 hours", .command(.setIdleTimeoutBattery(4 * 3600)), checked: idleTimeoutBatterySeconds == 4 * 3600),
                item(" Never", .command(.setIdleTimeoutBattery(0)), checked: idleTimeoutBatterySeconds == 0)
            ]
        case .lcdBrightnessBattery:
            return [
                limited("25%"),
                limited("50%"),
                limited("60%"),
                limited("70%"),
                limited("80%"),
                limited("90%"),
                limited("95% (default)"),
                limited("100%")
            ]
        case .keyboardEMU:
            return [
                item("Default Off", .command(.setKeyboardEMU(false)), checked: !keyboardEmuEnabled),
                item("Enable", .command(.setKeyboardEMU(true)), checked: keyboardEmuEnabled)
            ]
        case .loginCountdown:
            let options: [(Int, String)] = [
                (0, "Disabled"), (5, " 5 minutes"), (15, "15 minutes"), (30, "30 minutes"),
                (60, " 1 hour"), (120, " 2 hours"), (240, " 4 hours"), (480, " 8 hours"),
                (720, "12 hours"), (1440, "24 hours"), (2880, "48 hours"),
                (3 * 1440, " 3 days"), (7 * 1440, " 1 week"), (28 * 1440, "28 days later")
            ]
            return options.map { minutes, label in
                item(label, .command(.setLoginCountdown(minutes)), checked: loginCountdownMinutes == minutes)
            }
        case .scrambleKeys:
            return LoginUX.scrambleChooserChoices.map { label in
                let scrambled = label == "Scramble Keys"
                return item(label, .command(.setScrambleKeys(scrambled)), checked: scrambleKeys == scrambled)
            }
        case .killKey:
            return LoginUX.killKeyChoices.map { key in
                let stored = LoginUX.storedKillKey(choice: key)
                return item(key, .command(.setKillKey(stored)), checked: killKey == stored)
            }
        case .nfcPushTx:
            var rows = PushTx.suppliers.map { supplier in
                item(supplier.label, .command(.setPushtxURL(supplier.url)), checked: ptxurl == supplier.url)
            }
            let current = ptxurl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isStock = PushTx.suppliers.contains(where: { $0.url == current })
            if !current.isEmpty, !isStock {
                rows.append(item(PushTx.hostLabel(for: current), .command(.editPushtxURL), checked: true))
            } else {
                rows.append(item("Custom URL...", .command(.editPushtxURL)))
            }
            rows.append(item("Disable", .command(.setPushtxURL(nil)), checked: current.isEmpty))
            return rows
        case .backup:
            return [
                item("Backup System", .command(.backupSystem)),
                item("Verify Backup", .command(.verifyBackup)),
                // Firmware BackupStuffMenu wires this to `need_clear_seed` unconditionally;
                // the real restore lives only under Import Existing (flow.py).
                item("Restore Backup", .command(.restoreBackupBlocked)),
                item("Clone Coldcard", .command(.cloneColdcard))
            ]
        case .fileManagement:
            if spending.hobbled.isHobbled {
                var rows: [SimulatorMenuItem] = [
                    item("Sign Text File", .command(.signTextFile)),
                    item("Batch Sign PSBT", .command(.batchSignPSBT)),
                    item("List Files", .command(.listFiles)),
                    item("Export Wallet", .openMenu(.exportWallet)),
                    item("Verify Sig File", .command(.verifySigFile))
                ]
                if nfcSharingEnabled {
                    rows.append(item("NFC File Share", .command(.nfcFileShare)))
                }
                rows.append(contentsOf: [
                    item("BBQr File Share", .command(.shareFileQR(bbqr: true))),
                    item("QR File Share", .command(.shareFileQR(bbqr: false))),
                    item("Format SD Card", .command(.formatSDCard))
                ])
                if vdiskMode != 0 {
                    rows.append(item("Format RAM Disk", .command(.formatRamDisk)))
                }
                return rows
            }
            var rows = [
                item("Verify Backup", .command(.verifyBackup))
            ]
            if hasSecrets {
                rows.append(item("Backup System", .command(.backupSystem)))
                rows.append(item("Export Wallet", .openMenu(.exportWallet)))
                rows.append(item("Sign Text File", .command(.signTextFile)))
                rows.append(item("Batch Sign PSBT", .command(.batchSignPSBT)))
                rows.append(item("Teleport Multisig PSBT", .command(.teleportMultisigPSBT)))
            }
            rows.append(contentsOf: [
                item("List Files", .command(.listFiles)),
                item("Verify Sig File", .command(.verifySigFile))
            ])
            if nfcSharingEnabled {
                rows.append(item("NFC File Share", .command(.nfcFileShare)))
            }
            rows.append(contentsOf: [
                item("BBQr File Share", .command(.shareFileQR(bbqr: true))),
                item("QR File Share", .command(.shareFileQR(bbqr: false)))
            ])
            if hasSecrets {
                rows.append(item("Clone Coldcard", .command(.cloneColdcard)))
            }
            rows.append(item("Format SD Card", .command(.formatSDCard)))
            if vdiskMode != 0 {
                rows.append(item("Format RAM Disk", .command(.formatRamDisk)))
            }
            return rows
        case .settings:
            var rows: [SimulatorMenuItem] = [
                item("Login Settings", .openMenu(.loginSettings)),
                item("Hardware On/Off", .openMenu(.hardwareOnOff))
            ]
            if hasSecrets {
                rows.append(item("Multisig Wallets", .openMenu(.multisigWallets),
                                 checked: !multisig.wallets.isEmpty))
            }
            rows.append(contentsOf: [
                item("NFC Push Tx", .openMenu(.nfcPushTx), checked: hasPushtxURL),
                item("Display Units", .openMenu(.displayUnits)),
                item("Max Network Fee", .openMenu(.maxNetworkFee)),
                item("Idle Timeout", .openMenu(.idleTimeout)),
                item("Idle Timeout (on battery)", .openMenu(.idleTimeoutBattery)),
                item("LCD Brightness (on battery)", .openMenu(.lcdBrightnessBattery)),
                item("Delete PSBTs", .openMenu(.deletePSBTs), checked: deletePSBTs)
            ])
            if hasSecrets {
                rows.append(item("Keyboard EMU", .openMenu(.keyboardEMU), checked: keyboardEmuEnabled))
            }
            rows.append(item("Buried Settings", .openMenu(.buriedSettings)))
            return rows
        case .loginSettings:
            var login: [SimulatorMenuItem] = [
                item("Change Main PIN", .command(.changeMainPIN))
            ]
            if hasRealSecret { login.append(item("Trick PINs", .openMenu(.trickPINs))) }
            login.append(contentsOf: [
                item("Set Nickname", .command(.setNickname)),
                item("Scramble Keys", .openMenu(.scrambleKeys), checked: scrambleKeys),
                item("Kill Key", .openMenu(.killKey), checked: !killKey.isEmpty),
                item("Login Countdown", .openMenu(.loginCountdown), checked: loginCountdownMinutes != 0)
            ])
            if hasRealSecret { login.append(item("MicroSD 2FA", .openMenu(.microSD2FA))) }
            login.append(item("Calculator Login", .openMenu(.calculatorLogin), checked: calculatorLogin))
            login.append(item("Test Login Now", .command(.testLoginNow)))
            return login
        case .buriedSettings:
            var buried: [SimulatorMenuItem] = []
            if hasRealSecret {
                buried.append(item("Home Menu XFP", .openMenu(.homeMenuXFP), checked: alwaysShowHomeXFP))
            }
            buried.append(item("Menu Wrapping", .openMenu(.menuWrapping), checked: menuWrapping))
            return buried
        case .displayUnits:
            return DisplayUnits.allCases.map {
                item($0.menuTitle, .command(.setDisplayUnits($0)), checked: $0 == displayUnits)
            }
        case .maxNetworkFee:
            return MaxNetworkFee.allCases.map {
                item($0.menuTitle, .command(.setMaxFee($0)), checked: $0 == maxFee)
            }
        case .deletePSBTs:
            return [
                item("Default Keep", .command(.setDeletePSBTs(false)), checked: !deletePSBTs),
                item("Delete PSBTs", .command(.setDeletePSBTs(true)), checked: deletePSBTs)
            ]
        case .testnetMode:
            return [
                item("Bitcoin", .command(.setNetwork(.mainnet)), checked: network == .mainnet),
                item("Testnet4", .command(.setNetwork(.testnet)), checked: network == .testnet),
                item("Regtest", .command(.setNetwork(.regtest)), checked: network == .regtest)
            ]
        case .calculatorLogin:
            return [
                item("Default Off", .command(.setCalculatorLogin(false)), checked: !calculatorLogin),
                item("Calculator Login", .command(.setCalculatorLogin(true)), checked: calculatorLogin)
            ]
        case .aeStartIndex:
            return [
                item("Default Off", .command(.setAEStartIndex(false)), checked: !aeStartIndexEnabled),
                item("Enable", .command(.setAEStartIndex(true)), checked: aeStartIndexEnabled)
            ]
        case .menuWrapping:
            return [
                item("Default", .command(.setMenuWrapping(false)), checked: !menuWrapping),
                item("Always Wrap", .command(.setMenuWrapping(true)), checked: menuWrapping)
            ]
        case .homeMenuXFP:
            return [
                item("Only Tmp", .command(.setAlwaysShowHomeXFP(false)), checked: !alwaysShowHomeXFP),
                item("Always Show", .command(.setAlwaysShowHomeXFP(true)), checked: alwaysShowHomeXFP)
            ]
        case .newSeed:
            return [
                item("12 Words", .command(.generateSeed(12))),
                item("24 Words", .command(.generateSeed(24))),
                item("Advanced", .openMenu(.seedDice))
            ]
        case .seedDice:
            return [
                item("12 Word Dice Roll", .command(.diceSeed(12))),
                item("24 Word Dice Roll", .command(.diceSeed(24)))
            ]
        case .importExisting:
            return [
                item("12 Words", .command(.importWords(12))),
                item("18 Words", .command(.importWords(18))),
                item("24 Words", .command(.importWords(24))),
                item("Scan QR Code", .command(.scanAnyQR)),
                item("Restore Backup", .command(.restoreBackup)),
                item("Clone Coldcard", .command(.cloneStart)),
                item("Import XPRV", .command(.importXPRV)),
                item("Tapsigner Backup", .command(.importTapsignerBackup)),
                item("Seed XOR", .command(.xorRestore))
            ]
        case .passphrase:
            var rows: [SimulatorMenuItem] = []
            if !savedPassphrases.isEmpty {
                rows.append(item("Restore Saved", .openMenu(.savedPassphrases)))
            }
            rows.append(item("Edit Phrase", .command(.editPhrase)))
            return rows
        case .savedPassphrases:
            // Firmware lists the masked phrase as the label (pwsave.py unique prefix/suffix).
            let phrases = savedPassphrases.map(\.phrase)
            let masked = maskedPassphrases(phrases)
            return zip(savedPassphrases, masked).map { saved, label in
                item(label.isEmpty ? "(empty)" : label, .command(.openSavedPassphrase(saved.id)))
            }
        case .savedPassphraseActions:
            guard let selected = selectedSavedPassphrase else {
                return [item("Restore Saved", .openMenu(.savedPassphrases))]
            }
            return [
                item("[\(selected.fingerprint)]", .command(.openSavedPassphrase(selected.id))),
                item("Restore", .command(.restoreSavedPassphrase(selected.id))),
                item("Delete", .command(.deleteSavedPassphrase(selected.id)))
            ]
        case .addressExplorer:
            var rows: [SimulatorMenuItem] = []
            for type in AddressType.explorerCases {
                rows.append(item(type.displayName, .command(.pickAddressType(type))))
                if let preview = addressPreviews[type].map({ WalletExporter.truncateAddress($0) }) {
                    rows.append(item(" ↳ \(preview)", .command(.pickAddressType(type))))
                }
            }
            if accountNumber == 0 {
                rows.append(item("Applications", .openMenu(.applications)))
                rows.append(item("Account Number", .command(.changeAccount)))
                rows.append(item("Custom Path", .command(.customPath)))
                for (index, wallet) in multisig.wallets.enumerated() {
                    rows.append(item(wallet.name, .command(.exploreMultisig(index))))
                }
            } else {
                rows.append(item("Account: \(accountNumber)", .command(.changeAccount)))
            }
            if aeStartIndexEnabled || startIndex != 0 {
                rows.append(item("Start Idx: \(startIndex)", .command(.changeStartIndex)))
            }
            return rows
        case .applications:
            return [
                item("Samourai", .openMenu(.samourai)),
                item("Wasabi", .command(.applicationWasabi))
            ]
        case .samourai:
            return [
                item("Post-mix", .command(.samouraiPostmix)),
                item("Pre-mix", .command(.samouraiPremix))
            ]
        case .exportWallet:
            return WalletExportKind.allCases.filter { kind in
                switch kind {
                case .xpubSegwit, .xpubClassic, .xpubWrapped, .xpubMaster, .xpubXFP: false
                case .dumpSummary: false
                default: !WalletExportKind.keyExpressionKinds.contains(kind)
                }
            }.map { kind in item(kind.menuTitle, .command(.export(kind))) }
            + [
                item("Export XPUB", .openMenu(.exportXPUB)),
                item("Key Expression", .command(.beginKeyExpression)),
                item("Dump Summary", .command(.export(.dumpSummary)))
            ]
        case .exportXPUB:
            return [
                item("Segwit (BIP-84)", .command(.export(.xpubSegwit))),
                item("Classic (BIP-44)", .command(.export(.xpubClassic))),
                item("P2WPKH/P2SH (BIP-49)", .command(.export(.xpubWrapped))),
                item("Master XPUB", .command(.export(.xpubMaster))),
                item("Current XFP", .command(.export(.xpubXFP)))
            ]
        case .exportKeyExpression:
            return WalletExportKind.keyExpressionKinds.map { kind in
                item(kind.menuTitle, .command(.export(kind)))
            } + [item("Custom Path", .command(.keyExpressionCustomPath))]
        case .exportAddressType:
            return exportAddressTypes.map { type in
                item(type.displayName, .command(.pickExportAddressType(type)))
            }
        case .messageAddressFormat:
            return AddressType.singlesigExportOrder.map { type in
                item(type.displayName, .command(.pickMessageAddressType(type)))
            }
        case .customPathFormat:
            // Firmware PickAddrFmtMenu (address_explorer.py).
            return AddressType.singlesigExportOrder.map { type in
                item(type.displayName, .command(.pickCustomPathFormat(type)))
            }
        case .keypath:
            return keypathItems(atRoot: keypathAtRoot, cpath: keypathCPath, leaf: keypathLeaf, ranged: keypathRanged)
        case .notes:
            var rows: [SimulatorMenuItem] = []
            let groups = SecureNotes.sortedGroupNames(notes.map(\.group))
            for (offset, note) in notes.enumerated() where note.group.isEmpty {
                rows.append(item(NoteMenuCopy.parentRowLabel(index: offset, title: note.title), .command(.openNote(note.id))))
            }
            for group in groups {
                rows.append(item("↳ \(group)", .command(.openNoteGroup(group))))
            }
            if spending.notesReadOnly {
                if rows.isEmpty { rows.append(inert("(none saved yet)")) }
                return rows
            }
            rows.append(contentsOf: [
                item("New Note", .command(.newNote)),
                item("New Password", .command(.newPassword))
            ])
            if notes.isEmpty {
                rows.append(item("Disable Feature", .command(.disableSecureNotes)))
            } else {
                rows.append(item("Export All", .command(.exportAllNotes)))
                if notes.count >= 2 {
                    rows.append(item("Sort By Title", .command(.sortNotes)))
                }
            }
            rows.append(item("Import", .command(.importNotes)))
            return rows
        case .noteGroup:
            let group = selectedNoteGroup ?? ""
            var rows: [SimulatorMenuItem] = []
            for (offset, note) in notes.enumerated() where note.group == group {
                rows.append(item(NoteMenuCopy.parentRowLabel(index: offset, title: note.title), .command(.openNote(note.id))))
            }
            if rows.isEmpty { rows.append(inert("(none)")) }
            return rows
        case .noteGroupPicker:
            let groups = SecureNotes.sortedGroupNames(notes.map(\.group))
            let current = selectedNoteGroup ?? ""
            var rows = [item(NoteGroupPickerUX.noneTitle, .command(.pickNoteGroup("")),
                             checked: NoteGroupPickerUX.isChecked(title: NoteGroupPickerUX.noneTitle, current: current))]
            for group in groups {
                rows.append(item(group, .command(.pickNoteGroup(group)),
                                 checked: NoteGroupPickerUX.isChecked(title: group, current: current)))
            }
            rows.append(item(NoteGroupPickerUX.newGroupTitle, .command(.newNoteGroup)))
            return rows
        case .noteActions:
            guard let selectedNote else { return [item("New Note", .command(.newNote))] }
            var rows: [SimulatorMenuItem] = [
                item("\"\(selectedNote.title)\"", .command(.viewNote))
            ]
            if selectedNote.kind == .note {
                rows.append(item("View Note", .command(.viewNote)))
                if !spending.notesReadOnly {
                    rows.append(contentsOf: [
                        item("Edit", .command(.editNote)),
                        item("Delete", .command(.deleteNote)),
                        item("Export", .command(.exportNote))
                    ])
                }
                if selectedNote.canSignMisc {
                    rows.append(item("Sign Note Text", .command(.signNote)))
                }
                if selectedNote.isB39PassApplicable(
                    readOnly: spending.notesReadOnly,
                    relatedKeys: spending.relatedKeys,
                    wordBased: wordBasedSeed
                ) {
                    rows.append(item("Apply as BIP-39 Passphrase", .command(.applyNotePassphrase)))
                }
                return rows
            }
            if !selectedNote.username.isEmpty {
                rows.append(item("↳ \(selectedNote.username)", .command(.viewNote)))
            }
            if !selectedNote.site.isEmpty {
                rows.append(item("↳ \(selectedNote.site)", .command(.viewNote)))
            }
            rows.append(contentsOf: [
                item("View Password", .command(.viewPassword)),
                item("Send Password", .command(.sendPassword))
            ])
            if !spending.notesReadOnly {
                rows.append(contentsOf: [
                    item("Export", .command(.exportNote)),
                    item("Edit Metadata", .command(.editNote)),
                    item("Delete", .command(.deleteNote)),
                    item("Change Password", .command(.changeNotePassword))
                ])
            }
            if selectedNote.canSignMisc {
                rows.append(item("Sign Note Text", .command(.signNote)))
            }
            if selectedNote.isB39PassApplicable(
                readOnly: spending.notesReadOnly,
                relatedKeys: spending.relatedKeys,
                wordBased: wordBasedSeed
            ) {
                rows.append(item("Apply as BIP-39 Passphrase", .command(.applyNotePassphrase)))
            }
            return rows
        case .psbtExplorer:
            return [
                item("Inputs", .command(.explorePSBTInputs)),
                item("Outputs", .command(.explorePSBTOutputs))
            ]
        case .userEntropy:
            return [
                item("Mash Keys", .command(.mashEntropy)),
                item("Dice Rolls", .command(.diceMixEntropy)),
                item("Coin Flips", .command(.coinEntropy)),
                item("CANCEL", .command(.menuCancel))
            ]
        case .seedVault:
            var rows: [SimulatorMenuItem] = []
            if vaultedSeeds.isEmpty {
                rows.append(inert("(none saved yet)"))
            } else {
                for (offset, seed) in vaultedSeeds.enumerated() {
                    rows.append(item(SeedVaultMenuCopy.parentRowLabel(index: offset, label: vaultSeedLabel(seed)),
                                     .command(.openVaultSeed(seed.id)),
                                     checked: vaultSeedIsActive(seed, tmpSeedActive: tmpSeedActive, homeXFP: homeXFP)))
                }
            }
            if tmpSeedActive {
                let tmpInVault = vaultedSeeds.contains {
                    vaultSeedIsActive($0, tmpSeedActive: tmpSeedActive, homeXFP: homeXFP)
                }
                if !tmpInVault, !spending.hobbled.isHobbled {
                    rows.append(item("Add current tmp", .command(.addCurrentTmpToVault)))
                }
                if !vaultedSeeds.isEmpty {
                    rows.append(item("Restore Master", .command(.restoreMaster)))
                }
            }
            if vaultedSeeds.isEmpty {
                rows.append(item("Temporary Seed", .openMenu(.temporarySeed)))
            }
            return rows
        case .seedVaultActions:
            guard let selectedVaultSeed else { return [inert("(none saved yet)")] }
            let isActive = vaultSeedIsActive(selectedVaultSeed, tmpSeedActive: tmpSeedActive, homeXFP: homeXFP)
            var rows: [SimulatorMenuItem] = [
                item(vaultSeedLabel(selectedVaultSeed), .command(.showVaultSeedDetail(selectedVaultSeed.id)))
            ]
            if isActive {
                rows.append(inert("Seed In Use", checked: true))
            } else {
                rows.append(item("Use This Seed", .command(.useVaultSeed(selectedVaultSeed.id))))
            }
            if !spending.hobbled.isHobbled, !(tmpSeedActive && !isActive) {
                rows.append(item("Rename", .command(.renameVaultSeed(selectedVaultSeed.id))))
                rows.append(item("Delete", .command(.deleteVaultSeed(selectedVaultSeed.id))))
            }
            return rows
        case .microSD2FA:
            var rows: [SimulatorMenuItem] = [
                item("Add Card", .command(.microSD2FAAddCard))
            ]
            if !sd2faNonces.isEmpty {
                rows.append(item("Check Card", .command(.microSD2FACheckCard)))
                for (index, nonce) in sd2faNonces.enumerated() {
                    rows.append(item("Remove Card #\(index + 1)", .command(.microSD2FARemoveCard(nonce))))
                }
            }
            return rows
        case .trickPINs:
            return trickPINList(table: trickTable, sessionPIN: sessionPIN, tmpSeedActive: tmpSeedActive)
        case .trickPINDetail:
            return trickPINDetail(table: trickTable, pin: selectedTrickPIN)
        case .trickNewActions:
            return trickNewActionItems(pin: proposedTrickPIN, wordCount: masterWordCount,
                                       countdownMinutes: loginCountdownMinutes)
        case .trickWipeChoices:
            return trickWipeChoiceItems()
        case .trickDuressChoices:
            return trickDuressChoiceItems(wordCount: masterWordCount)
        case .trickCountdownChoices:
            return trickCountdownChoiceItems(countdownMinutes: loginCountdownMinutes)
        case .trickWrongActions:
            return trickWrongActionItems(count: proposedTrickWrongCount)
        case .trickCountdownPeriod:
            let current = selectedTrickPIN.flatMap { trickTable.slot(forPIN: $0)?.arg }.map(Int.init) ?? 60
            return TrickPins.countdownChoices.map { minutes, label in
                item(label, .command(.setTrickCountdown(minutes)), checked: minutes == current)
            }
        case .wifStore:
            return wifStoreItems(wifKeys: wifKeys, network: network, hobbled: spending.hobbled.isHobbled)
        case .wifStoreItem:
            return wifStoreItemItems(hobbled: spending.hobbled.isHobbled)
        case .listedFiles:
            return listedFiles.map { file in
                item(file.menuLabel, .command(.inspectListedFile(file.id)))
            }
        case .readyToSignFiles:
            var rows = [item(ReadyToSign.signAllLabel, .command(.signAllReadyToSign))]
            rows += listedFiles.map { file in
                item(file.menuLabel, .command(.signReadyToSignPSBT(file.id)))
            }
            return rows
        case .ssspConfig:
            return ssspConfigItems(spending: spending)
        case .spendingPolicyEdit:
            return spendingPolicyEditItems(spending: spending)
        case .spendingPolicyVelocity:
            let current = spending.policy.vel ?? 0
            return zip(SpendingPolicyLimits.velocityLabels, SpendingPolicyLimits.velocityBlocks).map { label, blocks in
                item(label, .command(.pickSpendingVelocity(blocks)), checked: blocks == current)
            }
        case .spendingPolicyWhitelist:
            return spendingWhitelistItems(spending: spending)
        case .cccConfig:
            return cccConfigItems(spending: spending, wallets: multisig.wallets)
        case .paperWallets:
            return [
                item(paperWalletMakingPDF ? "Making PDF" : "Don't make PDF", .command(.pickPaperWalletPDF)),
                item(paperWalletIsSegwit ? "Segwit P2WPKH" : "Classic P2PKH",
                     .command(.setPaperWalletSegwit(!paperWalletIsSegwit))),
                item("Use Dice", .command(.paperWalletUseDice)),
                item("GENERATE WALLET", .command(.generatePaperWallet))
            ]
        case .paperWalletTemplates:
            return paperWalletTemplates.map { file in
                item(file.menuLabel, .command(.selectPaperWalletTemplate(file.id)))
            }
        case .keyTeleportSend:
            return keyTeleportSendItems(notes: notes, seedVaultEnabled: seedVaultEnabled,
                                        hasSeed: hasSeed, tmpSeedActive: tmpSeedActive,
                                        wordBasedSeed: wordBasedSeed, hasPassphrase: hasPassphrase)
        case .keyTeleportNotes:
            return notes.enumerated().map { index, note in
                item(NoteMenuCopy.parentRowLabel(index: index, title: note.title),
                     .command(.keyTeleportPickNote(note.id)))
            }
        case .keyTeleportVault:
            return vaultedSeeds.map { seed in
                item(vaultSeedLabel(seed), .command(.keyTeleportPickVault(seed.id)))
            }
        case .keyTeleportCosigners:
            return []
        case .xorVaultPick:
            return []
        case .multisigWallets:
            return multisigRootItems(multisig)
        case .multisigWallet:
            return multisigWalletItems(multisig)
        case .multisigDescriptors:
            return [
                item(MultisigMenuLayout.viewDescriptor, .command(.viewMultisigDescriptor)),
                item(MultisigMenuLayout.exportDescriptor, .command(.exportMultisigDescriptor)),
                item(MultisigMenuLayout.bitcoinCore, .command(.exportMultisigBitcoinCore))
            ]
        case .trustPSBT:
            return MultisigMenuLayout.trustChoices.enumerated().map { index, title in
                item(title, .command(.setTrustPSBT(index)), checked: index == multisig.trustPolicy)
            }
        case .skipChecks:
            return [
                item(MultisigMenuLayout.skipChoices[0], .command(.setSkipChecks(false)), checked: !multisig.skipChecks),
                item(MultisigMenuLayout.skipChoices[1], .command(.setSkipChecks(true)), checked: multisig.skipChecks)
            ]
        case .fullAddressView:
            return [
                item(MultisigMenuLayout.addressViewChoices[0], .command(.setFullAddressView(false)),
                     checked: !multisig.fullAddressView),
                item(MultisigMenuLayout.addressViewChoices[1], .command(.setFullAddressView(true)),
                     checked: multisig.fullAddressView)
            ]
        case .unsortedMultisig:
            return [
                item(MultisigMenuLayout.unsortedChoices[0], .command(.setUnsortedMultisig(false)),
                     checked: !multisig.allowUnsorted),
                item(MultisigMenuLayout.unsortedChoices[1], .command(.setUnsortedMultisig(true)),
                     checked: multisig.allowUnsorted)
            ]
        default:
            return []
        }
    }

    private static func wifStoreItems(wifKeys: [WIFStoreItem], network: BitcoinNetwork,
                                      hobbled: Bool) -> [SimulatorMenuItem] {
        var rows: [SimulatorMenuItem] = []
        if wifKeys.count < WIF.maxStoreItems, !hobbled {
            rows.append(item("Import WIF", .command(.importWIF)))
        }
        if wifKeys.isEmpty {
            rows.append(inert("(none yet)"))
        } else {
            for (index, stored) in wifKeys.enumerated() {
                let wif = (try? WIFStoreLogic.encodedWIF(stored, network: network)) ?? stored.publicKeyHex
                rows.append(item(WIFStoreLogic.menuLabel(index: index, wif: wif, qwerty: true),
                                 .command(.openWIFItem(index))))
            }
            if wifKeys.count > 1 {
                rows.append(item("Export All", .command(.exportAllWIF)))
                if !hobbled {
                    rows.append(item("Clear All", .command(.clearAllWIF)))
                }
            }
        }
        return rows
    }

    /// Firmware `SecretPickerMenu` (`teleport.py`).
    private static func keyTeleportSendItems(notes: [SecureNote], seedVaultEnabled: Bool,
                                             hasSeed: Bool, tmpSeedActive: Bool,
                                             wordBasedSeed: Bool, hasPassphrase: Bool) -> [SimulatorMenuItem] {
        var rows: [SimulatorMenuItem] = [
            item("Quick Text Message", .command(.keyTeleportQuickNote))
        ]
        if !notes.isEmpty {
            rows.append(item("Single Note / Password", .openMenu(.keyTeleportNotes)))
            rows.append(item("Export All Notes & Passwords", .command(.keyTeleportExportAllNotes)))
        }
        if seedVaultEnabled {
            rows.append(item("From Seed Vault", .openMenu(.keyTeleportVault)))
        }
        if let master = keyTeleportMasterItemTitle(hasSeed: hasSeed, tmpSeedActive: tmpSeedActive,
                                                   wordBasedSeed: wordBasedSeed, hasPassphrase: hasPassphrase) {
            rows.append(item(master, .command(.keyTeleportShareMaster)))
            rows.append(item("Full COLDCARD Backup", .command(.keyTeleportShareBackup)))
        }
        return rows
    }

    private static func keyTeleportMasterItemTitle(hasSeed: Bool, tmpSeedActive: Bool,
                                                   wordBasedSeed: Bool, hasPassphrase: Bool) -> String? {
        if tmpSeedActive {
            if wordBasedSeed { return "Temp Secret (words)" }
            return hasPassphrase ? "XPRV from Seed+Passphrase" : "Temp XPRV Secret"
        }
        if hasSeed {
            return wordBasedSeed ? "Master Seed Words" : "Master XPRV"
        }
        return nil
    }

    private static func wifStoreItemItems(hobbled: Bool) -> [SimulatorMenuItem] {
        var rows: [SimulatorMenuItem] = [
            item("Detail", .command(.wifDetail)),
            item("Descriptors", .command(.wifDescriptors)),
            item("Addresses", .command(.wifAddresses)),
            item("Sign MSG", .command(.wifSignMSG))
        ]
        if !hobbled {
            rows.append(item("Delete", .command(.deleteWIF)))
        }
        return rows
    }

    private static func hobbledHome(secnapEnabled: Bool, wordBasedSeed: Bool, keyboardEmuEnabled: Bool,
                                    hasSecrets: Bool, seedVaultEnabled: Bool, homeXFP: String?,
                                    nfcSharingEnabled: Bool, spending: SpendingPolicyMenuSnapshot) -> [SimulatorMenuItem] {
        var rows: [SimulatorMenuItem] = []
        if let homeXFP { rows.append(item(homeXFP, .command(.readyToSign))) }
        rows.append(item("Ready To Sign", .command(.readyToSign)))
        if wordBasedSeed && spending.relatedKeys {
            rows.append(item("Passphrase", .openMenu(.passphrase)))
        }
        rows.append(item("Scan Any QR Code", .command(.scanAnyQR)))
        rows.append(item("Address Explorer", .openMenu(.addressExplorer)))
        if secnapEnabled && spending.allowNotes {
            rows.append(item("Secure Notes & Passwords", .openMenu(.notes)))
        }
        if TypePasswords.isHomeItemVisible(keyboardEmuEnabled: keyboardEmuEnabled, hasSecrets: hasSecrets),
           spending.relatedKeys {
            rows.append(item("Type Passwords", .command(.typePasswords)))
        }
        if seedVaultEnabled && spending.relatedKeys {
            rows.append(item("Seed Vault", .openMenu(.seedVault)))
        }
        rows.append(item("Advanced/Tools", .openMenu(.advanced)))
        if spending.hobbled.isTestDrive {
            rows.append(item("EXIT TEST DRIVE", .command(.exitTestDrive)))
        }
        return rows
    }

    private static func hobbledAdvanced(nfcSharingEnabled: Bool, hasRealSecret: Bool,
                                        spending: SpendingPolicyMenuSnapshot,
                                        hasMultisigWallets: Bool) -> [SimulatorMenuItem] {
        var rows: [SimulatorMenuItem] = [
            item("File Management", .openMenu(.fileManagement)),
            item("Export Wallet", .openMenu(.exportWallet))
        ]
        // Firmware `flow.qr_and_ms`: Q has QR; hide unless at least one MS wallet exists.
        if MultisigMenuLayout.qrAndMS(hasQR: true, walletCount: hasMultisigWallets ? 1 : 0) {
            rows.append(item("Teleport Multisig PSBT", .command(.teleportMultisigPSBT)))
        }
        rows.append(item("View Identity", .command(.viewIdentity)))
        if spending.relatedKeys {
            rows.append(item("Temporary Seed", .openMenu(.temporarySeed)))
        }
        rows.append(item("Paper Wallets", .command(.startPaperWallets)))
        if nfcSharingEnabled {
            rows.append(item("NFC Tools", .openMenu(.nfcTools)))
        }
        if spending.relatedKeys {
            rows.append(item("WIF Store", .openMenu(.wifStore)))
        }
        rows.append(item("Show Firmware Version", .command(.showVersion)))
        if hasRealSecret {
            rows.append(item("Destroy Seed", .command(.destroySeed)))
        }
        return rows
    }

    private static func ssspConfigItems(spending: SpendingPolicyMenuSnapshot) -> [SimulatorMenuItem] {
        var items: [SimulatorMenuItem] = [
            item("Edit Policy...", .command(.ssspEditPolicy))
        ]
        if let reason = spending.lastViolation, !reason.isEmpty {
            items.insert(item("Last Violation", .command(.ssspLastViolation)), at: 1)
        }
        items.append(item("Word Check", .command(.ssspWordCheck), checked: spending.wordCheck))
        items.append(item("Allow Notes", .command(.ssspAllowNotes), checked: spending.allowNotes))
        items.append(item("Related Keys", .command(.ssspRelatedKeys), checked: spending.relatedKeys))
        items.append(item("Remove Policy", .command(.ssspRemovePolicy)))
        items.append(item("Test Drive", .command(.ssspTestDrive)))
        items.append(item("ACTIVATE", .command(.ssspActivate)))
        return items
    }

    private static func spendingPolicyEditItems(spending: SpendingPolicyMenuSnapshot) -> [SimulatorMenuItem] {
        let pol = spending.policy
        var items: [SimulatorMenuItem] = [
            item("Max Magnitude", .command(.setSpendingMagnitude), checked: (pol.mag ?? 0) != 0),
            item("Limit Velocity", .command(.setSpendingVelocity), checked: (pol.vel ?? 0) != 0),
            item("Whitelist Addresses", .command(.openSpendingWhitelist), checked: !pol.addresses.isEmpty),
            item("Web 2FA", .command(.toggleSpendingWeb2FA), checked: !pol.web2fa.isEmpty)
        ]
        if !pol.web2fa.isEmpty {
            items.append(item("↳ Test 2FA", .command(.testSpending2FA)))
            items.append(item("↳ Enroll More", .command(.enrollMore2FA)))
        }
        return items
    }

    private static func spendingWhitelistItems(spending: SpendingPolicyMenuSnapshot) -> [SimulatorMenuItem] {
        let addrs = spending.policy.addresses
        let maxxed = addrs.count >= SpendingPolicyLimits.maxWhitelist
        var items: [SimulatorMenuItem] = [
            item("Scan QR", .command(maxxed ? .unimplemented("Max whitelist") : .scanWhitelistQR)),
            item("Import from File", .command(maxxed ? .unimplemented("Max whitelist") : .importWhitelistFile))
        ]
        if addrs.isEmpty {
            items.append(inert("(none yet)"))
        } else {
            for addr in addrs.reversed() {
                items.append(item(WalletExporter.truncateAddress(addr), .command(.inspectWhitelistAddress(addr))))
            }
            if addrs.count > 1 {
                items.append(item("Clear Whitelist", .command(.clearSpendingWhitelist)))
            }
        }
        return items
    }

    private static func cccConfigItems(spending: SpendingPolicyMenuSnapshot,
                                       wallets: [ImportedMultisigWallet]) -> [SimulatorMenuItem] {
        let xfp = spending.cccXFP ?? "--------"
        var items: [SimulatorMenuItem] = [
            item("[\(xfp)] Co-Signing", .command(.cccShowIdent))
        ]
        if let reason = spending.lastViolation, !reason.isEmpty {
            items.insert(item("Last Violation", .command(.cccLastViolation)), at: 1)
        }
        items.append(item("Spending Policy", .command(.ssspEditPolicy)))
        items.append(item("Export CCC XPUBs", .command(.cccExportXPUBs)))
        items.append(inert("Multisig Wallets"))
        for (index, wallet) in wallets.enumerated()
            where MultisigMenuLayout.cccRelatedWallets(cccXFP: spending.cccXFP, wallets: [wallet]).isEmpty == false {
            items.append(item(MultisigMenuLayout.cccWalletRow(wallet),
                              .command(.openMultisigWallet(index))))
        }
        items.append(item("↳ Build 2-of-N", .command(.cccBuild2ofN)))
        items.append(item("Load Key C", .command(.cccLoadKeyC)))
        items.append(item("Remove CCC", .command(.cccRemove)))
        return items
    }

    /// Firmware `MultisigMenu.construct`.
    private static func multisigRootItems(_ snapshot: MultisigMenuSnapshot) -> [SimulatorMenuItem] {
        var rows: [SimulatorMenuItem] = []
        if snapshot.wallets.isEmpty {
            rows.append(item(MultisigMenuLayout.noneSetupYet, .command(.noneSetupYet)))
        } else {
            for (index, wallet) in snapshot.wallets.enumerated() {
                rows.append(item(MultisigMenuLayout.walletRow(wallet), .command(.openMultisigWallet(index))))
            }
        }
        rows.append(item(MultisigMenuLayout.importItem, .command(.importMultisig)))
        rows.append(item(MultisigMenuLayout.exportXPUB, .command(.exportMultisigXPUB)))
        rows.append(item(MultisigMenuLayout.createAirgapped, .command(.createAirgapped)))
        rows.append(item(MultisigMenuLayout.trustPSBT, .command(.trustPSBTMenu)))
        rows.append(item(MultisigMenuLayout.skipChecks, .command(.skipChecksMenu)))
        rows.append(item(MultisigMenuLayout.fullAddressView, .openMenu(.fullAddressView),
                         checked: snapshot.fullAddressView))
        rows.append(item(MultisigMenuLayout.unsortedMultisig, .command(.unsortedMultisigMenu),
                         checked: snapshot.allowUnsorted))
        return rows
    }

    /// Firmware `make_ms_wallet_menu`.
    private static func multisigWalletItems(_ snapshot: MultisigMenuSnapshot) -> [SimulatorMenuItem] {
        guard let index = snapshot.selectedIndex, snapshot.wallets.indices.contains(index) else {
            return [item(MultisigMenuLayout.noneSetupYet, .command(.noneSetupYet))]
        }
        let wallet = snapshot.wallets[index]
        var rows: [SimulatorMenuItem] = [
            item(MultisigMenuLayout.quotedWalletName(wallet.name), .command(.viewMultisigDetail)),
            item(MultisigMenuLayout.viewDetails, .command(.viewMultisigDetail)),
            item(MultisigMenuLayout.rename, .command(.renameMultisig)),
            item(MultisigMenuLayout.delete, .command(.deleteMultisig))
        ]
        if wallet.bip67 {
            rows.append(item(MultisigMenuLayout.coldcardExport, .command(.exportMultisigColdcard)))
            rows.append(item(MultisigMenuLayout.electrumWallet, .command(.exportMultisigElectrum)))
        }
        rows.append(item(MultisigMenuLayout.descriptors, .openMenu(.multisigDescriptors)))
        return rows
    }

    private static func trickPINList(table: TrickPinTable, sessionPIN: String, tmpSeedActive: Bool) -> [SimulatorMenuItem] {
        if tmpSeedActive {
            return [inert("Not Available")]
        }
        let pins = table.visiblePINs(hiding: sessionPIN.isEmpty ? nil : sessionPIN)
        var rows: [SimulatorMenuItem] = []
        if !pins.isEmpty {
            rows.append(inert("Trick PINs:"))
            for pin in pins {
                let title = pin == TrickPins.wrongPINCode ? "↳WRONG PIN" : "↳\(pin)"
                rows.append(item(title, .command(.openTrickPIN(pin))))
            }
        }
        rows.append(item("Add New Trick", .command(.trickAddNew)))
        if !pins.contains(TrickPins.wrongPINCode) {
            rows.append(item("Add If Wrong", .command(.trickAddIfWrong)))
        }
        rows.append(item("Delete All", .command(.trickDeleteAll)))
        return rows
    }

    private static func trickPINDetail(table: TrickPinTable, pin: String?) -> [SimulatorMenuItem] {
        guard let pin, let slot = table.slot(forPIN: pin) else {
            return [inert("(none)")]
        }
        var rows: [SimulatorMenuItem] = []
        if slot.isWrongCatchall {
            rows.append(inert("After \(slot.arg) wrong:"))
        } else {
            rows.append(inert("PIN \(pin)"))
        }
        for kind in TrickPinDetailKind.rows(for: slot) {
            switch kind {
            case .duressWallet:
                rows.append(item(kind.menuTitle, .command(.trickDuressDetails)))
            case .countdown:
                rows.append(item(kind.menuTitle, .command(.trickCountdownDetails)))
            default:
                rows.append(inert(kind.menuTitle))
            }
        }
        if slot.isDuressWallet {
            rows.append(item("Activate Wallet", .command(.trickActivateWallet)))
        }
        rows.append(item("Hide Trick", .command(.trickHide)))
        rows.append(item("Delete Trick", .command(.trickDelete)))
        if !slot.isWrongCatchall {
            rows.append(item("Change PIN", .command(.trickChangePIN)))
        }
        return rows
    }

    private static func trickBIP85Story(wordCount: Int) -> String {
        let base = TrickPins.bip85IndexBase(wordCount: wordCount)
        return "This PIN will lead to a functional 'duress' wallet using seed words produced by the standard BIP-85 process. Index number is \(base + 1)...\(base + 3) for #1..#3 duress wallets. Same number of seed words as your true seed."
    }

    private static func trickNewActionItems(pin: String, wordCount: Int, countdownMinutes: Int) -> [SimulatorMenuItem] {
        _ = (wordCount, countdownMinutes)
        return [
            inert("[\(pin)]"),
            item("Brick Self", .command(.trickPickAction("Brick Self", TrickPinFlags.brick.rawValue, 0))),
            item("Wipe Seed", .command(.trickOpenWipeMenu)),
            item("Duress Wallet", .command(.trickOpenDuressMenu(false))),
            item("Login Countdown", .command(.trickOpenCountdownMenu)),
            item("Look Blank", .command(.trickPickAction("Look Blank", TrickPinFlags.blankWallet.rawValue, 0))),
            item("Just Reboot", .command(.trickPickAction("Just Reboot", TrickPinFlags.reboot.rawValue, 0))),
            item("Delta Mode", .command(.trickPickAction("Delta Mode", TrickPinFlags.deltaMode.rawValue, 0))),
            item("Policy Unlock", .command(.trickPickAction("Policy Unlock", TrickPinFlags.firmwareDefined.rawValue, TrickPins.spendingPolicyUnlockArg))),
            item("Policy Unlock & Wipe", .command(.trickPickAction("Policy Unlock & Wipe", (TrickPinFlags.firmwareDefined.union(.wipe)).rawValue, TrickPins.spendingPolicyUnlockArg)))
        ]
    }

    private static func trickWipeChoiceItems() -> [SimulatorMenuItem] {
        [
            item("Wipe & Reboot", .command(.trickPickAction("Wipe & Reboot", TrickPinFlags.wipe.union(.reboot).rawValue, 0))),
            item("Silent Wipe", .command(.trickPickAction("Silent Wipe", TrickPinFlags.wipe.union(.fakeOut).rawValue, 0))),
            item("Wipe -> Wallet", .command(.trickOpenDuressMenu(true))),
            item("Say Wiped, Stop", .command(.trickPickAction("Say Wiped, Stop", TrickPinFlags.wipe.rawValue, 0)))
        ]
    }

    private static func trickDuressChoiceItems(wordCount: Int) -> [SimulatorMenuItem] {
        let base = UInt16(TrickPins.bip85IndexBase(wordCount: wordCount))
        _ = trickBIP85Story(wordCount: wordCount)
        return [
            item("BIP-85 Wallet #1", .command(.trickPickAction("BIP-85 Wallet #1", TrickPinFlags.wordWallet.rawValue, base + 1))),
            item("BIP-85 Wallet #2", .command(.trickPickAction("BIP-85 Wallet #2", TrickPinFlags.wordWallet.rawValue, base + 2))),
            item("BIP-85 Wallet #3", .command(.trickPickAction("BIP-85 Wallet #3", TrickPinFlags.wordWallet.rawValue, base + 3))),
            item("Legacy Wallet", .command(.trickPickAction("Legacy Wallet", TrickPinFlags.xprvWallet.rawValue, 0)))
        ]
    }

    private static func trickCountdownChoiceItems(countdownMinutes: Int) -> [SimulatorMenuItem] {
        let defTo = UInt16(TrickPins.defaultCountdownMinutes(loginSetting: countdownMinutes))
        return [
            item("Wipe & Countdown", .command(.trickPickAction("Wipe & Countdown", TrickPinFlags.wipe.union(.countdown).rawValue, defTo))),
            item("Countdown & Brick", .command(.trickPickAction("Countdown & Brick", TrickPinFlags.wipe.union(.brick).union(.countdown).rawValue, defTo))),
            item("Just Countdown", .command(.trickPickAction("Just Countdown", TrickPinFlags.countdown.rawValue, defTo)))
        ]
    }

    private static func trickWrongActionItems(count: Int) -> [SimulatorMenuItem] {
        let n = UInt16(max(1, count))
        let rel = TrickPins.wrongAttemptOrdinal(Int(n))
        return [
            inert("[\(rel) WRONG PIN]"),
            item("Wipe, Stop", .command(.trickPickAction("Wipe, Stop", TrickPinFlags.wipe.rawValue, n))),
            item("Wipe & Reboot", .command(.trickPickAction("Wipe & Reboot", TrickPinFlags.wipe.union(.reboot).rawValue, n))),
            item("Silent Wipe", .command(.trickPickAction("Silent Wipe", TrickPinFlags.wipe.union(.fakeOut).rawValue, n))),
            item("Brick Self", .command(.trickPickAction("Brick Self", TrickPinFlags.brick.rawValue, n))),
            item("Last Chance", .command(.trickPickAction("Last Chance", TrickPinFlags.wipe.union(.brick).rawValue, n))),
            item("Just Reboot", .command(.trickPickAction("Just Reboot", TrickPinFlags.reboot.rawValue, n)))
        ]
    }

    private static func item(_ title: String, _ action: SimulatorMenuAction, subtitle: String? = nil,
                             checked: Bool = false, simulatorOnly: Bool = false) -> SimulatorMenuItem {
        SimulatorMenuItem(id: title + (subtitle ?? "") + String(describing: action), title: title, subtitle: subtitle,
                          checked: checked, simulatorOnly: simulatorOnly, action: action)
    }

    private static func limited(_ title: String) -> SimulatorMenuItem {
        item(title, .command(.unimplemented(title)))
    }

    /// Firmware `MenuItem` with no `f` — selecting the row does nothing.
    private static func inert(_ title: String, checked: Bool = false) -> SimulatorMenuItem {
        item(title, .command(.menuNoop), checked: checked)
    }

    /// Firmware `encoded == pa.tmp_value` using the active tmp XFP.
    private static func vaultSeedIsActive(_ seed: VaultedSeed, tmpSeedActive: Bool, homeXFP: String?) -> Bool {
        guard tmpSeedActive else { return false }
        let current = (homeXFP?.filter(\.isHexDigit) ?? "").uppercased()
        guard !current.isEmpty else { return false }
        return seed.fingerprint.filter(\.isHexDigit).uppercased() == current
    }

    /// Firmware `rec.label` (vault stores `[XFP]` when unnamed).
    private static func vaultSeedLabel(_ seed: VaultedSeed) -> String {
        SeedVaultMenuCopy.storedLabel(custom: seed.label, fingerprint: seed.fingerprint)
    }

    /// Firmware `MenuSystem(chosen=selected)` — open choosers on the current value.
    static func chooserIndex(menu: FirmwareMenu, displayUnits: DisplayUnits, maxFee: MaxNetworkFee,
                             deletePSBTs: Bool, calculatorLogin: Bool, alwaysShowHomeXFP: Bool,
                             menuWrapping: Bool, sighashWarnOnly: Bool, network: BitcoinNetwork,
                             seedVaultEnabled: Bool, aeStartIndexEnabled: Bool,
                             keyboardEmuEnabled: Bool = false, b85Unlimited: Bool = false,
                             usbPortEnabled: Bool = true, nfcSharingEnabled: Bool = false,
                             virtualDiskMode: Int = 0, ptxurl: String? = nil,
                             noteGroupCurrent: String? = nil, noteGroups: [String] = [],
                             multisig: MultisigMenuSnapshot = MultisigMenuSnapshot()) -> Int? {
        switch menu {
        case .displayUnits: DisplayUnits.allCases.firstIndex(of: displayUnits)
        case .maxNetworkFee: MaxNetworkFee.allCases.firstIndex(of: maxFee)
        case .deletePSBTs: deletePSBTs ? 1 : 0
        case .calculatorLogin: calculatorLogin ? 1 : 0
        case .homeMenuXFP: alwaysShowHomeXFP ? 1 : 0
        case .menuWrapping: menuWrapping ? 1 : 0
        case .sighashChecks: sighashWarnOnly ? 1 : 0
        case .testnetMode:
            switch network {
            case .mainnet: 0
            case .testnet: 1
            case .regtest: 2
            }
        case .seedVaultSetting: seedVaultEnabled ? 1 : 0
        case .aeStartIndex: aeStartIndexEnabled ? 1 : 0
        case .keyboardEMU: keyboardEmuEnabled ? 1 : 0
        case .b85IdxValues: b85Unlimited ? 1 : 0
        case .usbPort: usbPortEnabled ? 0 : 1
        case .nfcSharing: nfcSharingEnabled ? 1 : 0
        case .virtualDisk: min(max(virtualDiskMode, 0), 2)
        case .nfcPushTx: PushTx.chooserIndex(current: ptxurl)
        case .noteGroupPicker:
            NoteGroupPickerUX.chosenIndex(current: noteGroupCurrent ?? "", groups: noteGroups)
        case .trickNewActions, .trickWipeChoices, .trickDuressChoices, .trickCountdownChoices, .trickWrongActions: 1
        case .trustPSBT: multisig.trustPolicy
        case .skipChecks: multisig.skipChecks ? 1 : 0
        case .fullAddressView: multisig.fullAddressView ? 1 : 0
        case .unsortedMultisig: multisig.allowUnsorted ? 1 : 0
        default: nil
        }
    }

    /// Firmware `pwsave.py`: shortest unique prefix or suffix of length 1…7, else full phrase.
    static func maskedPassphrases(_ phrases: [String]) -> [String] {
        guard !phrases.isEmpty else { return [] }
        for n in 1...7 {
            let prefixes = phrases.map { phrase -> String in
                if phrase.isEmpty { return "(empty)" }
                if phrase.count <= n { return phrase }
                return String(phrase.prefix(n)) + String(repeating: "*", count: phrase.count - n)
            }
            if Set(prefixes).count == phrases.count { return prefixes }
            let suffixes = phrases.map { phrase -> String in
                if phrase.isEmpty { return "(empty)" }
                if phrase.count <= n { return phrase }
                return String(repeating: "*", count: phrase.count - n) + String(phrase.suffix(n))
            }
            if Set(suffixes).count == phrases.count { return suffixes }
        }
        return phrases.map { $0.isEmpty ? "(empty)" : $0 }
    }

    static func maskedPassphrase(_ phrase: String) -> String {
        maskedPassphrases([phrase])[0]
    }

    /// Firmware `KeypathMenu` (`address_explorer.py`).
    private static func keypathItems(atRoot: Bool, cpath: String, leaf: UInt32, ranged: Bool) -> [SimulatorMenuItem] {
        let labels = AddressExplorer.keypathLabels(atRoot: atRoot, cpath: cpath, leaf: leaf, ranged: ranged)
        return zip(labels, AddressExplorer.displayedKeypathLabels(atRoot: atRoot, cpath: cpath, leaf: leaf, ranged: ranged)).map { label, shown in
            if label.hasSuffix("/⋯") {
                let deeper = String(label.dropLast(2))
                return item(shown, .command(.keypathDeeper(deeper)))
            }
            return item(shown, .command(.keypathDone(label)))
        }
    }
}

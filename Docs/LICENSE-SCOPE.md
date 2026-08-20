# License scope

This document maps the licenses that apply to the repository. It does not
replace the license texts. The top-level `LICENSE`, `LICENSE-APACHE`, and the
notices under `ThirdParty/` are authoritative.

## Original contributions: Apache-2.0

Copyright 2026 Thales Matheus Mendonça Santos

To the extent that the copyright holder owns copyright or other licensable
rights in them, original contributions are available under the Apache License,
Version 2.0 in `LICENSE-APACHE`. This grant covers:

- project and build metadata: `Package.swift`, `Info.plist`,
  `PrivacyInfo.xcprivacy`, `ColdcardQSimulator.entitlements`,
  `Resources/Settings.bundle/`, and
  `ColdcardQSimulator.xcodeproj/`;
- original build and validation tooling under `Scripts/`;
- original application code in `App/ColdcardQSimulatorApp.swift`,
  `App/DocumentsAndQR.swift`,
  `App/NFCServices.swift`, and
  `App/SecureServices.swift`;
- independently expressed support code in `Sources/ColdcardCore/Base58.swift`,
  `ByteUtils.swift`, `DemoPSBT.swift`, `HMAC.swift`,
  `LocalizedErrors.swift`, `RIPEMD160.swift`, `SHA1.swift`, `SHA2.swift`,
  `TOTP.swift`, and `Secp256k1.swift`;
- original test harnesses and assertions under `Tests/`, excluding retained or
  transcribed third-party vectors and test data; and
- original documentation prose under `README.md`, and `Docs/`, excluding
  third-party text, screenshots, device artwork, and material identified below.

The Apache-2.0 grant also covers the copyrightable original changes,
selection, arrangement, and Swift-specific expression contributed to the mixed
files below. It does not relicense inherited material.

## Mixed Coldcard-derived and original contributions

The following files contain or implement behavior adapted from the pinned
Coldcard firmware snapshot. Coinkite-originated portions remain under the MIT
License with Commons Clause License Condition v1.0 in
`ThirdParty/ColdcardFirmware/COPYING-CC`. Copyrightable original contributions
to those files are additionally offered under Apache-2.0. A recipient of the
combined files must comply with every applicable license, including the
Commons Clause restriction:

- `App/ColdcardDeviceView.swift`;
- `App/PhoneViews.swift`;
- `App/ScreenViews.swift`;
- `App/LCDChrome.swift`;
- `App/DocumentsStandin.swift`;
- `App/WIFStoreSupport.swift`;
- `App/PaperWalletActions.swift`;
- `App/SimulatorModels.swift`;
- `App/SimulatorStore.swift`;
- `App/CloneAndTapsigner.swift`;
- `App/ImportXPRVActions.swift`;
- `App/FirmwareMenus.swift`;
- `App/FactoryActions.swift`;
- `App/SpendingPolicyActions.swift`;
- `App/CloneAndTapsigner.swift`;
- `App/KeyTeleportFlow.swift`;
- `App/MultisigActions.swift`;
- `App/NFCToolsActions.swift`;
- `App/ReadyToSignActions.swift`;
- `App/DoneSigningActions.swift`;
- `App/PushTxActions.swift`;
- `App/TrickPINActions.swift`;
- `App/TrickPINActions.swift`;
- `App/MultisigActions.swift`;
- `App/KeyTeleportFlow.swift`;
- `App/PushTxActions.swift`;
- `App/NFCToolsActions.swift`;
- `App/PaperWalletActions.swift`;
- `Sources/ColdcardCore/Base32.swift`;
- `Sources/ColdcardCore/BBQr.swift`;
- `Sources/ColdcardCore/BIP32.swift`;
- `Sources/ColdcardCore/BIP39.swift`;
- `Sources/ColdcardCore/BIP85.swift`;
- `Sources/ColdcardCore/TypePasswords.swift`;
- `Sources/ColdcardCore/BIP322.swift`;
- `Sources/ColdcardCore/SeedXOR.swift`;
- `Sources/ColdcardCore/SeedCreation.swift`;
- `Tests/ColdcardCoreTests/SeedCreationTests.swift`;
- `Sources/ColdcardCore/Bech32.swift`;
- `Sources/ColdcardCore/BitcoinAddress.swift`;
- `Sources/ColdcardCore/BitcoinTransaction.swift`;
- `Sources/ColdcardCore/Descriptor.swift`;
- `Sources/ColdcardCore/DeveloperDebug.swift`;
- `Sources/ColdcardCore/DisplayUnits.swift`;
- `Sources/ColdcardCore/HardwareKeyboard.swift`;
- `Sources/ColdcardCore/LCDLayout.swift`;
- `Tests/ColdcardCoreTests/LCDLayoutTests.swift`;
- `Tests/ColdcardCoreTests/MenuUXTests.swift`;
- `Tests/ColdcardCoreTests/SeedVaultTests.swift`;
- `Sources/ColdcardCore/ImportPrompt.swift`;
- `Sources/ColdcardCore/ExportPromptBuilder.swift`;
- `Sources/ColdcardCore/AES256CTR.swift`;
- `Sources/ColdcardCore/AESCTR.swift`;
- `Sources/ColdcardCore/CloneTransfer.swift`;
- `Sources/ColdcardCore/BackupFile.swift`;
- `Sources/ColdcardCore/KeyTeleport.swift`;
- `Sources/ColdcardCore/MicroSD2FA.swift`;
- `Sources/ColdcardCore/Multisig.swift`;
- `Sources/ColdcardCore/PaperWallet.swift`;
- `Sources/ColdcardCore/PushTx.swift`;
- `Sources/ColdcardCore/QRCode.swift`;
- `Sources/ColdcardCore/ScanAnything.swift`;
- `Sources/ColdcardCore/SecretStash.swift`;
- `Sources/ColdcardCore/SeedVault.swift`;
- `Sources/ColdcardCore/SeedDanger.swift`;
- `Sources/ColdcardCore/TapsignerBackup.swift`;
- `Sources/ColdcardCore/TrickPins.swift`;
- `Sources/ColdcardCore/WIF.swift`;
- `Sources/ColdcardCore/MessageSigning.swift`;
- `Sources/ColdcardCore/PSBT.swift`;
- `Sources/ColdcardCore/OutptValueCache.swift`;
- `Sources/ColdcardCore/SpendingPolicy.swift`;
- `Sources/ColdcardCore/SecureNotes.swift`;
- `Sources/ColdcardCore/Compat7z.swift`;
- `Sources/ColdcardCore/LoginUX.swift`;
- `Sources/ColdcardCore/CalculatorLogin.swift`;
- `Sources/ColdcardCore/ExpressionEvaluator.swift`;
- `Sources/ColdcardCore/MenuUX.swift`;
- `Sources/ColdcardCore/FirstTimeUX.swift`;
- `Sources/ColdcardCore/PinPrefixWords.swift`;
- `Sources/ColdcardCore/QSelftest.swift`;
- `Sources/ColdcardCore/NFCShare.swift`;
- `Sources/ColdcardCore/AddressExplorer.swift`;
- `Tests/ColdcardCoreTests/AddressExplorerTests.swift`;
- `Sources/ColdcardCore/ReadyToSign.swift`;
- `Sources/ColdcardCore/DoneSigning.swift`;
- `Sources/ColdcardCore/SecretStash.swift`;
- `Sources/ColdcardCore/PushTx.swift`;
- `Sources/ColdcardCore/MicroSD2FA.swift`;
- `Sources/ColdcardCore/TrickPins.swift`;
- `Sources/ColdcardCore/TapsignerBackup.swift`;
- `Sources/ColdcardCore/KeyTeleport.swift`;
- `Sources/ColdcardCore/PaperWallet.swift`;
- `Sources/ColdcardCore/Multisig.swift`;
- `Sources/ColdcardCore/CloneTransfer.swift`;
- `Sources/ColdcardCore/WIF.swift`;
- `Sources/ColdcardCore/ExportPromptBuilder.swift`;
- `Sources/ColdcardCore/AES256CTR.swift`;
- `Sources/ColdcardCore/AESCTR.swift`; and
- `Sources/ColdcardCore/QRCode.swift`.

Additional MIT notices also apply to `Bech32.swift`, `BitcoinTransaction.swift`,
`BIP39.swift`, `BIP39EnglishWords.swift`, their related tests, and retained test
data as described in `NOTICE.md` and `Docs/PROVENANCE.md`.

## Artwork, screenshots, and app icon

The following are not offered solely under Apache-2.0:

- `Resources/Assets.xcassets/q1-background.imageset/q1-background.png`;
- `Resources/Assets.xcassets/led-green.imageset/led-green.png`;
- `Resources/Assets.xcassets/led-red.imageset/led-red.png`;
- `Resources/Assets.xcassets/coldcard-splash.imageset/coldcard-splash.png`;
- `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`;
- `Docs/Simulator-UI-A.png`;
- `Docs/Simulator-UI-B.png`; and
- `Docs/preview.png`.

The enclosure, screen, LED, splash, and device artwork originate from or are
derived from the Coldcard snapshot and retain the Coinkite MIT + Commons Clause
notice. The app icon was generated with OpenAI image tooling using the retained
Q1 device artwork as its visual reference; any copyrightable original
composition is offered under Apache-2.0, while the referenced Coldcard material
remains under its original terms. Screenshots may also contain operating-system
or Simulator interface elements owned by their respective rights holders; this
project does not purport to license those elements.

Copyright licenses do not grant trademark rights. `COLDCARD`, the Q mark, and
related brand elements belong to their respective owners.

## Vendored and retained third-party material

- `Sources/BigInt/`: MIT; see `ThirdParty/BigInt-LICENSE.md`.
- `ThirdParty/ColdcardFirmware/`: the notices retained in that directory,
  principally Coinkite MIT + Commons Clause.
- BIP-39 and python-mnemonic material: the notices in
  `ThirdParty/BIP39-NOTICE.md`.
- Bech32/Bech32m material: MIT; see `ThirdParty/Bech32-LICENSE.md`.
- Bitcoin Core serialization material: MIT; see
  `ThirdParty/BitcoinCore-LICENSE.md`.

No Apache-2.0 grant from this project changes or supersedes these terms.

## AI-assisted development

The project was developed with assistance from ChatGPT and OpenAI image
tooling, with human direction, review, selection, and modification. OpenAI is
not listed as a licensor or copyright holder, and no affiliation, sponsorship,
or endorsement by OpenAI is claimed.

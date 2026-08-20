# Provenance and reuse map

## Primary upstream checkout

The mandatory behavioral reference is the sibling git clone at `../firmware`
(`https://github.com/Coldcard/firmware.git`). Verified locally:

- `git rev-parse HEAD` = `15de4a0c1a4587d8f6cf93b3763afbcbe0a7581c` (`master`, tracking `origin/master`)
- `ckcc-protocol` submodule = `3d1dfa858beb58b8dac37d8c66d7aed2909812f2` (`external/ckcc-protocol`, tag `v1.5.0-11-g3d1dfa8`)
- other checked-out submodules: `external/libngu`, `external/micropython`, `external/mpy-qr`, `misc/gpu/external/cmsis_device_c0`, `misc/gpu/external/stm32c0xx_hal_driver`
- `shared/public_constants.py` is a working symlink to `external/ckcc-protocol/ckcc/constants.py`

<https://github.com/Coldcard/firmware/tree/15de4a0c1a4587d8f6cf93b3763afbcbe0a7581c>

That commit is 13 revisions ahead of the earlier pin
`206bbdb0eb707083f6fb15182cb63f46635ae66e` (2026-08-18, “reject oversized SegWit
HRPs”). `docs/menu-tree.txt` at HEAD is byte-identical to the retained copy
`ThirdParty/ColdcardFirmware/menu-tree.txt`. Published changelog top entry
remains `2026-07-31 … 1.5.0Q`; unpublished work is in
`releases/Next-ChangeLog.md`.

`MSG_SIGNING_MAX_LENGTH` is `240`, read from the sibling
`external/ckcc-protocol/ckcc/constants.py` (also imported by
`shared/msgsign.py`). Python from that checkout is not copied into this
repository.

Coldcard-associated files are covered by the Coinkite MIT License with the
Commons Clause License Condition v1.0 in
`ThirdParty/ColdcardFirmware/COPYING-CC`.

No Coldcard Python source is redistributed in this repository. Python paths
named below are provenance pointers into the pinned upstream commit, not local
vendored files.

## Directly retained material

| Firmware path | Repository destination | Purpose |
|---|---|---|
| `unix/q1-images/background.png` | Asset `q1-background` | Q1 enclosure and LCD/key positioning |
| `unix/q1-images/led-*.png` | Assets `led-*` | Device status artwork |
| `graphics/colour/splash.png` | Asset `coldcard-splash` | Splash/privacy-cover artwork |
| `README.md` | `ThirdParty/ColdcardFirmware/README.md` | Upstream project and security documentation |
| `docs/menu-tree.txt` | `ThirdParty/ColdcardFirmware/menu-tree.txt` | Menu terminology and hierarchy |
| `docs/pin-entry.md` | `ThirdParty/ColdcardFirmware/pin-entry.md` | PIN and anti-phishing-word workflow |
| `docs/generic-wallet-export.md` | `ThirdParty/ColdcardFirmware/generic-wallet-export.md` | Export format reference |
| `testing/bip39-vectors.json` | `ThirdParty/ColdcardFirmware/Reference/bip39-vectors.json` | BIP-39 validation vectors |

## Derived project artwork and screenshots

| Repository path | Source/reference | License treatment |
|---|---|---|
| `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | Generated with OpenAI image tooling using the retained Q1 enclosure artwork as a visual reference | Mixed original composition plus Coinkite MIT + Commons Clause material; not Apache-only |
| `Docs/preview.png` | Rendered project UI using the retained Q1 enclosure artwork | Mixed project documentation plus Coinkite MIT + Commons Clause material; not Apache-only |
| `Docs/simulator-iphone.png` | User-provided screenshot of the app running in Apple Simulator | Project documentation with Coldcard-derived artwork and third-party Simulator UI elements; not Apache-only |

The generated icon intentionally contains no `SWIFT SIM` wording. Copyright
licenses do not grant trademark rights in `COLDCARD`, the Q mark, Apple product
names, or related brand elements.

The supplied `testing/base58.py` file declared CC BY-NC-ND 4.0. It is not
redistributed because that license does not permit sharing adaptations. The
Swift `Base58` implementation is independently expressed from standardized
Base58Check behavior and does not copy or require that Python file.

## Swift adaptations from upstream paths

- `shared/bbqr.py` → `Base32.swift`, `BBQr.swift`;
- `testing/bech32.py` → `Bech32.swift`;
- `testing/bip32.py`, `shared/chains.py` → `BIP32.swift`,
  `BitcoinAddress.swift`;
- `shared/serializations.py`, `testing/serialize.py`, `testing/sighash.py` →
  `BitcoinTransaction.swift`;
- `shared/psbt.py`, `testing/psbt.py` → `PSBT.swift`;
- `shared/multisig.py`, `testing/devtest/unit_multisig.py`, `testing/data/multisig/` → `Multisig.swift`;
- `shared/msgsign.py` → `MessageSigning.swift`;
- `shared/paper.py` → `PaperWallet.swift`;
- firmware `uqr` version-4 paper-wallet QR encoding → `QRCode.swift`;
- `shared/notes.py` → `SecureNotes.swift` and Secure Notes flows in the app layer;
- `shared/compat7z.py` → `Compat7z.swift` (AES-256 7z used by encrypted note export/import);
- `shared/export.py` → `Descriptor.swift`;
- `shared/seed.py` and BIP-39 vectors → `BIP39.swift`;
- `shared/xor_seed.py` → `SeedXOR.swift`;
- `shared/drv_entro.py` → `BIP85.swift`, `TypePasswords.swift`;
- `shared/tapsigner.py` and TAPSIGNER encrypted-backup test files
  (`testing/data/backup-*.aes`, hex inlined, files not vendored) →
  `TapsignerBackup.swift`, `AESCTR.swift`;
- `shared/backups.py` (`render_backup_contents`, `text_bk_parser`,
  `pick_backup_password`, `write_complete_backup`, `verify_backup_file`,
  `restore_complete`, `clone_start`, `clone_write_data`) →
  `BackupFile.swift`, `CloneTransfer.swift`, and backup/clone Files flows;
- `shared/pwsave.py` (`MicroSD2FA`), `shared/actions.py` (`microsd_2fa`),
  and `docs/microsd-2fa.md` → `MicroSD2FA.swift` and Login Settings
  MicroSD 2FA flows in the app layer;
- `shared/ux_q1.py`, `shared/menu.py`, and `docs/menu-tree.txt` → SwiftUI
  views and state-machine behavior.

This is not a line-by-line translation. Hardware- and MicroPython-specific APIs
were replaced with native iOS abstractions while preserving interoperable
Bitcoin formats and published test vectors. The source paths above remain
auditable at the pinned upstream commit without redistributing their Python
files in this repository.

## Additional upstream components

| Component | Version/source | Repository scope | License notice |
|---|---|---|---|
| attaswift/BigInt | v6.0.0, exact 21-file source subset | `Sources/BigInt/` | `ThirdParty/BigInt-LICENSE.md` |
| BIP-39 specification and English word list | bitcoin/bips | `BIP39.swift`, `BIP39EnglishWords.swift`, related tests | `ThirdParty/BIP39-NOTICE.md` |
| python-mnemonic vectors | trezor/python-mnemonic | retained BIP-39 vectors and related tests | `ThirdParty/BIP39-NOTICE.md` |
| Pieter Wuille Bech32/Bech32m reference | sipa/bech32 | `Bech32.swift` and related tests; Python source not vendored | `ThirdParty/Bech32-LICENSE.md` |
| Bitcoin Core serialization reference | Bitcoin Core test framework via Coldcard | `BitcoinTransaction.swift` and related tests; Python source not vendored | `ThirdParty/BitcoinCore-LICENSE.md` |

See the top-level `LICENSE`, `LICENSE-APACHE`, `NOTICE.md`, and
`Docs/LICENSE-SCOPE.md` before redistributing any part of the repository.

# Third-Party Notices

This repository contains material under several licenses. The top-level
`LICENSE` file and `Docs/LICENSE-SCOPE.md` explain their scope.

## Original Coldcard Q Simulator contributions

Copyright 2026 Thales Matheus Mendonça Santos

To the extent that the copyright holder owns copyright or other licensable
rights in them, original contributions are licensed under the Apache License,
Version 2.0 in `LICENSE-APACHE`. That grant does not relicense Coldcard-derived
or other third-party material. Mixed files remain subject to every applicable
license identified in `Docs/LICENSE-SCOPE.md`.

The project was developed with assistance from ChatGPT and OpenAI image
tooling, with human direction, review, selection, and modification. OpenAI is
not a licensor, sponsor, or endorser of this repository.

## Coldcard firmware, documentation, and assets

Source: `Coldcard/firmware`, commit
`15de4a0c1a4587d8f6cf93b3763afbcbe0a7581c`.

Copyright © Coinkite Inc.

The Coinkite MIT License with Commons Clause License Condition v1.0 is
reproduced verbatim in:

- `ThirdParty/ColdcardFirmware/COPYING-CC`
- `ThirdParty/ColdcardFirmware/LICENSE`

It applies to the retained Coldcard documentation and test data, the Q1
enclosure/LED/splash assets, the derived app icon and documentation imagery,
and the Swift adaptations identified in `Docs/PROVENANCE.md` and
`Docs/LICENSE-SCOPE.md`. The Commons Clause condition does not grant the right
to "Sell" the software as defined in that notice. Do not describe the affected
project as OSI-approved open source.

The pinned firmware snapshot also incorporates upstream work, including Pieter
Wuille's Bech32/Bech32m reference implementation and Bitcoin Core-derived
serialization code. Those Python sources are not vendored here; their MIT
notices remain bundled separately below because the corresponding Swift code
and tests retain that provenance.

## BigInt

`Sources/BigInt` is an exact 21-file source subset from `attaswift/BigInt`
v6.0.0. It is distributed under the MIT License. The upstream license is
reproduced verbatim in `ThirdParty/BigInt-LICENSE.md`.

## BIP-39, python-mnemonic, Bech32, and Bitcoin Core

- BIP-39 specification and English word list: MIT; see
  `ThirdParty/BIP39-NOTICE.md`.
- BIP-39 vectors from `trezor/python-mnemonic`: MIT; see
  `ThirdParty/BIP39-NOTICE.md`.
- Bech32/Bech32m reference implementation by Pieter Wuille: MIT; see
  `ThirdParty/Bech32-LICENSE.md`.
- Bitcoin Core-derived serialization material: MIT; see
  `ThirdParty/BitcoinCore-LICENSE.md`.

## Unofficial project and trademarks

This is an unofficial simulator. It is not affiliated with, endorsed by,
sponsored by, or security-reviewed by Coinkite. COLDCARD and related brand
elements belong to their respective owners. No trademark license is asserted.

## Security notice

This software is an educational and development simulator, not a hardware
wallet. It does not reproduce secure elements, verified boot, physical
isolation, anti-tamper properties, or the security assumptions of a real
Coldcard Q. Testnet is the intended default. Do not entrust real funds to keys
generated or stored by this app.

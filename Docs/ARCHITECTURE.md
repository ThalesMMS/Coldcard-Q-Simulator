# Architecture

## Layers

```text
SwiftUI device shell
        │
        ├── SimulatorStore (@MainActor/@Observable)
        │       ├── device state machine
        │       ├── Keychain and backups
        │       ├── file import/export
        │       └── camera/QR
        │
        └── ColdcardCore (local Swift package)
                ├── hashes and encodings
                ├── BIP-39 / PBKDF2
                ├── secp256k1 / RFC 6979
                ├── BIP-32 / SLIP-132
                ├── scripts and addresses
                ├── transactions / legacy sighash and BIP-143
                ├── PSBT v0 / common v2
                ├── descriptors
                └── message signing
```

## Isolation

`ColdcardCore` does not import SwiftUI, UIKit, Security, CryptoKit, camera APIs,
or file-system APIs. It can be compiled and tested independently on
Linux/macOS/iOS. The app injects secure entropy using `SecRandomCopyBytes`; the
core accepts an entropy-producing closure to keep tests deterministic.

## Persistence

The wallet record is serialized as JSON and stored as a generic Keychain item
with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The PIN itself is not
stored; `SHA256(salt || PIN)` is persisted to reproduce the simulator's lock
flow. This does not replicate the PIN protection provided by secure elements in
real hardware.

## Concurrency

The interface is controlled by `SimulatorStore` on the MainActor. Address
derivation, signing, parsing, and backup encryption run in detached tasks so
they do not block LCD rendering.

## Network

No analytics, generic RPC, or seed upload. PSBTs, exports, and backups enter
and leave through QR, Files, and Core NFC NDEF where iOS allows. Firmware-style
**Push Tx** may use HTTP(S) to the user-configured `ptxurl` (Testnet by
default). `ColdcardCore` must not import network frameworks.

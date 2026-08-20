# Validation

Run the complete local validation from the repository root:

```bash
./Scripts/validate.sh
```

The script performs seven stages:

1. builds and tests the local Swift package;
2. parses every iOS app source file;
3. validates Xcode project references;
4. validates plists and asset-catalog JSON;
5. checks the exact Apache-2.0 and Coldcard license texts, license-scope
   coverage, required third-party notices, absence of Python source under
   `ThirdParty/`, and the 1024×1024 app icon;
6. verifies that `MANIFEST.sha256` covers the complete publishable tree;
7. verifies every recorded SHA-256 hash.

## Automated test coverage

- SHA-256, SHA-512, RIPEMD-160, and HMAC;
- BIP-39 and PBKDF2;
- Base32, multipart BBQr, Base58Check, Bech32, and Bech32m;
- BIP-32 and non-hardened public derivation;
- BIP-44/49/84/86 address families;
- secp256k1 and deterministic ECDSA;
- descriptor checksums and compact message signing;
- P2PKH, P2SH-P2WPKH, and P2WPKH PSBT signing;
- security regressions for conflicting legacy UTXOs, unsafe sighashes,
  duplicate outpoints, and false change detection;
- hardware-keyboard mappings.

## Updating the integrity manifest

After an intentional source or documentation change, regenerate the manifest:

```bash
./Scripts/update_manifest.sh
```

Do not hand-edit `MANIFEST.sha256`. The updater excludes Git metadata, local
build products, Xcode user data, and `.DS_Store` files.

## iOS build verification

The package tests do not replace an iOS target build. On macOS with Xcode, run:

```bash
xcodebuild \
  -project ColdcardQSimulator.xcodeproj \
  -scheme ColdcardQSimulator \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The latest recorded environment and result are in `Docs/VALIDATION-RESULTS.md`.

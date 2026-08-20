# Validation results

Date: 2026-08-18.

Environment:

- macOS 26.6.1;
- Xcode 26.6 (build 17F113);
- Apple Swift 6.3.3;
- iOS Simulator SDK 26.5;
- booted iPhone 17 Pro Max Simulator.

## Results

- `./Scripts/validate.sh`: passed all seven stages;
- 29 `ColdcardCore` tests passed with zero failures: 19 XCTest tests and 10
  Swift Testing tests;
- all iOS Swift sources parsed successfully;
- Xcode project references, plists, and asset-catalog JSON passed validation;
- all 103 files covered by `MANIFEST.sha256` matched their recorded hashes;
- `LICENSE-APACHE` matched the Apache Software Foundation's official
  Apache-2.0 text byte for byte;
- both retained Coldcard license copies matched the pinned upstream commit
  byte for byte;
- every vendored file in the declared 21-file BigInt subset and its MIT
  license matched upstream v6.0.0; `Codable.swift` is the sole upstream source
  file intentionally omitted from the subset;
- every app source, ColdcardCore source, and publishable PNG is represented in
  `Docs/LICENSE-SCOPE.md`;
- the app icon passed the 1024×1024 source check and Xcode emitted the expected
  120×120 iPhone and 152×152 iPad icon products;
- no Python source remains under `ThirdParty/`, and no CC BY-NC-ND source file
  remains in the publishable tree;
- no external SwiftPM dependency is used.

The iOS target was built with:

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

Result: `BUILD SUCCEEDED`.

A second build targeted the booted iPhone 17 Pro Max Simulator with Xcode's
local ad-hoc signature. It also completed with `BUILD SUCCEEDED`; the resulting
app installed and launched as `dev.thales.ColdcardQSimulator`, displayed the
current `COLDCARD Q SIMULATOR` title, and accessed the simulated Keychain
without the unsigned-build warning.

## Test coverage summary

- Base32 and multipart BBQr;
- BIP-39, BIP-32, and supported address families;
- hashes, HMAC, Base58Check, Bech32, and Bech32m;
- descriptors, exports, and compact message signing;
- secp256k1 and deterministic ECDSA;
- PSBT parsing/signing and security regressions;
- hardware-keyboard mappings.

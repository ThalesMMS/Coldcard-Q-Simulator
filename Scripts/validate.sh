#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[1/7] Swift package tests"
swift test -c debug

echo "[2/7] Parse iOS Swift sources"
swiftc -swift-version 5 -parse App/*.swift

echo "[3/7] Validate project references"
python3 Scripts/validate_project.py

echo "[4/7] Validate plists and asset JSON"
python3 - <<'PY'
import json, plistlib
from pathlib import Path
for plist in [Path('Info.plist'), Path('PrivacyInfo.xcprivacy'),
              Path('Resources/Settings.bundle/Root.plist'),
              Path('Resources/Settings.bundle/Acknowledgements.plist')]:
    with plist.open('rb') as fh: plistlib.load(fh)
for path in Path('Resources/Assets.xcassets').rglob('Contents.json'):
    json.loads(path.read_text())
print('plists/assets: OK')
PY

echo "[5/7] Required provenance and assets"
test -f LICENSE
test -f LICENSE-APACHE
test -f NOTICE.md
test -f README.md
test -f Docs/LICENSE-SCOPE.md
test -f ThirdParty/ColdcardFirmware/COPYING-CC
cmp -s ThirdParty/ColdcardFirmware/COPYING-CC ThirdParty/ColdcardFirmware/LICENSE
test -f ThirdParty/ColdcardFirmware/README.md
test -f ThirdParty/ColdcardFirmware/Reference/bip39-vectors.json
test -f ThirdParty/BigInt-LICENSE.md
test -f ThirdParty/BIP39-NOTICE.md
test -f ThirdParty/Bech32-LICENSE.md
test -f ThirdParty/BitcoinCore-LICENSE.md
third_party_python_sources="$(find ThirdParty -type f -name '*.py' -print)"
if [[ -n "$third_party_python_sources" ]]; then
    echo "Python source files must not be vendored under ThirdParty:" >&2
    printf '%s\n' "$third_party_python_sources" >&2
    exit 1
fi
grep -q '15de4a0c1a4587d8f6cf93b3763afbcbe0a7581c' Docs/PROVENANCE.md
grep -q 'Commons Clause' LICENSE
grep -q 'Apache-2.0 grant applies' LICENSE
grep -q 'Copyright 2026 Thales Matheus Mendonça Santos' LICENSE
grep -q 'OpenAI image tooling' Docs/PROVENANCE.md
coldcard_license_hash="$(shasum -a 256 ThirdParty/ColdcardFirmware/COPYING-CC | awk '{print $1}')"
test "$coldcard_license_hash" = 'af3e07181f14662155d76a57cffdfc24517aa279654e394a742eb4ee81adfd4e'
apache_license_hash="$(shasum -a 256 LICENSE-APACHE | awk '{print $1}')"
test "$apache_license_hash" = 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30'
for scoped_file in App/*.swift Sources/ColdcardCore/*.swift Resources/Assets.xcassets/*/*.png Docs/*.png; do
    if ! grep -Fq "$(basename "$scoped_file")" Docs/LICENSE-SCOPE.md; then
        echo "unmapped license scope: $scoped_file" >&2
        exit 1
    fi
done
test -f Resources/Assets.xcassets/q1-background.imageset/q1-background.png
app_icon='Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png'
test -f "$app_icon"
test "$(sips -g pixelWidth "$app_icon" | awk '/pixelWidth/ {print $2}')" = '1024'
test "$(sips -g pixelHeight "$app_icon" | awk '/pixelHeight/ {print $2}')" = '1024'
test -f ColdcardQSimulator.xcodeproj/project.pbxproj

echo "[6/7] Validate manifest coverage"
./Scripts/update_manifest.sh --check

echo "[7/7] Validate manifest hashes"
shasum -a 256 -c MANIFEST.sha256

echo "Validation complete."

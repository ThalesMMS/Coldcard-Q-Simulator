#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
pbx = root / "ColdcardQSimulator.xcodeproj" / "project.pbxproj"
text = pbx.read_text()

required_literals = [
    "PBXNativeTarget",
    "ColdcardQSimulator.app",
    "ColdcardCore in Frameworks",
    "XCLocalSwiftPackageReference",
    "Assets.xcassets in Resources",
    "PrivacyInfo.xcprivacy in Resources",
    "Settings.bundle in Resources",
    "INFOPLIST_FILE = Info.plist",
    "IPHONEOS_DEPLOYMENT_TARGET = 17.0",
]
for literal in required_literals:
    if literal not in text:
        raise SystemExit(f"missing project entry: {literal}")

for source in sorted((root / "App").glob("*.swift")):
    if text.count(source.name) < 2:
        raise SystemExit(f"app source is not wired into project: {source.name}")

# Every object identifier referenced by a plain 24-hex token must be defined,
# except identifiers appearing in comments or as rootObject references, which
# are still definitions elsewhere. This catches most hand-generated PBX errors.
defined = set(re.findall(r"^\s*([0-9A-F]{24})\b[^=\n]*=\s*\{", text, re.M))
referenced = set(re.findall(r"\b([0-9A-F]{24})\b", text))
missing = sorted(referenced - defined)
if missing:
    raise SystemExit("undefined PBX identifiers: " + ", ".join(missing))

if len(defined) != len(set(defined)):
    raise SystemExit("duplicate PBX identifiers")

print(f"project: OK ({len(defined)} objects, {len(list((root / 'App').glob('*.swift')))} app sources)")

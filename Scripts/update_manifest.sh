#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

manifest_tmp="$(mktemp /tmp/coldcard-q-manifest.XXXXXX)"
case "$manifest_tmp" in
    /tmp/coldcard-q-manifest.*) ;;
    *) echo "Unexpected temporary path: $manifest_tmp" >&2; exit 2 ;;
esac
test -n "$manifest_tmp" && test -f "$manifest_tmp"

find . \
    -path './.git' -prune -o \
    -path './.build' -prune -o \
    -path './.build-*' -prune -o \
    -path './DerivedData' -prune -o \
    -path '*/xcuserdata' -prune -o \
    -name '.DS_Store' -prune -o \
    -name 'MANIFEST.sha256' -prune -o \
    -type f -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256 > "$manifest_tmp"

if [[ "${1:-}" == "--check" ]]; then
    if ! cmp -s "$manifest_tmp" MANIFEST.sha256; then
        echo "MANIFEST.sha256 is stale; run ./Scripts/update_manifest.sh" >&2
        rm -f -- "$manifest_tmp"
        exit 1
    fi
    rm -f -- "$manifest_tmp"
    echo "manifest coverage: OK"
else
    mv -f -- "$manifest_tmp" MANIFEST.sha256
    echo "MANIFEST.sha256 updated"
fi


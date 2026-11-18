#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=2.10.1
SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
DEST="$ROOT/.build/sparkle-$VERSION"

if [[ ! -f "$DEST/Sparkle.framework/Sparkle" || ! -x "$DEST/bin/generate_appcast" ]]; then
    mkdir -p "$ROOT/.build"
    staging="$(mktemp -d "$ROOT/.build/sparkle.XXXXXX")"
    trap 'rm -rf "$staging"' EXIT
    curl --fail --location --silent --show-error --retry 2 \
        "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" \
        -o "$staging/Sparkle.tar.xz"
    printf '%s  %s\n' "$SHA256" "$staging/Sparkle.tar.xz" | shasum -a 256 -c - >&2
    mkdir -p "$DEST"
    tar -xJf "$staging/Sparkle.tar.xz" -C "$DEST"
fi

printf '%s\n' "$DEST"

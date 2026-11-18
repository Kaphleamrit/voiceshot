#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$SCRIPT_DIR/VoiceShot.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Building VoiceShot.app first..."
    "$SCRIPT_DIR/build.sh"
fi

DEST_DIR="$HOME/Applications"
mkdir -p "$DEST_DIR"

echo "Installing VoiceShot to $DEST_DIR/VoiceShot.app..."
rm -rf "$DEST_DIR/VoiceShot.app"
cp -R "$APP_PATH" "$DEST_DIR/VoiceShot.app"

echo "========================================"
echo "  ✅ Installed to ~/Applications/VoiceShot.app"
echo "  You can launch it anytime from Spotlight (Cmd + Space -> VoiceShot)"
echo "  or run: open ~/Applications/VoiceShot.app"
echo "========================================"

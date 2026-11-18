#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$SCRIPT_DIR/VoiceShot.app"

if [ ! -d "$APP_PATH" ]; then
    echo "VoiceShot.app not found. Building now..."
    "$SCRIPT_DIR/build.sh"
fi

echo "Launching VoiceShot..."
if [ "${1:-}" = "--monitor" ] || [ "${1:-}" = "-m" ]; then
    open "$APP_PATH" --args --monitor
else
    open "$APP_PATH"
fi

echo "VoiceShot is running in your menu bar (top right) 🎙️📸"

#!/usr/bin/env bash
set -euo pipefail

# VoiceShot Build Script for macOS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="VoiceShot"
BUNDLE_DIR="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [ "${1:-}" = "--if-needed" ] && [ -x "$MACOS_DIR/$APP_NAME" ]; then
    needs_build=false
    for source in build.sh scripts/fetch-sparkle.sh Info.plist Sources/*.swift Resources/AppIcon.icns; do
        if [ "$source" -nt "$MACOS_DIR/$APP_NAME" ]; then
            needs_build=true
            break
        fi
    done
    if [ "$needs_build" = false ]; then
        exit 0
    fi
fi

echo "========================================"
echo "  Building $APP_NAME for macOS"
echo "========================================"

# Determine SDK
if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
elif [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
else
    SDK_PATH="$(xcrun --show-sdk-path)"
fi
echo "Using SDK: $SDK_PATH"
SPARKLE_DIR="$(bash scripts/fetch-sparkle.sh)"

# Clean previous build
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$CONTENTS_DIR/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$CONTENTS_DIR/Frameworks/Sparkle.framework"

# Compile Swift sources
echo "Compiling Swift source files..."
export SDKROOT="$SDK_PATH"
swiftc -O \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx12.0 \
    -F "$SPARKLE_DIR" -framework Sparkle \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
    Sources/*.swift \
    -o "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
echo "Packaging Info.plist..."
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy AppIcon if present
if [ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]; then
    echo "Installing AppIcon.icns..."
    cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Ad-hoc code sign bundle for macOS arm64
echo "Code signing bundle..."
codesign --force --sign - "$BUNDLE_DIR"

echo "========================================"
echo "  ✅ Build succeeded!"
echo "  Bundle: $BUNDLE_DIR"
echo "========================================"

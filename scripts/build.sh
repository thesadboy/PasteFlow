#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

echo "🔨 [1/4] Compiling PasteFlow with Swift (Release mode)..."
swift build -c release

# Find the built executable
BIN_PATH=$(swift build -c release --show-bin-path)/PasteFlow

APP_BUNDLE="build/PasteFlow.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "📦 [2/4] Assembling macOS .app Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy binary
cp "$BIN_PATH" "$MACOS/PasteFlow"
chmod +x "$MACOS/PasteFlow"

# Copy Info.plist
cp "Resources/Info.plist" "$CONTENTS/Info.plist"

# Copy resources (AppIcon, sounds, etc.)
if [ -d "Resources/Assets" ]; then
    cp -R Resources/Assets/* "$RESOURCES/"
fi

# Strip debug symbols to reduce binary size
echo "✂️  Stripping debug symbols..."
strip -u -r "$MACOS/PasteFlow" 2>/dev/null || true

echo "🔏 [3/4] Code signing bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ [4/4] Successfully built PasteFlow.app at: $DIR/$APP_BUNDLE"

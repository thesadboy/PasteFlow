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

# Copy Frameworks (Sparkle.framework)
FRAMEWORKS="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS"

BIN_DIR="$(dirname "$BIN_PATH")"
if [ -d "$BIN_DIR/Sparkle.framework" ]; then
    echo "  📦 Embedding Sparkle.framework from $BIN_DIR..."
    cp -R "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS/"
elif [ -d "Frameworks/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]; then
    echo "  📦 Embedding Sparkle.framework from local xcframework..."
    cp -R "Frameworks/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORKS/"
else
    SPARKLE_FW=$(find .build -name "Sparkle.framework" -type d 2>/dev/null | head -n 1)
    if [ -n "$SPARKLE_FW" ]; then
        echo "  📦 Embedding Sparkle.framework from $SPARKLE_FW..."
        cp -R "$SPARKLE_FW" "$FRAMEWORKS/"
    fi
fi

# Ensure @executable_path/../Frameworks is in rpath
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/PasteFlow" 2>/dev/null || true

# Strip debug symbols to reduce binary size
echo "✂️  Stripping debug symbols and removing SDK headers..."
strip -u -r "$MACOS/PasteFlow" 2>/dev/null || true
rm -rf "$FRAMEWORKS/Sparkle.framework/Headers" "$FRAMEWORKS/Sparkle.framework/PrivateHeaders" "$FRAMEWORKS/Sparkle.framework/Versions/B/Headers" "$FRAMEWORKS/Sparkle.framework/Versions/B/PrivateHeaders" 2>/dev/null || true
strip -u -r "$FRAMEWORKS/Sparkle.framework/Versions/B/Sparkle" 2>/dev/null || true
strip -u -r "$FRAMEWORKS/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater" 2>/dev/null || true
strip -u -r "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/org.sparkle-project.Downloader.xpc/Contents/MacOS/org.sparkle-project.Downloader" 2>/dev/null || true
strip -u -r "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/org.sparkle-project.InstallerLauncher.xpc/Contents/MacOS/org.sparkle-project.InstallerLauncher" 2>/dev/null || true

echo "🔏 [3/4] Code signing bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ [4/4] Successfully built PasteFlow.app at: $DIR/$APP_BUNDLE"

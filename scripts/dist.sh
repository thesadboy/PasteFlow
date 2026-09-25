#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

APP_NAME="PasteFlow"
APP_BUNDLE="$DIR/build/$APP_NAME.app"
DIST_DIR="$DIR/dist"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING="$DIST_DIR/staging"

# Step 1: Build
"$DIR/scripts/build.sh"

# Step 2: Prepare dist directory
echo "🗂  Preparing distribution staging..."
rm -rf "$DIST_DIR"
mkdir -p "$STAGING"

# Copy app bundle into staging
cp -R "$APP_BUNDLE" "$STAGING/$APP_NAME.app"

# Create a symlink to /Applications for drag-and-drop install
ln -s /Applications "$STAGING/Applications"

# Step 3: Create DMG
echo "💿 [5/5] Creating DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" 2>/dev/null

# Cleanup staging
rm -rf "$STAGING"

# Cleanup build artifacts (.app bundle)
echo "🧹 Cleaning up build artifacts..."
rm -rf "$DIR/build"

echo ""
echo "✅ DMG created at: $DMG_PATH"
echo "   Size: $(du -sh "$DMG_PATH" | cut -f1)"

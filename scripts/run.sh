#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

# Build first
"$DIR/scripts/build.sh"

APP_BUNDLE="$DIR/build/PasteFlow.app"
INSTALL_PATH="/Applications/PasteFlow.app"

echo "📲 Installing to /Applications..."
# Kill any running instance first (both dev and installed)
pkill -9 -f "PasteFlow" 2>/dev/null || true
sleep 0.5

# Replace existing installation
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

echo "🚀 Launching PasteFlow from /Applications..."
open "$INSTALL_PATH"
echo "✨ PasteFlow is now running from /Applications! Press Cmd+Shift+V to toggle."

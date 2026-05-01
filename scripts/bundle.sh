#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="MOP"
APP_BUNDLE="$PROJECT_DIR/${APP_NAME}.app"
INSTALL_DEST="/Applications/${APP_NAME}.app"
INFO_PLIST="$PROJECT_DIR/Sources/Info.plist"

echo "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

BINARY="$PROJECT_DIR/.build/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found at $BINARY"
    exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [ -f "$PROJECT_DIR/Sources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

VERSION=$(defaults read "$INFO_PLIST" CFBundleShortVersionString 2>/dev/null || echo "?")
echo "Version: $VERSION"

echo "Installing to $INSTALL_DEST..."
rm -rf "$INSTALL_DEST"
cp -R "$APP_BUNDLE" "$INSTALL_DEST"

echo ""
echo "Done. MOP $VERSION installed to /Applications."

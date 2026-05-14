#!/usr/bin/env bash
# Usage: scripts/notarize.sh <path-to-app-bundle> <version>
# Prereqs: xcrun notarytool store-credentials "notary" --apple-id ... --team-id ... --password ...
set -euo pipefail

APP="$1"
VERSION="$2"
DIST_DIR="$(dirname "$0")/../dist"
mkdir -p "$DIST_DIR"

DMG="$DIST_DIR/MOP-${VERSION}.dmg"
ZIP="$DIST_DIR/MOP-${VERSION}.zip"

echo "=== Creating DMG ==="
hdiutil create -volname "MOP" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "=== Signing DMG ==="
codesign --sign "${DEVELOPER_ID_APP:?set DEVELOPER_ID_APP}" --timestamp "$DMG"

echo "=== Submitting for notarization (1–5 min) ==="
xcrun notarytool submit "$DMG" --keychain-profile "notary" --wait

echo "=== Stapling ticket ==="
xcrun stapler staple "$DMG"

echo "=== Creating ZIP for Sparkle ==="
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "=== Verifying ==="
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo "✅ dist/MOP-${VERSION}.{dmg,zip} ready"

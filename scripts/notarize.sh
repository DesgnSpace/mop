#!/usr/bin/env bash
# Usage: scripts/notarize.sh <path-to-app-bundle> <version>
# Apple credentials are 1Password references in .env.1password, resolved by op.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${MOP_OP_WRAPPED:-}" ]; then
    command -v op >/dev/null || { echo "Error: 1Password CLI (op) required"; exit 1; }
    MOP_OP_WRAPPED=1 exec op run --env-file="$ROOT/.env.1password" -- "$0" "$@"
fi
: "${APPLE_ID:?APPLE_ID required}"
: "${APPLE_PASSWORD:?APPLE_PASSWORD required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID required}"

APP="$1"
VERSION="$2"
DIST_DIR="$(dirname "$0")/../dist"
mkdir -p "$DIST_DIR"

DMG="$DIST_DIR/MOP-${VERSION}.dmg"
ZIP="$DIST_DIR/MOP-${VERSION}.zip"

echo "=== Creating DMG ==="
hdiutil create -volname "MOP" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "=== Signing DMG ==="
codesign --sign "${DEVELOPER_ID_APP:-$APPLE_SIGNING_IDENTITY}" --timestamp "$DMG"

echo "=== Submitting for notarization (1–5 min) ==="
xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait

echo "=== Stapling ticket ==="
xcrun stapler staple "$DMG"

echo "=== Creating ZIP for Sparkle ==="
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "=== Verifying ==="
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo "✅ dist/MOP-${VERSION}.{dmg,zip} ready"

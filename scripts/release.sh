#!/usr/bin/env bash
# Usage: scripts/release.sh <version> <path-to-zip>
# Signs the zip for Sparkle, appends a new <item> to landing/public/appcast.xml.
# Prereqs: Sparkle tools in .build/checkouts/Sparkle/bin/ or PATH
# Set SPARKLE_PRIVATE_KEY_FILE to the path of your EdDSA private key, or have it in Keychain.
set -euo pipefail

VERSION="$1"
ZIP="$2"
APPCAST="$(dirname "$0")/../landing/public/appcast.xml"
RELEASES_DIR="$(dirname "$0")/../RELEASES"
SPARKLE_BIN=".build/checkouts/Sparkle/bin"

[ -f "$ZIP" ] || { echo "Error: zip not found at $ZIP"; exit 1; }

echo "=== Signing ZIP for Sparkle ==="
SIG_OUTPUT=$("$SPARKLE_BIN/sign_update" "$ZIP")
SIGNATURE=$(echo "$SIG_OUTPUT" | grep 'sparkle:edSignature' | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')
LENGTH=$(echo "$SIG_OUTPUT" | grep 'length' | sed 's/.*length="\([^"]*\)".*/\1/')

echo "Signature: $SIGNATURE"
echo "Length:    $LENGTH"

# Release notes
NOTES_FILE="$RELEASES_DIR/${VERSION}.md"
if [ ! -f "$NOTES_FILE" ]; then
    echo "⚠️  No release notes at $NOTES_FILE — using placeholder"
    NOTES="<p>Bug fixes and improvements.</p>"
else
    NOTES=$(cat "$NOTES_FILE")
fi

# Build new <item>
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
BASE_URL="${RELEASE_BASE_URL:-https://mop.desgn.space/releases}"
ITEM="
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <description><![CDATA[${NOTES}]]></description>
            <enclosure
                url=\"${BASE_URL}/MOP-${VERSION}.zip\"
                sparkle:version=\"${VERSION}\"
                sparkle:shortVersionString=\"${VERSION}\"
                sparkle:edSignature=\"${SIGNATURE}\"
                length=\"${LENGTH}\"
                type=\"application/octet-stream\" />
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        </item>"

# Inject before </channel>
if [ -f "$APPCAST" ]; then
    sed -i '' "s|</channel>|${ITEM}\n    </channel>|" "$APPCAST"
else
    echo "⚠️  No appcast at $APPCAST — create landing/ first"
    exit 1
fi

echo "✅ appcast.xml updated with v${VERSION}"
echo "Next: upload MOP-${VERSION}.zip to ${BASE_URL}/ and deploy landing/"

#!/usr/bin/env bash
# Usage: scripts/release.sh <version> <path-to-zip>
# Signs the Sparkle ZIP, uploads release artifacts to Cloudflare R2, publishes
# releases.json + appcast.xml, then optionally triggers the landing deploy hook.
set -euo pipefail

VERSION="${1:?version required}"
ZIP="${2:?zip path required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${ZIP%.zip}.dmg"
RELEASES_DIR="$ROOT/RELEASES"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-14.0}"

if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID required}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID required}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY required}"
: "${R2_BUCKET:?R2_BUCKET required}"
: "${R2_PUBLIC_BASE_URL:?R2_PUBLIC_BASE_URL required}"

[ -f "$ZIP" ] || { echo "Error: zip not found at $ZIP"; exit 1; }
[ -f "$DMG" ] || { echo "Error: dmg not found at $DMG"; exit 1; }
command -v aws >/dev/null || { echo "Error: aws CLI required for R2 upload"; exit 1; }
command -v bun >/dev/null || { echo "Error: bun required for release metadata"; exit 1; }
[ -x "$SPARKLE_BIN/sign_update" ] || { echo "Error: Sparkle sign_update not found at $SPARKLE_BIN/sign_update"; exit 1; }

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"
export AWS_EC2_METADATA_DISABLED="true"
unset AWS_PROFILE AWS_DEFAULT_PROFILE

BASE_URL="${R2_PUBLIC_BASE_URL%/}"
ENDPOINT_URL="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
NOTES_FILE="$RELEASES_DIR/${VERSION}.md"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [ ! -f "$NOTES_FILE" ]; then
    echo "Error: no release notes at $NOTES_FILE"
    exit 1
fi

echo "=== Signing ZIP for Sparkle ==="
SIGN_UPDATE_ARGS=("$ZIP")
if [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    SIGN_UPDATE_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
elif [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    SIGN_UPDATE_ARGS+=(--ed-key-file -)
fi
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ] && [ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    SIG_OUTPUT=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/sign_update" "${SIGN_UPDATE_ARGS[@]}")
else
    SIG_OUTPUT=$("$SPARKLE_BIN/sign_update" "${SIGN_UPDATE_ARGS[@]}")
fi
SIGNATURE=$(printf '%s\n' "$SIG_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(printf '%s\n' "$SIG_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
[ -n "$SIGNATURE" ] || { echo "Error: failed to parse Sparkle signature"; exit 1; }
[ -n "$LENGTH" ] || { echo "Error: failed to parse Sparkle length"; exit 1; }

DMG_NAME="MOP-${VERSION}.dmg"
ZIP_NAME="MOP-${VERSION}.zip"
DMG_URL="${BASE_URL}/${DMG_NAME}"
ZIP_URL="${BASE_URL}/${ZIP_NAME}"

echo "=== Uploading release artifacts to R2 ==="
aws s3 cp "$DMG" "s3://${R2_BUCKET}/${DMG_NAME}" \
    --endpoint-url "$ENDPOINT_URL" \
    --content-type "application/x-apple-diskimage" \
    --cache-control "public, max-age=31536000, immutable"
aws s3 cp "$ZIP" "s3://${R2_BUCKET}/${ZIP_NAME}" \
    --endpoint-url "$ENDPOINT_URL" \
    --content-type "application/zip" \
    --cache-control "public, max-age=31536000, immutable"

EXISTING_JSON="$TMP_DIR/releases-existing.json"
if curl -fsS "${BASE_URL}/releases.json" -o "$EXISTING_JSON"; then
    echo "Found existing releases.json"
else
    printf '{"latest":"","releases":[]}\n' > "$EXISTING_JSON"
fi

RELEASES_JSON="$TMP_DIR/releases.json"
APPCAST_XML="$TMP_DIR/appcast.xml"

VERSION="$VERSION" \
DMG_URL="$DMG_URL" \
ZIP_URL="$ZIP_URL" \
ZIP_LENGTH="$LENGTH" \
SPARKLE_SIGNATURE="$SIGNATURE" \
MINIMUM_SYSTEM_VERSION="$MINIMUM_SYSTEM_VERSION" \
NOTES_FILE="$NOTES_FILE" \
EXISTING_JSON="$EXISTING_JSON" \
RELEASES_JSON="$RELEASES_JSON" \
APPCAST_XML="$APPCAST_XML" \
BASE_URL="$BASE_URL" \
bun run --silent - <<'EOF'
import { readFileSync, writeFileSync } from "fs";

const env = process.env;
const notesMarkdown = readFileSync(env.NOTES_FILE!, "utf8").trim();
const existing = JSON.parse(readFileSync(env.EXISTING_JSON!, "utf8"));

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function escapeXml(value: string) {
  return escapeHtml(value).replaceAll("'", "&apos;");
}

function markdownToHtml(markdown: string) {
  const lines = markdown.split(/\r?\n/);
  const html: string[] = [];
  let inList = false;

  for (const line of lines) {
    if (line.startsWith("## ")) {
      if (inList) {
        html.push("</ul>");
        inList = false;
      }
      html.push(`<h2>${escapeHtml(line.slice(3))}</h2>`);
      continue;
    }

    if (line.startsWith("- ")) {
      if (!inList) {
        html.push("<ul>");
        inList = true;
      }
      html.push(`<li>${escapeHtml(line.slice(2))}</li>`);
      continue;
    }

    if (line.trim() === "") {
      continue;
    }

    if (inList) {
      html.push("</ul>");
      inList = false;
    }
    html.push(`<p>${escapeHtml(line)}</p>`);
  }

  if (inList) {
    html.push("</ul>");
  }

  return html.join("\n");
}

const release = {
  version: env.VERSION!,
  date: new Date().toISOString(),
  dmgUrl: env.DMG_URL!,
  zipUrl: env.ZIP_URL!,
  zipLength: Number(env.ZIP_LENGTH!),
  sparkleSignature: env.SPARKLE_SIGNATURE!,
  minimumSystemVersion: env.MINIMUM_SYSTEM_VERSION!,
  notesMarkdown,
  notesHtml: markdownToHtml(notesMarkdown),
};

const releases = [
  release,
  ...(existing.releases ?? []).filter((item: { version?: string }) => item.version !== release.version),
].sort((a, b) => b.version.localeCompare(a.version, undefined, { numeric: true }));

writeFileSync(env.RELEASES_JSON!, JSON.stringify({ latest: releases[0]?.version ?? release.version, releases }, null, 2) + "\n");

const items = releases.map((item) => `        <item>
            <title>Version ${escapeXml(item.version)}</title>
            <pubDate>${new Date(item.date).toUTCString()}</pubDate>
            <description><![CDATA[${item.notesHtml}]]></description>
            <enclosure
                url="${escapeXml(item.zipUrl)}"
                sparkle:version="${escapeXml(item.version)}"
                sparkle:shortVersionString="${escapeXml(item.version)}"
                sparkle:edSignature="${escapeXml(item.sparkleSignature)}"
                length="${item.zipLength}"
                type="application/octet-stream" />
            <sparkle:minimumSystemVersion>${escapeXml(item.minimumSystemVersion)}</sparkle:minimumSystemVersion>
        </item>`).join("\n");

writeFileSync(env.APPCAST_XML!, `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>MOP Changelog</title>
        <link>${escapeXml(env.BASE_URL ?? "")}/appcast.xml</link>
        <description>MOP release history</description>
        <language>en</language>
${items}
    </channel>
</rss>
`);
EOF

echo "=== Publishing release metadata to R2 ==="
aws s3 cp "$RELEASES_JSON" "s3://${R2_BUCKET}/releases.json" \
    --endpoint-url "$ENDPOINT_URL" \
    --content-type "application/json" \
    --cache-control "public, max-age=60"
aws s3 cp "$APPCAST_XML" "s3://${R2_BUCKET}/appcast.xml" \
    --endpoint-url "$ENDPOINT_URL" \
    --content-type "application/rss+xml" \
    --cache-control "public, max-age=60"

DEPLOY_HOOK_URL="${CLOUDFLARE_DEPLOY_HOOK_URL:-${DEPLOY_HOOK_URL:-${VERCEL_DEPLOY_HOOK_URL:-}}}"
if [ -n "$DEPLOY_HOOK_URL" ]; then
    echo "=== Triggering landing deploy ==="
    if ! curl -fsS -X POST "$DEPLOY_HOOK_URL" >/dev/null; then
        echo "⚠️  Deploy hook failed. R2 release was still published."
    fi
fi

echo "✅ Published MOP ${VERSION}"
echo "DMG: ${DMG_URL}"
echo "Appcast: ${BASE_URL}/appcast.xml"

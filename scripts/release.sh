#!/usr/bin/env bash
# Usage: scripts/release.sh [--dry-run] <version> <path-to-zip>
# Signs the Sparkle ZIP, uploads release artifacts to Cloudflare R2 under the
# shared bucket's mop/ prefix (served at https://downloads.desgn.space), and
# publishes releases.json + appcast.xml + latest + install.sh. Mirrors the
# appcast to the legacy bucket so pre-migration installs keep updating.
# Also regenerates Casks/mop.rb with the new version and sha256.
#
# Dry run: pass --dry-run or set RELEASE_DRY_RUN=1 to print the upload plan
# and key layout without uploading or needing credentials.
set -euo pipefail

DRY_RUN="${RELEASE_DRY_RUN:-0}"
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]}"

VERSION="${1:?version required}"
ZIP="${2:?zip path required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${ZIP%.zip}.dmg"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-14.0}"

if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi

# Shared download host + key prefix. Every MOP object lives under mop/.
PUBLIC_BASE_URL="${R2_PUBLIC_BASE_URL:-https://downloads.desgn.space}"
KEY_PREFIX="${R2_KEY_PREFIX:-mop}"
# Pre-migration installs still poll the old domain for appcast.xml; when
# R2_LEGACY_BUCKET is set, the new appcast is mirrored there for the transition.
LEGACY_BUCKET="${R2_LEGACY_BUCKET:-}"
LEGACY_BASE_URL="${R2_LEGACY_PUBLIC_BASE_URL:-https://downloads.mop.desgn.space}"

[ -f "$ZIP" ] || { echo "Error: zip not found at $ZIP"; exit 1; }
[ -f "$DMG" ] || { echo "Error: dmg not found at $DMG"; exit 1; }

BASE_URL="${PUBLIC_BASE_URL%/}"
DMG_NAME="MOP-${VERSION}.dmg"
ZIP_NAME="MOP-${VERSION}.zip"
DMG_KEY="${KEY_PREFIX}/${DMG_NAME}"
ZIP_KEY="${KEY_PREFIX}/${ZIP_NAME}"
RELEASES_JSON_KEY="${KEY_PREFIX}/releases.json"
APPCAST_KEY="${KEY_PREFIX}/appcast.xml"
LATEST_KEY="${KEY_PREFIX}/latest"
INSTALL_SH_KEY="${KEY_PREFIX}/install.sh"

echo "=== MOP ${VERSION} release ==="
echo "Bucket s3://${R2_BUCKET:-<R2_BUCKET unset>}, public ${BASE_URL}:"
for key in "$DMG_KEY" "$ZIP_KEY" "$RELEASES_JSON_KEY" "$APPCAST_KEY" "$LATEST_KEY" "$INSTALL_SH_KEY"; do
    echo "  ${key} -> ${BASE_URL}/${key}"
done

ZIP_SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

CASK_FILE="$ROOT/Casks/mop.rb"
mkdir -p "$(dirname "$CASK_FILE")"
cat > "$CASK_FILE" <<EOF
cask "mop" do
  version "${VERSION}"
  sha256 "${ZIP_SHA256}"

  url "${BASE_URL}/${KEY_PREFIX}/MOP-#{version}.zip"
  name "MOP"
  desc "Voice-to-text for macOS that runs entirely on your machine"
  homepage "https://mop.desgn.space"

  livecheck do
    url "${BASE_URL}/${KEY_PREFIX}/releases.json"
    strategy :json do |json|
      json["latest"]
    end
  end

  depends_on macos: ">= :sonoma"

  app "MOP.app"
end
EOF
echo "Regenerated ${CASK_FILE} for ${VERSION}"

if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "=== Dry run: planned uploads to s3://${R2_BUCKET:-<R2_BUCKET unset>} ==="
    echo "[dry-run] aws s3 cp \"$DMG\" -> ${DMG_KEY}"
    echo "[dry-run] aws s3 cp \"$ZIP\" -> ${ZIP_KEY}"
    echo "[dry-run] aws s3 cp releases.json -> ${RELEASES_JSON_KEY}"
    echo "[dry-run] aws s3 cp appcast.xml -> ${APPCAST_KEY}"
    echo "[dry-run] aws s3 cp latest pointer -> ${LATEST_KEY}"
    echo "[dry-run] aws s3 cp scripts/install.sh -> ${INSTALL_SH_KEY}"
    if [ -n "$LEGACY_BUCKET" ]; then
        echo "[dry-run] aws s3 cp appcast.xml -> s3://${LEGACY_BUCKET}/appcast.xml (legacy mirror)"
    else
        echo "[dry-run] legacy appcast mirror SKIPPED (R2_LEGACY_BUCKET unset)"
        echo "[dry-run] Existing installs checking ${LEGACY_BASE_URL}/appcast.xml will not see this release."
    fi
    echo "✅ Dry run complete. Nothing was uploaded."
    exit 0
fi

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID required}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID required}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY required}"
: "${R2_BUCKET:?R2_BUCKET required}"
command -v aws >/dev/null || { echo "Error: aws CLI required for R2 upload"; exit 1; }
command -v bun >/dev/null || { echo "Error: bun required for release metadata"; exit 1; }
[ -x "$SPARKLE_BIN/sign_update" ] || { echo "Error: Sparkle sign_update not found at $SPARKLE_BIN/sign_update"; exit 1; }

ENDPOINT_URL="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"
export AWS_EC2_METADATA_DISABLED="true"
unset AWS_PROFILE AWS_DEFAULT_PROFILE

upload() {
    local file="$1" key="$2" content_type="$3" cache_control="$4"
    aws s3 cp "$file" "s3://${R2_BUCKET}/${key}" \
        --endpoint-url "$ENDPOINT_URL" \
        --content-type "$content_type" \
        --cache-control "$cache_control"
}

LAST_TAG=$(git -C "$ROOT" tag --sort=-v:refname | grep -v "^v${VERSION}$" | head -1)
if [ -n "$LAST_TAG" ]; then
    NOTES_MARKDOWN="$(git -C "$ROOT" log "${LAST_TAG}..HEAD" --pretty=format:"- %s" --no-merges)"
else
    NOTES_MARKDOWN="$(git -C "$ROOT" log --pretty=format:"- %s" --no-merges | head -20)"
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

echo "=== Uploading release artifacts to R2 ==="
upload "$DMG" "$DMG_KEY" "application/x-apple-diskimage" "public, max-age=31536000, immutable"
upload "$ZIP" "$ZIP_KEY" "application/zip" "public, max-age=31536000, immutable"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

EXISTING_JSON="$TMP_DIR/releases-existing.json"
if curl -fsS "${BASE_URL}/${RELEASES_JSON_KEY}" -o "$EXISTING_JSON"; then
    echo "Found existing releases.json"
else
    printf '{"latest":"","releases":[]}\n' > "$EXISTING_JSON"
fi

RELEASES_JSON="$TMP_DIR/releases.json"
APPCAST_XML="$TMP_DIR/appcast.xml"
LATEST_JSON="$TMP_DIR/latest.json"

VERSION="$VERSION" \
DMG_URL="${BASE_URL}/${DMG_KEY}" \
ZIP_URL="${BASE_URL}/${ZIP_KEY}" \
ZIP_LENGTH="$LENGTH" \
SPARKLE_SIGNATURE="$SIGNATURE" \
MINIMUM_SYSTEM_VERSION="$MINIMUM_SYSTEM_VERSION" \
NOTES_MARKDOWN="$NOTES_MARKDOWN" \
EXISTING_JSON="$EXISTING_JSON" \
RELEASES_JSON="$RELEASES_JSON" \
APPCAST_XML="$APPCAST_XML" \
LATEST_JSON="$LATEST_JSON" \
APPCAST_LINK="${BASE_URL}/${APPCAST_KEY}" \
bun run --silent - <<'EOF'
import { readFileSync, writeFileSync } from "fs";

const env = process.env;
const notesMarkdown = (env.NOTES_MARKDOWN ?? "").trim();
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

// Stable pointer the install script resolves: single line, no jq needed.
writeFileSync(
  env.LATEST_JSON!,
  JSON.stringify({
    version: release.version,
    url: release.zipUrl,
    dmgUrl: release.dmgUrl,
    releasedAt: release.date,
  }) + "\n",
);

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
        <link>${escapeXml(env.APPCAST_LINK ?? "")}</link>
        <description>MOP release history</description>
        <language>en</language>
${items}
    </channel>
</rss>
`);
EOF

echo "=== Publishing release metadata to R2 ==="
upload "$RELEASES_JSON" "$RELEASES_JSON_KEY" "application/json" "public, max-age=60"
upload "$APPCAST_XML" "$APPCAST_KEY" "application/rss+xml" "public, max-age=60"
upload "$LATEST_JSON" "$LATEST_KEY" "application/json" "public, max-age=300"
upload "$ROOT/scripts/install.sh" "$INSTALL_SH_KEY" "text/x-shellscript" "public, max-age=300"

if [ -n "$LEGACY_BUCKET" ]; then
    echo "=== Mirroring appcast to legacy bucket ==="
    aws s3 cp "$APPCAST_XML" "s3://${LEGACY_BUCKET}/appcast.xml" \
        --endpoint-url "$ENDPOINT_URL" \
        --content-type "application/rss+xml" \
        --cache-control "public, max-age=60"
else
    echo "⚠️  R2_LEGACY_BUCKET is not set."
    echo "⚠️  Installs still checking ${LEGACY_BASE_URL}/appcast.xml will NOT see this release."
fi

DEPLOY_HOOK_URL="${CLOUDFLARE_DEPLOY_HOOK_URL:-${DEPLOY_HOOK_URL:-${VERCEL_DEPLOY_HOOK_URL:-}}}"
if [ -n "$DEPLOY_HOOK_URL" ]; then
    echo "=== Triggering landing deploy ==="
    if ! curl -fsS -X POST "$DEPLOY_HOOK_URL" >/dev/null; then
        echo "⚠️  Deploy hook failed. R2 release was still published."
    fi
fi

echo ""
echo "✅ Published MOP ${VERSION} to ${BASE_URL}/${KEY_PREFIX}/"
echo "Install:   curl -fsSL ${BASE_URL}/${INSTALL_SH_KEY} | sh"
echo "Appcast:   ${BASE_URL}/${APPCAST_KEY}"
echo "Cask:      ${CASK_FILE} — copy it into the desgn-space/homebrew-tap repo to publish"

#!/usr/bin/env bash
# Usage: scripts/publish.sh [major|minor|fix] [--dry-run]
# Bumps VERSION, drafts release notes from git log, then runs make publish.
# With --dry-run the release plan is printed and nothing is uploaded or tagged.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Current version (from last tag) ───────────────────────────────────────────
LAST_TAG=$(git tag --sort=-v:refname | head -1)
CURRENT="${LAST_TAG#v}"
if [ -z "$CURRENT" ]; then CURRENT="0.0.0"; fi
MAJOR=$(echo "$CURRENT" | cut -d. -f1)
MINOR=$(echo "$CURRENT" | cut -d. -f2)
PATCH=$(echo "$CURRENT" | cut -d. -f3)

# ── Bump type ─────────────────────────────────────────────────────────────────
BUMP=""
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        major|minor|fix) BUMP="$arg" ;;
        --dry-run)       DRY_RUN=1 ;;
        *)               echo "Usage: $0 [major|minor|fix] [--dry-run]"; exit 1 ;;
    esac
done

if [ -z "$BUMP" ]; then
    echo "Current version: $CURRENT"
    echo ""
    echo "Release type:"
    echo "  1) major  → $((MAJOR + 1)).0.0"
    echo "  2) minor  → ${MAJOR}.$((MINOR + 1)).0"
    echo "  3) fix    → ${MAJOR}.${MINOR}.$((PATCH + 1))"
    printf "Choice [1/2/3]: "
    read -r CHOICE
    case "$CHOICE" in
        1) BUMP=major ;;
        2) BUMP=minor ;;
        3) BUMP=fix   ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

case "$BUMP" in
    major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
    minor) NEW_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
    fix)   NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
    *)     echo "Usage: $0 [major|minor|fix]"; exit 1 ;;
esac

echo ""
echo "Bumping $CURRENT → $NEW_VERSION"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
printf "Publish MOP %s? [y/N]: " "$NEW_VERSION"
read -r CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Build + upload release ────────────────────────────────────────────────────
SIGN_ID="${DEVELOPER_ID_APP:-DesgnSpace}"
if [ "$DRY_RUN" = "1" ]; then
    # Rehearsal: build locally and print the upload plan. No notarization,
    # no upload, no tag.
    RELEASE_DRY_RUN=1 make _publish_dev VERSION="$NEW_VERSION" DEVELOPER_ID_APP="$SIGN_ID"
    echo "Dry run complete. Skipped tagging v$NEW_VERSION."
    exit 0
fi
if [[ "$SIGN_ID" == Developer\ ID\ Application:* ]]; then
    make _publish VERSION="$NEW_VERSION" DEVELOPER_ID_APP="$SIGN_ID"
else
    make _publish_dev VERSION="$NEW_VERSION" DEVELOPER_ID_APP="$SIGN_ID"
fi

# ── Tag after upload succeeds ─────────────────────────────────────────────────
git tag "v$NEW_VERSION"
git push origin "v$NEW_VERSION"

#!/usr/bin/env bash
# Usage: scripts/publish.sh [major|minor|fix]
# Bumps VERSION, drafts release notes from git log, then runs make publish.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Current version ────────────────────────────────────────────────────────────
CURRENT=$(cat VERSION)
MAJOR=$(echo "$CURRENT" | cut -d. -f1)
MINOR=$(echo "$CURRENT" | cut -d. -f2)
PATCH=$(echo "$CURRENT" | cut -d. -f3)

# ── Bump type ─────────────────────────────────────────────────────────────────
BUMP="${1:-}"
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

# ── Draft release notes ────────────────────────────────────────────────────────
NOTES_FILE="RELEASES/${NEW_VERSION}.md"
LAST_TAG=$(git tag --sort=-v:refname | head -1)

if [ ! -f "$NOTES_FILE" ]; then
    {
        echo "## What's new in $NEW_VERSION"
        echo ""
        if [ -n "$LAST_TAG" ]; then
            git log "${LAST_TAG}..HEAD" --pretty=format:"- %s" --no-merges
        else
            git log --pretty=format:"- %s" --no-merges | head -20
        fi
        echo ""
    } > "$NOTES_FILE"
fi

# Open for editing
EDITOR="${EDITOR:-nano}"
echo "Opening release notes in $EDITOR... (save + close to continue)"
"$EDITOR" "$NOTES_FILE"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$NOTES_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "Publish MOP %s? [y/N]: " "$NEW_VERSION"
read -r CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Write VERSION + tag ───────────────────────────────────────────────────────
echo "$NEW_VERSION" > VERSION
git tag "v$NEW_VERSION"

# ── Run make publish ──────────────────────────────────────────────────────────
SIGN_ID="${DEVELOPER_ID_APP:-DesgnSpace}"
if [[ "$SIGN_ID" == Developer\ ID\ Application:* ]]; then
    make _publish VERSION="$NEW_VERSION" DEVELOPER_ID_APP="$SIGN_ID"
else
    make _publish_dev VERSION="$NEW_VERSION" DEVELOPER_ID_APP="$SIGN_ID"
fi

git push origin "v$NEW_VERSION"

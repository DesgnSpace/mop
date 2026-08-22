#!/bin/sh
# MOP installer: curl -fsSL https://downloads.desgn.space/mop/install.sh | sh
# Installs or upgrades MOP.app in /Applications (falls back to ~/Applications).
set -eu

BASE_URL="https://downloads.desgn.space/mop"
APP_NAME="MOP"

say() {
    printf '%s\n' "$*"
}

case "$(uname -s)" in
    Darwin) ;;
    *)
        say "This installer needs macOS."
        say "To build MOP from source on another system:"
        say "  git clone https://github.com/desgn-space/mop.git && cd mop && swift build && swift run MOP"
        exit 1
        ;;
esac

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="$(printf '%s' "$MACOS_VERSION" | cut -d. -f1)"
if [ "$MACOS_MAJOR" -lt 14 ]; then
    say "MOP needs macOS 14.0 or later. This Mac has ${MACOS_VERSION}."
    exit 1
fi

command -v curl >/dev/null || { say "curl is required but was not found. Install it and run this again."; exit 1; }
command -v ditto >/dev/null || { say "ditto is required but was not found. Install the macOS command line tools and run this again."; exit 1; }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mop-install.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

say "Resolving the latest MOP version..."
LATEST_JSON="$(curl -fsSL "${BASE_URL}/latest")" || {
    say "Could not reach ${BASE_URL}/latest. Check your connection and try again."
    exit 1
}
VERSION="$(printf '%s' "$LATEST_JSON" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
DOWNLOAD_URL="$(printf '%s' "$LATEST_JSON" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
[ -n "$VERSION" ] || { say "Could not read the latest version from the server. Try again in a few minutes."; exit 1; }
[ -n "$DOWNLOAD_URL" ] || DOWNLOAD_URL="${BASE_URL}/${APP_NAME}-${VERSION}.zip"

say "Downloading MOP ${VERSION}..."
ZIP_PATH="${TMP_DIR}/${APP_NAME}-${VERSION}.zip"
curl -fsSL --retry 3 -o "$ZIP_PATH" "$DOWNLOAD_URL" || {
    say "Download failed from ${DOWNLOAD_URL}. Check your connection and run this again."
    exit 1
}

say "Unpacking..."
mkdir -p "${TMP_DIR}/app"
ditto -x -k "$ZIP_PATH" "${TMP_DIR}/app"
[ -d "${TMP_DIR}/app/${APP_NAME}.app" ] || {
    say "The download did not contain ${APP_NAME}.app. Nothing was installed."
    exit 1
}

DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="${HOME}/Applications"
    mkdir -p "$DEST"
fi

rm -rf "${DEST}/${APP_NAME}.app"
cp -R "${TMP_DIR}/app/${APP_NAME}.app" "${DEST}/${APP_NAME}.app"
xattr -dr com.apple.quarantine "${DEST}/${APP_NAME}.app" 2>/dev/null || true

say ""
say "MOP ${VERSION} installed in ${DEST}/${APP_NAME}.app"
say ""
say "Next steps:"
say "  1. Open MOP — it lives in your menu bar as a waveform icon."
say "  2. Allow Microphone access when prompted:"
say "     System Settings > Privacy & Security > Microphone"
say "  3. Add MOP under Accessibility so hotkeys and auto-paste work:"
say "     System Settings > Privacy & Security > Accessibility"

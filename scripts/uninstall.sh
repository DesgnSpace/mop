#!/bin/bash
set -euo pipefail

LAUNCHD_LABEL="com.super-voice-assistant"
INSTALL_PATH="/usr/local/bin/super-voice-assistant"
PLIST_PATH="$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"

echo "Unloading launchd service..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true

echo "Removing launchd plist..."
rm -f "$PLIST_PATH"

echo "Removing binary..."
sudo rm -f "$INSTALL_PATH"

echo "Removing logs..."
rm -f "$HOME/Library/Logs/super-voice-assistant.log"
rm -f "$HOME/Library/Logs/super-voice-assistant.err"

echo ""
echo "Super Voice Assistant has been uninstalled."
echo "Note: Keyboard shortcut preferences are stored in ~/Library/Preferences and will be"
echo "removed automatically if unused. Run 'defaults delete com.super-voice-assistant' to clean up."
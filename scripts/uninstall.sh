#!/bin/bash
set -euo pipefail

LAUNCHD_LABEL="com.mop"
INSTALL_PATH="/usr/local/bin/mop"
PLIST_PATH="$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"

echo "Unloading launchd service..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true

echo "Removing launchd plist..."
rm -f "$PLIST_PATH"

echo "Removing binary..."
sudo rm -f "$INSTALL_PATH"

echo "Removing logs..."
rm -f "$HOME/Library/Logs/mop.log"
rm -f "$HOME/Library/Logs/mop.err"

echo ""
echo "MOP has been uninstalled."
echo "Note: Keyboard shortcut preferences are stored in ~/Library/Preferences and will be"
echo "removed automatically if unused. Run 'defaults delete com.mop' to clean up."
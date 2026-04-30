#!/bin/bash
set -euo pipefail

LAUNCHD_LABEL="com.mop"
PLIST_PATH="$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"
INSTALL_PATH="/usr/local/bin/mop"

if pgrep -x "MOP" &>/dev/null; then
    echo "MOP is already running."
    exit 0
fi

if [ -f "$PLIST_PATH" ]; then
    echo "Starting MOP via launchd..."
    GUI_DOMAIN="gui/$(id -u)"
    if launchctl print "${GUI_DOMAIN}/${LAUNCHD_LABEL}" &>/dev/null; then
        launchctl kickstart "${GUI_DOMAIN}/${LAUNCHD_LABEL}"
    else
        launchctl bootstrap "$GUI_DOMAIN" "$PLIST_PATH"
    fi
    echo "MOP started. Logs: ~/Library/Logs/mop.log"
elif [ -f "$INSTALL_PATH" ]; then
    echo "Starting MOP directly..."
    "$INSTALL_PATH" &
    echo "MOP started (PID $!)."
else
    echo "MOP not installed. Run scripts/install.sh first."
    exit 1
fi

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY_NAME="SuperVoiceAssistant"
INSTALL_PATH="/usr/local/bin/super-voice-assistant"
LAUNCHD_LABEL="com.super-voice-assistant"
PLIST_PATH="$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"

echo "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

BUILT_BINARY="$PROJECT_DIR/.build/release/$BINARY_NAME"

if [ ! -f "$BUILT_BINARY" ]; then
    echo "Error: Built binary not found at $BUILT_BINARY"
    exit 1
fi

echo "Installing binary to $INSTALL_PATH..."
sudo cp "$BUILT_BINARY" "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

echo "Creating launchd plist..."
mkdir -p "$(dirname "$PLIST_PATH")"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCHD_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/super-voice-assistant.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/super-voice-assistant.err</string>
</dict>
</plist>
EOF

echo "Loading launchd service..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

# Migrate data from old locations
APP_DATA="$HOME/Library/Application Support/SuperVoiceAssistant"
OLD_DOCS="$HOME/Documents/SuperVoiceAssistant"
OLD_WHISPERKIT="$HOME/Documents/huggingface/models/argmaxinc/whisperkit-coreml"
OLD_PARAKEET_FLUID="$HOME/Library/Application Support/FluidAudio/Models"
OLD_PARAKEET_DOCS="$HOME/Documents/FluidAudio"

if [ -d "$OLD_DOCS" ]; then
    echo "Migrating app data from $OLD_DOCS..."
    mkdir -p "$APP_DATA"
    [ -f "$OLD_DOCS/transcription_history.json" ] && cp "$OLD_DOCS/transcription_history.json" "$APP_DATA/" 2>/dev/null || true
    [ -f "$OLD_DOCS/transcription_stats.json" ] && cp "$OLD_DOCS/transcription_stats.json" "$APP_DATA/" 2>/dev/null || true
fi

if [ -d "$OLD_WHISPERKIT" ]; then
    echo "Migrating WhisperKit models from $OLD_WHISPERKIT..."
    mkdir -p "$APP_DATA/Models/WhisperKit"
    cp -R "$OLD_WHISPERKIT/"* "$APP_DATA/Models/WhisperKit/" 2>/dev/null || true
fi

if [ -d "$OLD_PARAKEET_FLUID" ]; then
    echo "Migrating Parakeet models from $OLD_PARAKEET_FLUID..."
    mkdir -p "$APP_DATA/Models/Parakeet"
    for dir in "$OLD_PARAKEET_FLUID"/parakeet-tdt-*-coreml; do
        [ -d "$dir" ] && cp -R "$dir" "$APP_DATA/Models/Parakeet/" 2>/dev/null || true
    done
elif [ -d "$OLD_PARAKEET_DOCS" ]; then
    echo "Migrating Parakeet models from $OLD_PARAKEET_DOCS..."
    mkdir -p "$APP_DATA/Models/Parakeet"
    for dir in "$OLD_PARAKEET_DOCS"/parakeet-tdt-*; do
        if [ -d "$dir" ]; then
            dirname=$(basename "$dir")
            cp -R "$dir" "$APP_DATA/Models/Parakeet/${dirname}-coreml" 2>/dev/null || true
        fi
    done
fi

echo ""
echo "Super Voice Assistant installed and configured to auto-launch on login."
echo "  Binary:  $INSTALL_PATH"
echo "  Plist:   $PLIST_PATH"
echo "  Logs:    ~/Library/Logs/super-voice-assistant.log"
echo ""
echo "To uninstall, run: scripts/uninstall.sh"
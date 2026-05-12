# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build
swift build

# Run (debug)
swift run MOP

# Release bundle → installs to /Applications
make bundle

# Install as launchd service
make install

# Run a specific test target
swift run TestTranscription
swift run TestStreamingTTS
swift run TestSentenceSplitter
swift run TestAudioCollector

# Manage models
swift run ListModels
swift run ValidateModels
swift run DeleteModel
```

## Architecture

macOS menu-bar app (`NSApplicationDelegate`, `.accessory` activation policy). No Xcode project — pure Swift Package Manager.

**Package layout:**
- `SharedSources/` → `SharedModels` library target. Shared between main app and test/tool executables.
- `Sources/` → `MOP` executable target (app entry point + UI).
- `tests/` → standalone executable test targets (not XCTest).
- `tools/` → standalone model management utilities.

**Key dependencies:** WhisperKit (offline STT), FluidAudio/Parakeet (fast offline STT), KeyboardShortcuts (global hotkeys).

**Core data flow:**
1. Global hotkey → `AppDelegate` (in `Sources/main.swift`)
2. `AppDelegate` drives `AudioTranscriptionManager` (recording + transcription) and `GeminiStreamingPlayer`/`GeminiAudioCollector` (TTS)
3. `AudioTranscriptionManager` delegates back to `AppDelegate` via `AudioTranscriptionManagerDelegate`
4. Transcription result → `typeTextAtCursor()` (tries AX API, falls back to CGEvent unicode or clipboard+paste)
5. Results stored in `TranscriptionHistory.shared`

**Model management:** `ModelStateManager.shared` (singleton, `@Published`) owns engine selection (WhisperKit vs Parakeet), model loading, and download state. UI observes via Combine.

**Config:** `GeminiConfig` reads API key from UserDefaults (migrated from `.env`). `TranscriptionPreferences` stores auto-paste, cleanup, copy-to-clipboard flags. `CleanupConfig` selects the cleanup driver (Gemini, Ollama, LM Studio).

**Text cleanup pipeline:** Post-transcription optional cleanup via `GeminiTextCleanup` or `LocalLLMTextCleanup`. Triggered when `TranscriptionPreferences.useTextCleanup` is true; result delivered via `transcriptionDidCleanUp` delegate callback.

**TTS flow:** Selected text → `Cmd+C` simulation → `GeminiStreamingPlayer.playText()` → `SmartSentenceSplitter` chunks text → `GeminiAudioCollector` WebSocket streams audio → AVAudioEngine plays with 1.15× TimePitch.

**UI:** Single `UnifiedManagerWindow` with `SidebarNavigationView` tabs (Models, History, Statistics, Preferences, Shortcuts, Cleanup, Audio Devices).

## Background Process Management

- Run app in background during development: `swift build && swift run MOP` with `run_in_background: true`
- Restart only when code changes require a fresh build
- User prefers to keep the running instance for continuous testing

## Git Commit Guidelines

- No Claude attribution or Co-Author information in commits

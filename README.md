# MOP

macOS voice assistant with global hotkeys - transcribe speech to text with offline models (WhisperKit or Parakeet), and read selected text aloud with Gemini Live. Fast, accurate, and simple.

## Demo

**Parakeet transcription (fast and accurate):**

https://github.com/user-attachments/assets/163e6484-a3b1-49ef-b5e1-d9887d1f65d0

**Instant text-to-speech:**

https://github.com/user-attachments/assets/c961f0c6-f3b3-49d9-9b42-7a7d93ee6bc8

**Visual disambiguation for names:**

https://github.com/user-attachments/assets/0b7f481f-4fec-4811-87ef-13737e0efac4

## Features

**Voice-to-Text Transcription**
- Press Command+Option+Z for local offline transcription (WhisperKit or Parakeet)
- Press Command+Option+X for cloud transcription with Gemini API
- Choose your engine in Settings: WhisperKit models or Parakeet (faster, more accurate)
- Automatic text pasting at cursor position
- Transcription history with Command+Option+A

**Streaming Text-to-Speech**
- Press Command+Option+S to read selected text aloud using Gemini Live API
- Press Command+Option+S again while reading to cancel the operation
- Sequential streaming for smooth, natural speech with minimal latency
- Smart sentence splitting for optimal speech flow

**Screen Recording & Video Transcription**
- Press Command+Option+A to show transcription history
- Automatic video transcription using Gemini 2.5 Flash API with visual context
- Better accuracy for programming terms, code, technical jargon, and ambiguous words
- Transcribed text automatically pastes at cursor position

## Requirements

- macOS 14.0 or later
- Xcode 15+ or Xcode Command Line Tools (for Swift 5.9+)
- Gemini API key (for text-to-speech and text cleanup)

## System Permissions Setup

This app requires specific system permissions to function properly:

### 1. Microphone Access
The app will automatically request microphone permission on first launch. If denied, grant it manually:
- Go to **System Settings > Privacy & Security > Microphone**
- Enable access for **MOP**

### 2. Accessibility Access (Required for Global Hotkeys & Auto-Paste)
You must manually grant accessibility permissions for the app to:
- Monitor global keyboard shortcuts (Command+Option+Z/S/X/A/V/C, Escape)
- Automatically paste transcribed text at cursor position

**To enable:**
1. Go to **System Settings > Privacy & Security > Accessibility**
2. Click the lock icon to make changes (enter your password)
3. Click the **+** button to add an application
4. Navigate to the app location:
   - If running via `swift run`: Add **Terminal** or your terminal app (iTerm2, etc.)
   - If running the built binary directly: Add the **MOP** executable
5. Ensure the checkbox next to the app is checked

**Important:** Without accessibility access, the app cannot detect global hotkeys (Command+Option+Z/S/A/V, Escape) or paste text automatically.

## Installation & Running

```bash
# Clone the repository
git clone https://github.com/yourusername/mop.git
cd mop

# Build the app
swift build

# Run the main app
swift run MOP

# Configure your Gemini API key in Settings (Cmd+,)
```

The app will appear in your menu bar as a waveform icon.

## Configuration

### Text Replacements

You can configure automatic text replacements for transcriptions by editing `config.json` in the project root:

```json
{
  "textReplacements": {
    "Cloud Code": "Claude Code",
    "cloud code": "claude code",
    "cloud.md": "CLAUDE.md"
  }
}
```

This is useful for correcting common speech-to-text misrecognitions, especially for proper nouns, brand names, or technical terms. Replacements are case-sensitive and applied to all transcriptions.

## Usage

### Voice-to-Text Transcription

**Local (Cmd+Option+Z):**
1. Launch the app - it appears in the menu bar
2. Open Settings to select and download a model (Parakeet or WhisperKit)
3. Press **Command+Option+Z** to start recording
4. Press **Command+Option+Z** again to stop and transcribe
5. Text automatically pastes at cursor
6. Press **Escape** to cancel

**Transcription engines:**
- **Parakeet v2**: ~110x realtime, 1.69% WER, English - recommended for speed
- **Parakeet v3**: ~210x realtime, 1.8% WER, 25 languages
- **WhisperKit**: Various model sizes, good accuracy, more language options

After transcription, Gemini is optionally used to clean up the text (fix grammar/punctuation).

### Text-to-Speech
1. Select any text in any application
2. Press **Command+Option+S** to read the selected text aloud
3. Press **Command+Option+S** again while reading to cancel the operation
4. The app uses Gemini Live API for natural, streaming speech synthesis
5. Configure audio devices via Settings for optimal playback

### Keyboard Shortcuts

- **Command+Option+Z**: Start/stop audio recording and transcribe (WhisperKit - offline)
- **Command+Option+S**: Read selected text aloud / Cancel TTS playback
- **Command+Option+A**: Show transcription history window
- **Command+Option+V**: Paste last transcription at cursor
- **Control+Space**: Start/stop audio recording (alternative)
- **Escape**: Cancel audio recording (when recording is active)

## Available Commands

```bash
# Run the main app
swift run MOP

# List all available WhisperKit models
swift run ListModels

# Test downloading a model (currently set to distil-whisper_distil-large-v3)
swift run TestDownload

# Validate downloaded models are complete
swift run ValidateModels

# Delete all downloaded models
swift run DeleteModels

# Delete a specific model
swift run DeleteModel <model-name>
# Example: swift run DeleteModel distil-large-v3

# Test transcription with a sample audio file
swift run TestTranscription

# Test live transcription with microphone input
swift run TestLiveTranscription

# Test streaming TTS functionality
swift run TestStreamingTTS

# Test audio collection for TTS
swift run TestAudioCollector

# Test sentence splitting for TTS
swift run TestSentenceSplitter
```

## Project Structure

- `Sources/` - Main app code
  - `ModelStateManager.swift` - Engine and model selection
  - `AudioTranscriptionManager.swift` - Audio recording and transcription routing
- `SharedSources/` - Shared components
  - `ParakeetTranscriber.swift` - FluidAudio Parakeet wrapper
  - `GeminiStreamingPlayer.swift` - Streaming TTS playback
  - `GeminiTextCleanup.swift` - Gemini text cleanup for transcriptions
- `tests/` - Test utilities
- `tools/` - Model management utilities

## Featured in

- [claude-code-tips](https://github.com/ykdojo/claude-code-tips)

## License

See [LICENSE](LICENSE) for details.

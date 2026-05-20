# MOP

[![GitHub stars](https://img.shields.io/github/stars/desgn-space/mop?style=flat&color=amber)](https://github.com/desgn-space/mop)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Website](https://img.shields.io/badge/Website-mop.desgn.space-black)](https://mop.desgn.space)

**Voice-to-text for macOS. Free, open source, runs entirely on your machine.**

MOP lives in your menu bar. Press a hotkey to start dictating — your words appear at the cursor in any app. Transcription runs offline on Apple Silicon using WhisperKit or Parakeet. Nothing leaves your device unless you choose it. No subscription. No telemetry. No surprises.

👉 [mop.desgn.space](https://mop.desgn.space) — website, docs, and downloads

---

## What it does

**Dictation**
- `Control+Space` — start recording, press again to transcribe and paste
- Runs fully offline via WhisperKit or Parakeet on Apple Silicon
- Parakeet v2: ~110× realtime, 1.69% WER, English
- Parakeet v3: ~210× realtime, 1.8% WER, 25 languages
- WhisperKit: multiple model sizes, broad language support
- Optional AI cleanup pass — bring your own provider (Gemini, OpenAI, Ollama, LM Studio, or Anthropic)

**Text-to-speech**
- `Command+Option+S` — read selected text aloud via Gemini Live
- Press again to stop
- Streams audio sentence-by-sentence for low latency and natural flow

**AI text cleanup** *(optional, off by default)*
- Fixes grammar, punctuation, and formatting after transcription
- Only sends data if you turn it on and configure a provider
- Bring your own: Gemini, OpenAI, Ollama, LM Studio, or Anthropic — or run fully local with Ollama/LM Studio

**History and utilities**
- `Command+Option+A` — open transcription history
- `Command+Option+V` — paste last transcription at cursor
- Text replacements to correct recurring misrecognitions (e.g. "Cloud Code" → "Claude Code")

---

## Requirements

- macOS 14.0 or later
- Xcode Command Line Tools (Swift 5.9+)
- Gemini API key — required for text-to-speech (Gemini Live)
- Optional: OpenAI, Ollama, LM Studio, or Anthropic API key for AI text cleanup

---

## Install

```bash
git clone https://github.com/desgn-space/mop.git
cd mop
swift build
swift run MOP
```

MOP appears in your menu bar as a waveform icon. Open Settings to download a transcription model. Add a Gemini API key to enable text-to-speech, or connect any supported provider for AI cleanup.

---

## Permissions

MOP needs two system permissions to work.

**Microphone** — requested automatically on first launch. If blocked, go to **System Settings › Privacy & Security › Microphone** and enable MOP.

**Accessibility** — required for global hotkeys and auto-paste. Go to **System Settings › Privacy & Security › Accessibility**, click **+**, and add:
- Your terminal app (Terminal, iTerm2, etc.) if running via `swift run`
- The MOP executable if running the built binary directly

Without accessibility access, hotkeys and auto-paste won't work.

---

## Text replacements

Fix recurring transcription errors by adding entries to `config.json` in the project root:

```json
{
  "textReplacements": {
    "Cloud Code": "Claude Code",
    "cloud code": "claude code",
    "cloud.md": "CLAUDE.md"
  }
}
```

Replacements are case-sensitive and applied to every transcription.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Control+Space` | Start / stop recording and transcribe |
| `Command+Option+S` | Read selected text aloud / stop playback |
| `Command+Option+A` | Open transcription history |
| `Command+Option+V` | Paste last transcription at cursor |
| `Escape` | Cancel recording |

---

## CLI commands

```bash
swift run MOP               # run the app
swift run ListModels        # list available WhisperKit models
swift run ValidateModels    # check downloaded models are complete
swift run DeleteModels      # delete all downloaded models
swift run DeleteModel <name> # delete one model by name
swift run TestTranscription  # test transcription with a sample file
swift run TestStreamingTTS   # test streaming TTS
swift run TestAudioCollector # test audio collection
swift run TestSentenceSplitter # test sentence splitting
```

---

## Project structure

```
Sources/          main app
  AudioTranscriptionManager.swift   recording and transcription routing
  ModelStateManager.swift           engine and model selection
SharedSources/    shared library
  ParakeetTranscriber.swift         FluidAudio Parakeet wrapper
  GeminiStreamingPlayer.swift       streaming TTS playback
  GeminiTextCleanup.swift           Gemini cleanup driver
tests/            test executables
tools/            model management utilities
```

---

## Credits

MOP is built on [super-voice-assistant](https://github.com/ykdojo/super-voice-assistant) by [@ykdojo](https://github.com/ykdojo). Big thanks for the foundation.

## License

See [LICENSE](LICENSE) for details.

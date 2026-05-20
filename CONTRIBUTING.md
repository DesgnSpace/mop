# Contributing to MOP

MOP is a free, open-source macOS voice utility. Contributions that make dictation faster, more private, or more useful are welcome.

---

## Getting Started

**Prerequisites:**
- macOS 14.0 or later
- Xcode Command Line Tools (Swift 5.9+)

**Setup:**
```bash
git clone https://github.com/desgn-space/mop.git
cd mop
swift build
swift run MOP
```

---

## Core principles

**Nothing leaves the device by default.** Transcription runs fully offline via WhisperKit or Parakeet on Apple Silicon. Any feature that sends data off-device must be opt-in, user-configured, and clearly documented.

**No secrets in code.** Never commit API keys, tokens, or endpoint configs. User-supplied keys are stored in UserDefaults and never hardcoded.

**Keep it simple.** MOP is a menu-bar app — not a platform. Avoid abstractions, frameworks, or dependencies that aren't clearly necessary.

---

## Code style

- Swift modern concurrency (`async/await`, structured concurrency, actors) for all async work
- Descriptive names — no abbreviations that need a comment to explain
- Handle audio device disconnects and model download failures gracefully with user-facing feedback
- Match existing patterns before introducing new ones

---

## Testing changes

There are no XCTest suites — tests are standalone executable targets under `tests/`:

```bash
swift run TestTranscription
swift run TestLiveTranscription
```

Ensure `swift build` compiles cleanly before opening a PR.

---

## Opening a pull request

1. Fork and create a branch: `git checkout -b feat/your-improvement`
2. Commit with semantic messages: `feat(hud): add visual cancel indicator`
3. Open a PR against `main` — a maintainer will review it

---

## Code of Conduct

Be respectful. Contributions of all experience levels are welcome.

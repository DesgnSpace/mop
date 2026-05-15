# Live Transcription — Research Charter

**Status:** Research (no code changes)
**Track:** Parallel to engine-unification track (separate owner)
**Product framing:** MOP is a consumer product for **"people or people just beside"** — friends, family, normal users on standard hardware. Every decision defaults to 16 GB Mac under real-world load.

---

## What this document is

A definition of what needs to be researched before any v2 feature work starts. It produces no code, no recommendation, and no implementation plan. A follow-up findings document will carry those outputs after the questions below are answered.

**What we have today might already work.** The working assumption is that the current stack (WhisperKit, FluidAudio/Parakeet, Qwen3 + LLM cleanup drivers) may already cover the user-visible needs. Before adding or replacing anything, we need evidence of insufficiency. That evidence must be measured, not asserted.

### Cross-cutting constraints

These shape every part of this research and must hold across all candidates:

1. **Swift-native** — SPM drop-in preferred over C++ bridges, Python sidecars, or hand-rolled CoreML conversion.
2. **Live transcription** — text appears bit-by-bit as the user speaks.
3. **Beyond the current set** — candidate pool is not limited to WhisperKit / FluidAudio / Qwen3.
4. **16 GB consumer Mac under real-world load** — not isolated benchmarks.
5. **UI anonymity** — engines must be presentable to the user as a flat list of *models* with no engine brand names ("WhisperKit", "Parakeet", "FluidAudio") leaking into the UI. This affects which engines qualify: any candidate must produce models that are describable to a normal user purely by capability (speed, accuracy, languages, memory class). Implementation of this UI consolidation is owned by the engine-unification track ("another tax/person") — this charter only ensures the research output respects the constraint.

---

## Part 1 — STT Engine Candidates

### A. What does "live transcription" need to feel right?

A.1 Latency budget — at what delay does dictation feel broken vs natural? (Reference: Moonshine targets 107 ms; Apple SpeechAnalyzer sub-second; Whisper sliding-window 1–3 s.)

A.2 True streaming partials (text rewrites as model gains context) vs chunked commit (text appears in 1–2 s blocks)? Different engine families. Need a product decision to evaluate against.

A.3 End-of-utterance auto-commit required? If yes, engine must expose EOU or pair with VAD (Silero).

A.4 Session shape: short dictation (< 30 s) tolerates batch-with-chunking; meeting capture needs true streaming for memory reasons.

### B. Does the current stack already cover live transcription?

B.1 **FluidAudio** ships `StreamingAsrManager`, `StreamingEouAsrManager`, `StreamingNemotronAsrManager`. MOP uses only the batch path today (`AudioTranscriptionManager.swift:286-332`). Open: how does FluidAudio streaming perform on a 16 GB M1/M2 under realistic background load?

B.2 **WhisperKit** ships `AudioStreamTranscriber`, `EnergyVAD`, `AudioChunker`. Open: streaming latency + accuracy vs current batch, on small models that fit 16 GB.

B.3 **Qwen3** has no streaming surface. Open: still earning its place, or only there as a multilingual fallback that streaming-capable engines now cover?

B.4 Decision gate: if B.1 and B.2 both pass the latency + memory bar, introducing a new engine is hard to justify. Numbers must exist before Tier 2 candidates are considered.

### C. Candidate pool

Catalogued for evaluation, not endorsed. Each entry needs measurement on consumer hardware before earning a recommendation.

**Tier 1 — native, streaming, Swift-friendly**

| Engine | Streaming | Runtime | Languages | Min OS |
|---|---|---|---|---|
| Apple SpeechAnalyzer | `analyzeSequence(_:)`, `SpeechDetector` | OS-managed | Apple's set | macOS 26 |
| FluidAudio (in tree) | `Streaming*AsrManager` + EOU + Nemotron | ANE/CoreML ~66 MB | 25 EU + EN | macOS 14 |
| WhisperKit (in tree) | `AudioStreamTranscriber` + `EnergyVAD` | ANE/CoreML | ~99 | macOS 13 |

Apple SpeechAnalyzer gates on macOS 26 — that is a **product decision**, not a technical one. It is zero-dependency, free, OS-managed, and already powering Notes / Voice Memos / Journal.

**Tier 2 — viable, narrower scope**

- **speech-swift** (soniqo/speech-swift). SPM: `ParakeetStreamingASR`, `NemotronStreamingASR`, `Qwen3ASR`, `OmnilingualASR`, Silero VAD, Parakeet-EOU-120M, `VoicePipeline` state machine. Ships a menu-bar DictateDemo with the exact product shape MOP wants. MLX + CoreML mix — MLX paths use GPU memory (the 16 GB concern).
- **Moonshine + moonshine-swift**. ONNX Runtime (not CoreML). v2 ergodic streaming encoder, 107 ms latency on MacBook Pro, English-focused, tiny models. Strong fit for 16 GB if English-only is acceptable.
- **mlx-audio-swift / mlx-swift-audio** (Blaizzy, DePasqualeOrg). Broad model zoo (Qwen3-ASR, Voxtral Realtime, Cohere Transcribe, Parakeet, GLM-ASR). MLX = unified memory pressure on smaller Macs.
- **OtosakuStreamingASR-iOS**. Lightweight streaming Conformer, Swift + CoreML, small surface.

**Tier 3 — possible but more integration work**

- **whisper.cpp** via SPM `systemLibrary`. Manual sliding-window streaming. Portability fallback.
- **NVIDIA Nemotron raw**. Already reachable through FluidAudio — no independent integration needed.
- **parakeet-mlx** (EliFuzz). Python-first; no Swift package.

### D. The 16 GB vs 32 GB constraint

Must be measured, not estimated.

D.1 Working memory on Apple Silicon: ANE vs GPU/MLX vs CPU path. FluidAudio Parakeet TDT on ANE is ~66 MB; MLX-GPU equivalent is ~2 GB. That delta is the entire low-RAM story.

D.2 Concurrent app reality — measurement under "MOP + Chrome + Slack + Zoom," not clean boot.

D.3 Model size on disk — consumer download time + storage budget. Default download likely caps at ≤ ~500 MB; larger models behind explicit opt-in.

D.4 Tiered offering — conservative default for 16 GB + opt-in higher-accuracy model for 32 GB+. Validate this tiering maps to real engine families.

D.5 Thermal + battery — consumer laptops run unplugged. ANE > GPU > CPU for both. Favours CoreML/ANE engines.

### E. Languages & accuracy

E.1 Which language coverage is non-negotiable today vs aspirational?

E.2 Is WER the right metric, or is "feels accurate on dictation-style speech in a quiet room" the real bar? The latter favours streaming transducer models even when their batch WER trails Whisper.

### F. Maintenance & supply-chain

F.1 Project momentum: commit cadence, releases, issue response for each candidate.

F.2 License: every candidate above is permissive (MIT/Apache-class) — verify per release.

F.3 Model hosting: Hugging Face is de-facto. Need a fallback story when HF is unreachable.

---

## Part 2 — Streaming Cleanup

Live STT solves half the problem. As soon as transcription emits bit-by-bit, the cleanup layer becomes the user-visible bottleneck. The product cannot paste strict raw text and call it done — it must turn speech into proper writing as the user speaks.

### G. The core problem: speech is not text

Spoken input arrives messy. The concrete case to handle:

> "this is the person that is going to — no no no, they now like…"

A strict transcription pastes all of that to the cursor. The product must understand intent and emit proper writing. Today cleanup runs once, post-finalization, on the full string (`AudioTranscriptionManager.swift:501-538`). With streaming STT this needs to happen **as the user speaks**.

G.1 How aggressive should cleanup be? Pure disfluency removal (uh/um/repeated words) is safe. Self-correction collapse ("X — no, Y" → just "Y") is interpretive — sometimes the user wanted both clauses. What is the default? What does the user override look like?

G.2 When does cleanup commit? Options ranked by increasing UX risk:
  - Per full session — today's behaviour; loses the "live" benefit.
  - Per phrase / EOU — cleanup runs at each end-of-utterance boundary. Likely sweet spot.
  - Per sentence boundary (punctuation-aware) — commit only when the model places a terminator.
  - Per partial — every STT update re-runs cleanup over the whole utterance. Highest cost (text flickers).

G.3 Latency vs quality for the cleanup LLM. A local 7B cleans a sentence in ~200–500 ms; cloud Gemini/Claude is faster but adds network jitter. On a 16 GB Mac, running a local cleanup model on top of a streaming STT model may not fit. Research must measure peak RAM with **both models loaded simultaneously**.

G.4 Streaming the cleanup driver. All four current drivers (`AnthropicTextCleanup`, `GeminiTextCleanup`, `LocalLLMTextCleanup`, `OpenAITextCleanup`) are batch — Ollama explicitly sets `"stream": false` at `LocalLLMTextCleanup.swift:61`. The underlying APIs all support streaming. Open: does streaming the cleanup output give a visible UX win, or is per-phrase batch sufficient at this scale?

### H. The protocol gap

Today's driver contract (`SharedSources/TextCleanupDriver.swift:14-17`):

```swift
func cleanup(_ text: String, prompt: String) async throws -> CleanupResult
```

Single string in, single string out. No streaming, no delta, no prior-context. Streaming bit-by-bit cleanup needs more.

H.1 Does the driver need to know what has already been committed to screen so it only emits the next delta? Without this, every partial replays the whole utterance and the model may contradict its earlier output.

H.2 Right shape: "whole running utterance + already-committed prefix → return delta"? Or "new fragment + prior cleaned context → return cleaned fragment"? Both have failure modes to evaluate.

H.3 No driver currently sees conversational history. All four pass `(system=prompt, user=text)` only. To self-correct ("they're going to" overriding "this is the person"), the model needs the prior partial. How much prior context is enough — one sentence? Full session?

H.4 `CleanupProfile.modelOverride` (`CleanupProfile.swift:8`) is declared but dead — `AudioTranscriptionManager:521` ignores it. If streaming cleanup wants a smaller/faster model than batch cleanup, plumbing this field through is the minimum change required.

### I. Re-writing already-typed text

If cleanup runs as the user speaks, the text already typed into the user's editor will sometimes be wrong and need replacing. Today there is no mechanism for this.

I.1 `typeTextAtCursor` (`Sources/main.swift:386-420`) has three insertion paths — clipboard+⌘V, AX `kAXSelectedTextAttribute`, CGEvent unicode — and **none track what was inserted**. No anchor, no range, no character count.

I.2 AX path is the most promising: `kAXSelectedTextRangeAttribute` to select a prior range, then `kAXSelectedTextAttribute` to overwrite. Research: which apps honour this reliably?

I.3 CGEvent fallback: backspace N times + retype. Works everywhere keystrokes work. Visually jarring on long rewrites. Does not survive fields that auto-correct (Safari address bar, Mail subject).

I.4 Clipboard paste **cannot be rewritten** without ⌘Z, which is intrusive. Open: accept "no rewrite when paste fallback is used" as a known limitation?

I.5 Lock-in boundary: once a sentence ends and the user moves on, stop revising. Define the exact policy.

### J. Profiles — existing structure and the legal-document question

Profiles must be understood before any streaming-cleanup design. Current structure (`SharedSources/CleanupProfile.swift:3-35`):

- `prompt: String` — system instruction to the driver
- `driverOverride: CleanupDriver?` — per-profile driver
- `modelOverride: String?` — declared, unused (see H.4)
- `appBundleIDs: [String]`, `urlHostPatterns: [String]` — auto-routing by frontmost app / browser URL
- `isDefault: Bool`

Shipped defaults (`CleanupProfileStore.swift:109-141`): **Format** · **Casual** (default) · **Code Comments** (auto-routes to VSCode/Cursor/Xcode). No legal, formal, or email profiles ship today.

Auto-routing already exists — `resolveActive(forFrontmostBundleID:urlHost:)` picks a profile from the frontmost app or browser URL. Writing a legal document in Pages or in a Google Docs tab on `*.lawfirm.example` could route to a "Legal" profile automatically.

**The legal-document question** — *"writing legal documents like how does that work?"* — needs concrete answers:

- **Vocabulary**: legal writing has fixed phrasing (whereas/hereinafter/the party of the first part). A casual cleanup model may "correct" these into plain English. Do profile prompts alone prevent this, or does the model need different temperature / few-shot examples?
- **Conservatism**: legal text must not be paraphrased. A "Format" profile (punctuation-only) is closer to what legal needs than the default "Casual" profile. Should legal mode disable interpretive cleanup entirely?
- **Citations / structure**: numbered clauses, defined terms in capitalised acronyms. Can the prompt enforce this alone, or does the driver need structured-output mode?
- **Privacy**: legal users may prohibit cloud drivers. Should a Legal profile force `driverOverride = .localLLM`? Profiles already support this.
- **Self-correction in legal dictation**: *"the defendant — strike that, the plaintiff."* Cleanup must produce "the plaintiff", not preserve the verbal stage direction. Same streaming-cleanup case as §G, different aggressiveness requirement.

The same questions apply to **casual** (preserve voice and contractions) and **formal** (tighten, no contractions, no "like"). Research: what does the matrix of profile × cleanup-aggressiveness × streaming-commit-boundary look like?

J.5 Profiles as the unit of streaming policy. Per-partial vs per-EOU, allowed rewrite radius, allowed driver — natural to put on the profile. Research: does `CleanupProfile` grow streaming/aggressiveness fields, or does the prompt encode this implicitly?

### K. Understanding-driven cleanup, not strict text

The product must treat the transcript as **intent** to be expressed in proper writing, not as literal text to paste. The model should:

- use the profile as the register (legal, casual, formal),
- use app/URL context as additional signal (already auto-routed today, but not yet passed to the LLM call),
- be allowed to discard or rewrite false starts when the profile permits.

K.1 How much improvement does passing app/URL context into the cleanup LLM's user message buy? Today the driver call carries zero context beyond `(prompt, text)`.

K.2 Should the profile expose a cleanup-aggressiveness knob (strict / balanced / interpretive) for users to dial?

K.3 Is there a shared base preamble for partial-aware prompts worth defining once and augmenting per profile? Example shape: "You are receiving a live dictation. The prefix `…` is already committed and cannot change. Emit only the continuation, cleaned per the profile below." Then the profile-specific prompt follows.

---

## Part 3 — Live Input + In-Place Editing on macOS

This is the load-bearing piece once Parts 1 and 2 land. Live STT only feels right if typed text can be **rewritten as the user changes their mind**. A user says something, the system pastes it, and then they want to change it — the product must support that, not just append forever. This is going to be important.

### L. Baseline today (the fallback we already have)

L.1 What we do now is paste. `typeTextAtCursor` (`Sources/main.swift:386-420`) picks one of three paths: clipboard+⌘V, AX `kAXSelectedTextAttribute`, CGEvent unicode. Pasting is easy and survives anywhere — that is its virtue and it is the safe fallback.

L.2 **Open assumption to verify**: it is not confirmed whether the current paste path behaves the same in native text fields (TextEdit / Notes / Cocoa) as in **browser inputs** (`<input>`, `<textarea>`, contenteditable in Safari / Chrome / Arc / Firefox / Electron apps). Must be measured directly — paste-into-Gmail and paste-into-TextEdit are not the same operation.

L.3 Whatever fancier approach is chosen must degrade to paste when it cannot run.

### M. The core problem: "eat" the input as it streams

As live input comes in, the app must **consume and revise it in place**, not append forever. Someone says "the meeting is on Tuesday — actually Wednesday." The product should land *"The meeting is on Wednesday."*, not the full raw disfluency.

M.1 Track what was typed — UTF-16 length, AX text range, or a marker — to target prior output for replacement.

M.2 Decide a revision boundary — most likely per-EOU or per-sentence. Once a sentence is locked in, stop revising.

M.3 Race condition: the user may type into the same field while STT produces partials. Detect concurrent user input and bail out of rewrites, or queue, or scope the rewritable range to a span no user keystroke has crossed?

M.4 ⌘Z must undo the whole edit cycle, not 47 individual backspace-then-retype entries. Which insertion path produces a single undo entry per cleanup commit?

### N. macOS approaches to in-place editing

The research ask: **what is the best macOS primitive for editing already-emitted text?** All candidates to be measured, none pre-selected.

**N.1 AX range select + overwrite.** Read caret via `kAXSelectedTextRangeAttribute`; select prior range; overwrite via `kAXSelectedTextAttribute`. Theoretically the cleanest path — atomic, app-supported, undo-friendly in well-behaved apps.
  - Research: which apps honour this? Native Cocoa text views: likely yes. WebKit (Safari, Mail): partial. Chromium/Electron: mixed. JetBrains / VSCode / Cursor: untested.
  - Does AX range-replace produce a single undo entry?

**N.2 CGEvent backspace + retype.** N synthetic deletes + new inserts. Works everywhere keystrokes work, including Terminal. Visually jarring on long rewrites. Fails in auto-correcting fields (Safari address bar, Mail subject).
  - Research: max rewrite length before giving up and falling back?

**N.3 Clipboard + paste with selection.** Programmatically select-back via `kAXSelectedTextRangeAttribute` or ⇧⌘←, then ⌘V the cleaned replacement. Survives apps that ignore AX text-set but honour AX range selection.

**N.4 NSTextInputClient / marked text.** Input methods use "marked text" — a tentative range the app renders with an underline, revisable wholesale before commit. macOS IMEs (Japanese, Chinese, system dictation) use this every day. This is the right shape for streaming partials. Can a non-IME app drive this without becoming a full input source?
  - Research: investigate `TISCreateInputSource`, `IMKServer`. Can MOP run as a lightweight input method only when the user enables the optional feature? High-risk, high-reward path.

**N.5 AppleScript / SystemEvents.** Last resort. Slow, requires Automation permission. Useful only as a probe.

**N.6 App-specific integrations.** Notes / Mail / Pages have AppleScript dictionaries. Browsers expose JS. Not worth pursuing unless the AX matrix shows widespread gaps.

Research output must be a **compatibility matrix**: TextEdit · Notes · Mail · Pages · Safari (input) · Safari (contenteditable) · Chrome · Arc · Firefox · Slack · Discord · VSCode · Cursor · Xcode · Terminal · iTerm — labelled "works / partial / broken / single-undo / multi-undo / races-with-autocorrect" per primitive.

### O. The optional UI: HUD popup as a streaming surface

The user described this as an extension of the existing UI: *"like a pop-up that shows the text as they talk as they go,"* with paste as backup *"if needed."* MOP already has a HUD (`RecordingHUDController.swift` · `RecordingHUDView.swift` · `RecordingHUDWindow.swift`). Extending it to render live text is additive.

**O.1 What the HUD popup does.** A small floating panel shows the streaming transcript + cleanup output live. The user watches their words appear in the HUD, not in the focused app — until they confirm, at which point the final text is pasted at the cursor.

**O.2 Why it sidesteps Part 3 §N.** All in-place-edit complexity disappears inside the HUD — it is our own SwiftUI text view, we control everything. Rewrites are trivial. We only paste once, at commit time, into the user's actual document.

**O.3 Not the default.** This feature is **off by default**. Most users want text to land directly in the focused app, paste-style. The HUD popup is opt-in for users who want the live preview + accept/edit workflow.

**O.4 When enabled, it must work.** Research bar:
  - Streaming partials render at < 100 ms perceived latency.
  - User can edit in the HUD (keyboard) before commit — requires a real `NSTextView` / SwiftUI `TextEditor`, not a label.
  - Commit: Return / configurable hotkey / EOU auto-commit (per profile per §J.5).
  - Cancel: Escape clears without pasting.
  - HUD must not steal focus from the user's document — `.nonactivatingPanel` style, `.canBecomeKey = false` until user clicks in. Verify this is already true for the existing HUD window.
  - At commit, text goes to whichever app was frontmost when recording started (`activeBundleID` already snapshotted at `AudioTranscriptionManager:139`).

**O.5 The two-mode product.**
  - **Direct-write mode (default):** live STT + cleanup → paste at cursor, AX-rewrite where feasible (per §N matrix), CGEvent fallback.
  - **HUD preview mode (opt-in):** live STT + cleanup → HUD popup → user confirms → paste. Best for careful work (legal drafting, code comments) where the user wants to see and edit before committing.

**O.6 Reuse.** The existing HUD already handles window placement, hide-during-recording, and persisted position (commit `108f8ad`). The streaming-text view is additive, not a replacement. Research: does the existing HUD have spare visual real-estate, or does preview mode swap it for a larger panel?

### P. Open research questions for Part 3

P.1 AX compatibility matrix (per §N) across the full app list.

P.2 Paste parity (per L.2) — confirm or refute that paste behaves identically in native fields and browser inputs.

P.3 Undo behaviour per insertion path — single ⌘Z must roll back a full cleanup cycle.

P.4 NSTextInputClient / marked-text feasibility (per N.4) — yes / no / "only as input source," with rationale.

P.5 HUD preview mode prototype — wired to existing FluidAudio streaming managers, demonstrating streaming partials + edit + commit + cancel, gated behind a preference defaulted to off.

P.6 Mode-switching cost — toggling HUD preview mode likely takes effect on next recording, not mid-session.

P.7 Fallback cascade — explicit ordering: try AX range-replace → try backspace+retype → paste over selection → append-only paste with user-visible warning that rewrites are disabled in this app.

---

## Explicit non-goals

- **Engine unification / abstraction protocol** — owned by the parallel track. This document does not specify a `SpeechTranscriber` protocol, a `ModelStateManager` refactor, or any code consolidation.
- **UI redesign of the model picker** — also owned by the parallel track. This charter only flags the UI-anonymity constraint (see cross-cutting constraints) so that any engine recommendation here is compatible with anonymous presentation.
- **Production code changes** — none follow directly from this charter. Findings → follow-up document → implementation plan → code, in that order.

## Research Output Deliverables

The follow-up findings document must contain:

1. **Pass/fail verdict** on "does the current stack meet the live-transcription bar on 16 GB consumer Macs?" — measured, not asserted.
2. If pass: list of wiring work to expose what already exists + a streaming cleanup design pairing with FluidAudio's existing streaming managers.
3. If fail: ranked short-list of ≤ 3 engine candidates with measured memory + latency + accuracy numbers on both 16 GB and 32 GB reference machines.
4. **macOS 26 baseline decision** — whether Apple SpeechAnalyzer is on the table as a product choice.
5. **Default model + opt-in upgrade model** pairing per D.4 tiering.
6. **Streaming cleanup design** answering: G.2 (commit boundary), H.1–H.3 (driver protocol shape), I.1–I.5 (rewrite strategy + lock-in boundary), J.4 (legal-profile behaviour), J.5 (whether `CleanupProfile` grows streaming fields).
7. **Profile matrix** for legal / casual / formal — prompt, driver, cleanup aggressiveness, rewrite radius, recommended driver.
8. **AX/insertion compatibility matrix** per N — which path works in each app, single vs multi undo, autocorrect races.
9. **Paste parity finding** per L.2 / P.2.
10. **Marked-text / NSTextInputClient feasibility verdict** per N.4 / P.4.
11. **HUD preview mode prototype** on a branch, demonstrating streaming + edit + commit + cancel, preference-gated off by default.
12. **Fallback cascade specification** per P.7 — explicit ordering + user-visible behaviour when every step fails.

## Files Referenced

- `Sources/AudioTranscriptionManager.swift` — batch-only transcription + cleanup call site (`:286-332`, `:501-538`)
- `Sources/ModelStateManager.swift` — engine selection + loading state
- `Sources/main.swift:386-479` — `typeTextAtCursor`, `insertViaAXAPI`, `insertViaUnicodeEvents`, `shouldPasteViaClipboard`
- `Sources/RecordingHUDController.swift` · `Sources/RecordingHUDView.swift` · `Sources/RecordingHUDWindow.swift` — base for HUD preview mode (§O)
- `SharedSources/ParakeetTranscriber.swift` — batch path only; streaming managers exist in FluidAudio dependency, unused
- `SharedSources/ModelData.swift` — model registry
- `SharedSources/TextCleanupDriver.swift:14-17` — driver protocol (batch-only today)
- `SharedSources/{Anthropic,Gemini,LocalLLM,OpenAI}TextCleanup.swift` — driver implementations
- `SharedSources/CleanupDriverRegistry.swift` · `SharedSources/CleanupConfig.swift` — driver resolution
- `SharedSources/CleanupProfile.swift:3-35` · `SharedSources/CleanupProfileStore.swift:109-141` — profile structure + seeded defaults
- `SharedSources/TranscriptionPreferences.swift` — `defaultCleanupPrompt` (used by the seeded Casual profile), auto-paste / cleanup / clipboard flags
- `Sources/BrowserURLDetector.swift` — frontmost-browser URL extraction feeding `CleanupProfileStore.resolveActive(forFrontmostBundleID:urlHost:)` (the auto-routing entry point used in §J)

## Sources

- [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)
- [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio) · [ASR Getting Started](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md)
- [soniqo/speech-swift](https://github.com/soniqo/speech-swift)
- [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) · [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio)
- [DePasqualeOrg/mlx-swift-audio](https://github.com/DePasqualeOrg/mlx-swift-audio)
- [Apple SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) · [Bringing advanced STT to your app](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app) · [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/) · [SpeechAnalyzer guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
- [Apple + Argmax blog](https://www.argmaxinc.com/blog/apple-and-argmax)
- [moonshine-ai/moonshine](https://github.com/moonshine-ai/moonshine) · [Moonshine v2 paper](https://arxiv.org/abs/2602.12241)
- [Otosaku/OtosakuStreamingASR-iOS](https://github.com/Otosaku/OtosakuStreamingASR-iOS)
- [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- [Pushing the Limits of On-Device Streaming ASR](https://arxiv.org/abs/2604.14493)
- [Best open source STT 2026 — Northflank](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- [FluidInference/parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- [Whisper → Parakeet on Neural Engine](https://macparakeet.com/blog/whisper-to-parakeet-neural-engine/)
- [Apple vs Whisper vs Parakeet benchmark 2026](https://dicta.to/blog/speech-to-text-engine-comparison-mac-2026/)

# Live partials (local Qwen + Parakeet)

Last updated: **2026-07-20**.

MacWispr shows a **live draft transcript while the mic is open** for **local** engines (**Qwen** MLX and **Parakeet** Core ML). This is **not** native causal / token streaming. It is **orchestrated live batch**: re-run ASR on the growing 16 kHz buffer and morph the HUD.

## User-visible flow

| Phase | What happens |
|-------|----------------|
| **Hold / Toggle start** | Mic starts; optional monochrome “Listening · m:ss” until first draft |
| **While speaking** | Every ~1.1 s, snapshot PCM → `TranscriptionEngine.transcribe` (full buffer so far) → HUD morphs words in |
| **Release / stop** | Stop live loop → **reuse live draft when buffer barely grew** (fast paste); otherwise one final full-buffer pass → insert |
| **Polish** | Optional; runs after STT (never mid-stream). Off by default. |

Short clips (&lt; ~1 s of audio) may not show a live draft before release; final pass still runs.

## What it is / is not

| | |
|--|--|
| **Is** | Live **feel** for Qwen 0.6B / 1.7B **and Parakeet v3**; monochrome multi-line HUD; polish deferred to post-insert |
| **Is not** | Parakeet-EOU 120M native chunk streaming (`ParakeetStreamingASR` — not wired; TDT uses batch re-runs) |
| **Is not** | Token-level streaming from the Qwen decoder API |
| **Is not** | Live path for cloud STT (OpenAI / ElevenLabs stay batch-on-release) |

## Engines

| Engine | Live partials while mic open? | On release |
|--------|-------------------------------|------------|
| **Qwen 0.6B / 1.7B (MLX)** | Yes | Final full-buffer batch → insert → optional polish |
| **Parakeet v3 (Core ML)** | Yes (same growing-buffer batch re-run) | Final full-buffer batch → insert |
| **OpenAI / ElevenLabs** | No | Batch only |

Default local model: **Qwen 0.6B** (`ASRModelSize.recommendedDefault` → `.small`) for lower RAM / download. Live partials work for **both** 0.6B and 1.7B; user can pick 1.7B for accuracy.

## Implementation map

| Piece | File / API | Role |
|-------|------------|------|
| Live loop | `AppState.startLivePartialLoop` | Timer ~1.1 s; skip if prior ASR still in flight |
| Buffer snapshot | `AudioRecorder.snapshotSamples()` | Copy PCM without stopping the mic |
| Final stop | `AppState.stopRecordingAndTranscribe` | Cancels live loop; final `transcribe`; polish after insert |
| Batch ASR | `TranscriptionEngine.transcribe` | Shared by live drafts + final pass |
| Optional VAD stream helper | `TranscriptionEngine.transcribeStreaming` | Post-buffer VAD segments (available; final path uses batch after live drafts) |
| Silero VAD | Loaded with Qwen in `TranscriptionEngine` | Used if VAD-guided streaming path is invoked |
| HUD | `ListeningHUDController` | Monochrome card; word morph + fade; 4-line scroll |

### Live loop rules

- When `transcriptionProvider == .local` (Qwen **or** Parakeet)
- Minimum samples before first pass: **16_000** (~1.0 s @ 16 kHz)
- Interval: **~1.1 s**; at most one in-flight live ASR (`livePartialInFlight`)
- Session / `recordingSession` guards drop stale results after release
- Failures in live passes are ignored; final pass still runs

### Final + polish

1. Stop live task; `stopRecording()` → full PCM  
2. Keep last draft visible (phase **Finalizing**)  
3. Drain any **in-flight** live ASR briefly (so release can use a fresh draft)  
4. **Fast path:** if last live draft covered almost the whole buffer (≤ ~0.75 s of new audio after that snapshot), **paste the draft** — no second full STT  
5. **Slow path:** otherwise final `transcribe` on full buffer (missed tail / no draft)  
6. Light `postProcess` → insert via `TextInserter`  
7. If polish enabled → polish then insert  

This avoids the common 2–3 s lag where the HUD already showed the full text but release re-ran Qwen on the entire buffer (and often waited behind the last live pass on the same actor).

## Listening HUD design

File: `Sources/ListeningHUDController.swift`.

| State | Appearance |
|-------|------------|
| Listening, **no** draft yet | Compact monochrome capsule: “Listening” + elapsed |
| Listening / finalizing **with** draft | Wider card (~364 pt), **no** red dot / LIVE badge / Listening chrome — **text only** |
| Done / Failed | Compact status line (words · latency or error) |

### Live text card

- **Width** ~364 pt (~30% narrower than earlier 520 pt strip)
- **Height** ~112–118 pt viewport for **~4 lines**
- Words wrap **left → right, top → bottom**
- When content exceeds 4 lines: **auto-scroll down** (latest text stays in view)
- **Black / white** (system `.primary` on material) — not red phase chrome
- **Morph animation:** keep common **word prefix** identity; replace only the changed **tail**; new words **fade + rise in** (never wipe to empty between hypotheses)
- Stable SwiftUI host (`ListeningBannerBox`) so typewriter/morph state survives timer ticks

Toggle: Settings / onboarding **Listening HUD** (`listeningHUDEnabled`).

## Privacy

Live drafts are **on-device only**. Telemetry still must **never** include transcript text (see `PRIVACY.md`). Live UI text is local process UI, not a telemetry field.

## Agent notes / do not regress

- Do **not** reintroduce red “Dynamic Island” chrome or instructional long copy on the live card
- Do **not** run polish before insert completes
- Do **not** block the mic audio thread on ASR — live ASR is async on `TranscriptionEngine` actor
- Replacing root SwiftUI view every tick **resets** animation state — keep `ListeningBannerBox` stable
- Parakeet-EOU native streaming is a **separate** product path if added later; current Parakeet live path is the same growing-buffer batch re-run as Qwen

## Related

- [ARCHITECTURE.md](./ARCHITECTURE.md) — phases + engine table  
- [AGENTS.md](../../AGENTS.md) — product conventions  
- [KNOWN_ISSUES.md](./KNOWN_ISSUES.md) — HUD troubleshooting  

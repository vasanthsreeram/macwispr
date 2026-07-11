# MacWispr architecture (current)

Last updated: 2026-07-12 · product line **1.2.2+**

**Stack choice:** stay on **Swift** (AppKit + MLX via `speech-swift` + Sparkle). Size and peak RAM are dominated by metallibs and model weights, not the app language. Full comparison and “why not Rust/Zig/Bun”: [LANGUAGE_STACK.md](./LANGUAGE_STACK.md).

## Runtime shape

```
┌──────────────────────────────────────────────────────────────┐
│  NSStatusItem (mic + timer) → NSPopover (MenuBarView)         │
│  ⌥Space HotkeyManager       → AppState start/stop              │
│  Listening banner (optional)→ nonactivating panel under bar    │
│  FailureBanner              → nonactivating error panel        │
│  Dashboard NSWindow         → MainWindowView + onboarding      │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────┐
│ AppState (@MainActor)                                          │
│  • dictationPhase: setup | ready | listening | transcribing    │
│                    | success | failed                          │
│  • dictationMode: hold | toggle                                │
│  • asrModelSize: Qwen En+Asian 0.6/1.7B | Parakeet v3 En+EU    │
│  • AudioRecorder → samples @ 16 kHz                            │
│  • TranscriptionEngine → Qwen3ASR (MLX) or ParakeetASR (CoreML)│
│  • CloudSTTClient when provider is OpenAI / ElevenLabs         │
│  • TextInserter (clipboard / type / both)                      │
│  • HistoryStore + UsageStats                                   │
│  • Telemetry.shared (opt-in PostHog batch)                     │
│  • FeedbackSounds (configurable system AIFF chimes)            │
└──────────────────────────────────────────────────────────────┘
```

## Dictation phases

| Phase | Menu bar | Optional banner |
|-------|----------|-----------------|
| setup / ready | idle waveform | hidden |
| listening | red mic + timer | **Listening** + timer |
| transcribing | orange | **Transcribing** |
| success | green + latency | **Done** + words · STT latency |
| failed | orange | **Failed** + reason |

## On-device ASR engines

| UI name (`displayName`) | Package | Backend | Notes |
|-------------------------|---------|---------|--------|
| **Qwen 0.6B (En + Asian)** | `Qwen3ASR` | MLX / GPU | Default on ≤16 GB |
| **Qwen 1.7B (En + Asian)** | `Qwen3ASR` | MLX / GPU | Default on >16 GB |
| **Parakeet v3 (En + EU)** | `ParakeetASR` | Core ML / ANE | Fixed mel `[1,128,3000]`; short clips padded |

- Catalog: `ASRModelSize.swift` (user labels emphasize language coverage, not “MLX 8-bit”)
- Dashboard: **Local** chip (top-right) + menu of the three models / cloud BYOK
- Load / warm / transcribe: `TranscriptionEngine.swift` (actor with dual backend)
- Parakeet short-clip pad: `prepareParakeetSamples` (HF encoder is fixed-shape; INT4 repo retired)
- Custom vocabulary context is **Qwen-only** (`supportsContext`)
- Switching models unloads the previous backend (frees MLX / Core ML footprint)

## Dictation modes

| Mode | ⌥Space | UI |
|------|--------|-----|
| **Hold** | Down → start; Up → stop + transcribe | ⌥Space (menu bar shows phase) |
| **Toggle** | Down toggles start/stop; Up ignored | ⌥Space |

## Hotkey pipeline

1. Prefer `CGEvent.tapCreate` (session, head insert) to **swallow** ⌥Space.
2. Also register **Carbon** hotkey + **global/local** `NSEvent` monitors as backup.
3. If tap swallows, monitors do not see the event (no double-fire).
4. Callbacks hop to main queue → `AppState`.

Accessibility is required for a working tap and for paste into other apps.

## Telemetry

Single choke point: `Telemetry.swift`.

- Opt-in kill-switch (`telemetryOptIn` UserDefaults); default **off**
- Anonymous install UUID; bucketed latency; enum failure reasons
- Events: `hotkey_health`, `dictation_completed`, `dictation_failed`, `opt_in`, `opt_out`
- PostHog US `/batch` with project write key embedded in the client
- See `PRIVACY.md` for the public contract

## Packaging

`scripts/build-app.sh`:

1. `swift build -c release --product MacWispr`
2. Build `mlx.metallib` via speech-swift’s `build_mlx_metallib.sh`
3. Copy binary + metallibs into `MacWispr.app`
4. Embed `Sparkle.framework`
5. Inject version into `Info.plist`
6. Sign (Developer ID if `MACWISPR_SIGN_IDENTITY` set) via `sign-and-notarize.sh`

Without metallib next to the executable, **Qwen / MLX** crashes at startup. Parakeet Core ML does not need `mlx.metallib`, but the packaged app always ships it for Qwen.

## Dependencies

- **speech-swift** → `Qwen3ASR`, **`ParakeetASR`**, `Qwen3Chat`, `SpeechVAD`, `AudioCommon`
- **Sparkle** → in-app updates (appcast on fuckwisprflow.com)
- Caches: HuggingFace / speech-swift model cache under `~/Library/Caches/` (Qwen + Parakeet)

## CLI flags

| Flag | Behavior |
|------|----------|
| `--open-dashboard` | Open main window after AppState is ready |
| `--self-test` | Smoke: status item, model, hold/toggle API, synthetic hotkey |

## Activation policy

- Default: `.accessory` (menu bar only, no Dock).
- Dashboard open: temporarily `.regular` so the window can key-focus.
- Last titled window closed: back to `.accessory`.

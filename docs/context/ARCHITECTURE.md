# MacWispr architecture (current)

Last updated: 2026-07-11 · product line **1.2.2+**

## Runtime shape

```
┌──────────────────────────────────────────────────────────────┐
│  NSStatusItem (waveform)  →  NSPopover (MenuBarView)          │
│  ⌥Space HotkeyManager     →  AppState start/stop               │
│  ListeningHUD (dot+timer) →  nonactivating floating panel      │
│  FailureBanner            →  nonactivating error panel         │
│  Dashboard NSWindow       →  MainWindowView + onboarding       │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────┐
│ AppState (@MainActor)                                          │
│  • dictationPhase: setup | ready | listening | transcribing    │
│                    | success | failed                          │
│  • dictationMode: hold | toggle                                │
│  • AudioRecorder → samples @ 16 kHz                            │
│  • TranscriptionEngine (Qwen3ASR actor) or CloudSTTClient      │
│  • TextInserter (clipboard / type / both)                      │
│  • HistoryStore + UsageStats                                   │
│  • Telemetry.shared (opt-in PostHog batch)                     │
│  • FeedbackSounds (soft system AIFF chimes)                    │
└──────────────────────────────────────────────────────────────┘
```

## Dictation phases

| Phase | Menu bar | Floating HUD |
|-------|----------|--------------|
| setup / ready | status text | hidden |
| listening | elapsed / listening | **red glow + timer** |
| transcribing | “Transcribing…” | **orange glow** (no timer) |
| success / failed | brief | green / red glow, then hide |

HUD intentionally has **no words** — phase is color only; duration is digits.

## Dictation modes

| Mode | ⌥Space | UI |
|------|--------|-----|
| **Hold** | Down → start; Up → stop + transcribe | Hold to Speak |
| **Toggle** | Down toggles start/stop; Up ignored | Start / Stop |

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

Without metallib next to the executable, MLX crashes at startup.

## Dependencies

- **speech-swift** → Qwen3ASR, SpeechVAD, AudioCommon (MLX transitive)
- **Sparkle** → in-app updates (appcast on fuckwisprflow.com)
- Model default: Qwen3-ASR 0.6B MLX (size selectable in Settings)
- Cache: `~/Library/Caches/qwen3-speech/` (and related)

## CLI flags

| Flag | Behavior |
|------|----------|
| `--open-dashboard` | Open main window after AppState is ready |
| `--self-test` | Smoke: status item, model, hold/toggle API, synthetic hotkey |

## Activation policy

- Default: `.accessory` (menu bar only, no Dock).
- Dashboard open: temporarily `.regular` so the window can key-focus.
- Last titled window closed: back to `.accessory`.

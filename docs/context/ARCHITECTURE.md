# MacWispr architecture (current)

## Runtime shape

```
┌─────────────────────────────────────────────────────────┐
│  NSStatusItem (waveform)  →  NSPopover (MenuBarView)     │
│  ⌥Space HotkeyManager     →  AppState start/stop          │
│  Dashboard NSWindow       →  MainWindowView               │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│ AppState (@MainActor)                                     │
│  • dictationMode: hold | toggle                           │
│  • AudioRecorder → samples @ 16 kHz                       │
│  • TranscriptionEngine (Qwen3ASR actor)                   │
│  • TextInserter (clipboard / type / both)                 │
│  • HistoryStore + UsageStats                              │
└─────────────────────────────────────────────────────────┘
```

## Dictation modes

| Mode | ⌥Space | UI |
|------|--------|-----|
| **Hold** | Down → start; Up → stop + transcribe | **Hold to Speak** press-and-hold button |
| **Toggle** | Down toggles start/stop; Up ignored | **Start Listening** / **Stop & Transcribe** |

## Hotkey pipeline

1. Prefer `CGEvent.tapCreate` (session, head insert, default tap) to **swallow** ⌥Space.  
2. Always also register **global** (+ local) `NSEvent` monitors as backup.  
3. If tap swallows, monitors do not see the event (no double-fire).  
4. Callbacks hop to main queue → `AppState`.

Accessibility is required for a working tap (and for paste into other apps).

## Packaging

`scripts/build-app.sh`:

1. `swift build -c release --product MacWispr`  
2. Build `mlx.metallib` via speech-swift’s `build_mlx_metallib.sh`  
3. Copy binary + `mlx.metallib` / `default.metallib` into `MacWispr.app`  
4. Generate `AppIcon.icns` + `AppLogo.png` from `docs/assets/logo.png`  
5. Zip for releases  

Without metallib next to the executable, MLX crashes at startup.

## Dependencies

- **speech-swift** → Qwen3ASR, SpeechVAD, AudioCommon (MLX transitive)  
- Model: `aufklarer/Qwen3-ASR-0.6B-MLX-4bit`  
- Cache: `~/Library/Caches/qwen3-speech/`  

## CLI flags

| Flag | Behavior |
|------|----------|
| `--open-dashboard` | Open main window after AppState is ready |
| `--self-test` | Smoke: status item, model, hold/toggle API, synthetic hotkey |

## Activation policy

- Default: `.accessory` (menu bar only, no Dock).  
- Dashboard open: temporarily `.regular` so the window can key-focus.  
- Last titled window closed: back to `.accessory`.

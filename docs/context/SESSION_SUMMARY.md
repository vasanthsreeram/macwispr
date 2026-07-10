# Session summary — MacWispr install, fixes, and debloat

**Date:** 2026-07-11  
**Branch:** `main`  
**Latest relevant commits:** `e81baf7` … `eba1c61`

This document captures what was done in the long interactive session: install, crash fix, UX experiments, debloat, and hotkey testing.

---

## Product

**MacWispr** — on-device voice dictation for macOS (Apple Silicon), Qwen3-ASR 0.6B via MLX. Menu-bar app; hold or toggle dictation; insert text system-wide.

**Requirements:** macOS 14+, arm64, Microphone + Accessibility, ~300MB+ model cache on first run.

---

## Timeline of changes (high level)

| Area | What happened | Outcome |
|------|----------------|---------|
| **Install** | Prebuilt GitHub release preferred over source build | v1.1.0 zip install; avoid wrong `__MACOSX` path when unzipping |
| **Launch crash** | Release `.app` missing `mlx.metallib` | Packaging fix in `scripts/build-app.sh`; metallib next to binary |
| **Dashboard** | “Open Dashboard” no-op from menu | AppKit-hosted window via `AppDelegate.showDashboard()` |
| **Logo** | New blue/white waveform icon | `docs/assets/logo.png` + `AppIcon.icns` / `AppLogo.png` |
| **Sounds** | Start/stop chimes | `FeedbackSounds.swift` (Tink / Pop); toggle in Settings |
| **⌥Space typing** | Space leaked into focused app | `CGEvent` tap swallows ⌥Space when possible |
| **Floating pill** | Superwhisper-style top indicator | Added, then **removed** (notch traps / complexity) |
| **Token streaming** | Partial text during decode | Added, then **removed** (debloat) |
| **Menu bar icon** | `MenuBarExtra` unreliable / logo not template | **`NSStatusItem`** via `StatusBarController` |
| **Dictation UX** | Inconsistent hotkey only | **Hold to Speak** button + **Start/Stop** toggle + Hold/Toggle modes |
| **Hotkey testing** | User reported shortcut dead | `--self-test` + synthetic/CGEvent inject; code path works when AX trusted |

---

## Current feature set (after debloat)

### Kept
- Menu bar waveform icon (`StatusBarController`)
- Panel: status, model load, Hold/Toggle mode, **Hold to Speak**, **Start Listening**, dashboard/settings/quit
- ⌥Space: **Hold** or **Toggle** mode (Settings + panel)
- Sound feedback on start/stop (optional)
- Dashboard window (time saved / history)
- Metallib bundled in `.app` build
- `--self-test` and `--open-dashboard` CLI flags

### Removed (intentionally)
- Floating hover pill over the desktop
- Live token streaming UI + direct MLX package dependency for custom decode
- Notch clamp / drag hosting complexity

---

## Key files

```
Sources/
  MacWisprApp.swift          App entry; wires AppDelegate + status bar
  AppDelegate.swift          Dashboard window; --self-test; AX prompt
  AppState.swift             Recording, model load, modes, hotkey callbacks
  StatusBarController.swift  NSStatusItem + NSPopover menu
  MenuBarView.swift          Popover UI (hold button, toggle, mode)
  HotkeyManager.swift        Event tap + global/local monitors for ⌥Space
  TranscriptionEngine.swift  Qwen3ASR load + one-shot transcribe
  FeedbackSounds.swift       Start/stop system sounds
  TextInserter.swift         Clipboard / type-out insert
  MainWindowView.swift       Dashboard shell + dictate tab
  DashboardView.swift        Time-saved metrics
  SettingsView.swift         Insertion, sounds, dictation mode, AX
  AudioRecorder.swift        Mic → 16 kHz float samples
  UsageStats.swift           History + WPM estimates

scripts/
  build-app.sh               Release .app + mlx.metallib + icon
  install.sh                 Build → /Applications
```

---

## How to build / run

```bash
# From repo
./scripts/install.sh
open -a MacWispr

# App bundle only
./scripts/build-app.sh
open dist/MacWispr.app

# Automated smoke test (status item, model, hold/toggle API, synthetic hotkey)
/Applications/MacWispr.app/Contents/MacOS/MacWispr --self-test
```

**Metal toolchain** (for metallib on fresh machines):

```bash
xcodebuild -downloadComponent MetalToolchain
```

---

## Self-test results (session)

When run with Accessibility available to the process:

- Status item present  
- Model loaded  
- Hold start/stop API  
- Toggle start/stop API  
- Synthetic hotkey DOWN → recording  
- Synthetic hotkey UP → stopped  
- CGEvent inject could fire the hotkey path  

**Implication:** If the user’s physical keyboard still fails, prefer checking **System Settings → Privacy & Security → Accessibility** (and Input Monitoring) for **this** `/Applications/MacWispr.app` binary after each reinstall/codesign.

---

## Important bugs fixed

1. **MLX metallib missing** — app exited with `Failed to load the default metallib`  
2. **Dashboard open** — title lookup / MenuBarExtra dismissed actions  
3. **Menu bar missing** — custom logo as non-template `MenuBarExtra` label; fixed with `NSStatusItem` + SF Symbol template  
4. **Debloat** — floating + streaming removed after UX/regession cost  

---

## Open / known issues

| Issue | Notes |
|-------|--------|
| Physical ⌥Space flaky for some installs | Usually Accessibility not bound to current app path; re-add MacWispr in Settings |
| Unsigned / ad-hoc signed app | Gatekeeper; re-grant TCC after replace in `/Applications` |
| Space may still type if only monitor fallback | Event tap failed; needs Accessibility |
| Prebuilt GitHub zip | May lag behind packaging fixes until a new release is cut |

---

## Related commits (session)

```
e81baf7 Fix release crash: bundle MLX metallib in the app package
a8a9d24 Fix Open Dashboard doing nothing from the menu bar
6a655ae Use new blue/white waveform logo and fix Open Dashboard click
23bde93 Swallow ⌥Space via event tap and fix listening chimes
befc2d9 Add Superwhisper-style floating listening indicator   (later removed)
364f31f Stream transcription tokens live during inference   (later removed)
07b7b96 Fix ⌥Space hotkey reliability and floating pill notch trapping
fbaad91 Debloat: remove floating pill and streaming complexity
e8a0e2a Fix menu bar icon and add hold + toggle dictation controls
eba1c61 Test and harden ⌥Space hotkey with synthetic event self-test
```

See also: [ARCHITECTURE.md](./ARCHITECTURE.md), [KNOWN_ISSUES.md](./KNOWN_ISSUES.md).

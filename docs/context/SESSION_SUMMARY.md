# Session summary — MacWispr product evolution

**Branch for releases:** `main`  
**Shipped / shipping line:** **1.2.3** (Parakeet + Qwen; Developer ID Team `UTSTY3J6NS`)  
**Not in 1.2.3:** fine-tuned LFM polish → branch **`feat/native-lfm-polish` only**  
**Agent guide:** [AGENTS.md](../../AGENTS.md) · **Release scope:** [RELEASE_1.2.3.md](./RELEASE_1.2.3.md)

This document captures major product milestones so agents do not re-learn them from scratch.

---

## Product

**MacWispr** — on-device voice dictation for macOS (Apple Silicon). Menu-bar app; hold or toggle dictation; insert text system-wide; local **Qwen (MLX)** + **Parakeet (Core ML)**; optional BYOK cloud STT; optional transcript polish (Qwen chat / OpenAI on `main`); opt-in anonymous telemetry.

**Requirements:** macOS 14+, arm64, Microphone + Accessibility, full Xcode for metallib builds, ~300MB+ model cache on first local run.

---

## Timeline (high level)

| Area | Outcome |
|------|---------|
| **Install / metallib** | Packaged `mlx.metallib`; preflight requires full Xcode.app |
| **Dashboard** | AppKit-hosted window via `AppDelegate.showDashboard()` |
| **Hotkey** | CGEvent tap + Carbon + monitors; Accessibility repair UX |
| **Menu bar** | `NSStatusItem` + `StatusBarController` (not MenuBarExtra-only) |
| **Dictation UX** | Hold + Toggle modes; pipeline phases in menu bar |
| **Listening HUD** | Minimal floating capsule: **glowing phase dot + elapsed timer only** (no instructional copy) |
| **Sounds** | Soft system chimes (Tink/Pop/Glass/Funk) at low volume; mute detection |
| **Failure UX** | Non-activating failure banner + onboarding checklist |
| **Sparkle** | Auto-updates via `https://fuckwisprflow.com/appcast.xml` |
| **Signing** | Developer ID Team `UTSTY3J6NS`; notarize profile `MacWispr-notary` when Keychain set |
| **Telemetry** | Privacy-first opt-in PostHog client; live project key in 1.2.2+ builds |
| **Site** | fuckwisprflow.com (Cloudflare Pages project `fuckwisprflow`) |
| **1.2.3 ASR** | Parakeet v3 En+EU (Core ML) + Qwen En+Asian; model chip; GPU free on switch (#12) |
| **LFM polish** | **Not shipped** — stays on `feat/native-lfm-polish` until a later release |

### Intentionally removed earlier

- Floating hover pill experiments that trapped under the notch
- Live token streaming UI (debloat)

---

## Current feature set (agent checklist)

### Kept / shipping

- Menu bar waveform + phase status + elapsed while listening
- **Minimal Listening HUD** (dot + number; system material capsule)
- Soft feedback sounds (optional)
- Hold / Toggle ⌥Space
- Local Qwen (MLX) + Parakeet (Core ML) + OpenAI / ElevenLabs BYOK
- Dashboard (time saved / history) + Local model quick-switch chip
- Failure banner + onboarding
- Sparkle Check for Updates
- Opt-in telemetry (`Telemetry.swift` + Settings disclosure)
- App Intents / Shortcuts hooks (`MacWisprIntents.swift`)

### Privacy hard rules

- No transcript/audio/vocabulary/clipboard/keys in telemetry
- Default telemetry **off**

---

## Key files

```
Sources/
  MacWisprApp.swift
  AppDelegate.swift
  AppState.swift
  StatusBarController.swift / MenuBarView.swift
  HotkeyManager.swift
  TranscriptionEngine.swift / CloudSTTClient.swift
  ListeningHUDController.swift   # minimal HUD
  FeedbackSounds.swift           # soft chimes
  FailureBannerController.swift
  OnboardingView.swift
  Telemetry.swift
  TextInserter.swift / UsageStats.swift
  SparkleUpdater.swift

scripts/
  build-app.sh / build-dmg.sh / install.sh
  sign-and-notarize.sh / setup-signing.sh
  release.sh

website/
  appcast.xml                    # Sparkle feed (deploy with site)
  index.html …

docs/context/                    # agent-oriented notes
AGENTS.md / CLAUDE.md            # agent entrypoints
PRIVACY.md
```

---

## How to build / run (local test before release)

```bash
./scripts/install.sh
open -a MacWispr

# App bundle only
./scripts/build-app.sh
open dist/MacWispr.app

# Smoke
/Applications/MacWispr.app/Contents/MacOS/MacWispr --self-test
```

Prefer local install + manual ⌥Space test **before** `./scripts/release.sh` and appcast deploy.

---

## Open ideas (not shipped)

- Public website **leaderboard** for opt-in users (GitHub issue #11) — separate from anonymous telemetry; needs identity + privacy design.

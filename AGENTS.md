# AGENTS.md — MacWispr

Instructions for coding agents working in this repository.

## Product

**MacWispr** is a macOS menu-bar voice dictation app (Apple Silicon, macOS 14+).

- Default STT: **on-device Qwen3-ASR via MLX**
- Optional: BYOK cloud STT (OpenAI / ElevenLabs) + optional polish
- Global hotkey: **⌥Space** (hold or toggle)
- Inserts text system-wide (Accessibility required for paste / event tap)
- Marketing site: [fuckwisprflow.com](https://fuckwisprflow.com)
- Sparkle updates: appcast at `https://fuckwisprflow.com/appcast.xml`
- Latest shipped line: **1.2.2** (Developer ID Team `UTSTY3J6NS`)

## Repo map

| Path | Role |
|------|------|
| `Sources/` | Swift app (SwiftPM product `MacWispr`) |
| `scripts/` | build, sign, DMG, release, install |
| `website/` | Marketing + **Sparkle appcast** (Cloudflare Pages `fuckwisprflow`) |
| `docs/` | GitHub Pages product page + agent context |
| `docs/context/` | Architecture, signing, known issues (agent-oriented) |
| `PRIVACY.md` | Public telemetry / privacy contract |
| `Info.plist` | Bundle ID, version, Sparkle feed URL / public key |
| `dist/` | Built `.app` / zip / DMG (local; do not commit) |

### Important sources

| File | Responsibility |
|------|----------------|
| `AppState.swift` | Recording, phases, hotkey callbacks, telemetry hooks, history |
| `HotkeyManager.swift` | CGEvent tap + Carbon hotkey + NSEvent backup |
| `TranscriptionEngine.swift` | Local MLX Qwen3ASR |
| `ListeningHUDController.swift` | Floating **minimal** HUD (glowing dot + elapsed digits only) |
| `FeedbackSounds.swift` | Soft system-sound chimes (low volume) |
| `Telemetry.swift` | Opt-in PostHog batch client (whitelisted events only) |
| `StatusBarController.swift` / `MenuBarView.swift` | Menu bar UI |
| `FailureBannerController.swift` | Non-activating failure banner |
| `OnboardingView.swift` | First-run checklist |
| `SparkleUpdater.swift` | Check for Updates |

## Privacy & telemetry (must not regress)

- Telemetry is **opt-in, off by default** (`Telemetry.shared` / Settings → Privacy).
- **Never** send: transcript text, audio, vocabulary, clipboard, API keys, hardware serials, precise location, raw timings.
- Allowed events only: `hotkey_health`, `dictation_completed`, `dictation_failed`, `opt_in`, `opt_out`.
- Transport: HTTPS PostHog `/batch` (US), anonymous install UUID.
- Project write key lives in `Telemetry.swift` (client `phc_…` key — not a personal API secret).
- Public contract: `PRIVACY.md`. Update it if the collect list changes.
- Fail-silent: network errors must never block dictation.

## UX conventions (current)

### Listening HUD

- **No instructional copy** in the floating HUD (no “Listening”, “release to…”, etc.).
- Show **glowing phase dot** + **elapsed timer** while recording only.
- Use **system materials** (`.regularMaterial` / capsules) and **system colors** (`systemRed` / `systemOrange` / `systemGreen`) — free AppKit/SwiftUI chrome, no third-party theme kit.
- Keep non-activating, mouse-transparent panel at top of screen.

### Sounds

- Soft volumes only (`FeedbackSounds` ~0.22–0.32). Do not restore near-full volume system AIFF playback.
- Optional mute detection when chimes are enabled but output is muted.

### Dictation modes

| Mode | ⌥Space |
|------|--------|
| Hold | Down start / up stop+transcribe |
| Toggle | Down toggles start/stop |

## Build & local test (before release)

```bash
# Full Xcode.app required (not CLT alone) for mlx.metallib
./scripts/preflight-xcode.sh

# Local install for manual testing — preferred before any GitHub release
export MACWISPR_VERSION=1.2.2   # or next version
source .env.signing             # if present
./scripts/install.sh            # or build-app.sh then copy to /Applications
open -a MacWispr

# Smoke
/Applications/MacWispr.app/Contents/MacOS/MacWispr --self-test
```

- Prefer **local install + try ⌥Space** over shipping immediately.
- `MACWISPR_SKIP_NOTARIZE=1` if notary Keychain profile is missing.
- Notary profile name (when configured): `MacWispr-notary`.

## Release flow (do not skip Sparkle steps)

1. Bump version in `Info.plist`, `scripts/build-*.sh` defaults, `AppVersion` fallback, website copy as needed.
2. Build + Developer ID sign (`source .env.signing && ./scripts/build-app.sh`).
3. Notarize + staple when credentials work.
4. Zip with `ditto`, **Sparkle `sign_update`** → update `website/appcast.xml` `length` + `edSignature`.
5. `./scripts/release.sh vX.Y.Z` (GitHub Release assets).
6. Deploy website: `wrangler pages deploy website --project-name=fuckwisprflow`.
7. Verify: download published zip has expected features; live appcast matches zip size/signature.

Details: [docs/SPARKLE.md](docs/SPARKLE.md), [docs/context/SIGNING.md](docs/context/SIGNING.md).

## Coding rules

- Stay on Apple Silicon / macOS 14+ assumptions.
- Keep dictation path fail-safe and non-blocking (no modal dialogs mid-dictation).
- Prefer AppKit panels that are **nonactivating** for HUD / banners so focus stays in the target app.
- Do not add autocapture, session recording, or free-text analytics.
- Do not commit `.env.signing`, private Sparkle keys, notary passwords, or `.signing/` secrets.
- Metallib must ship next to the binary (`scripts/build-app.sh` already does this).
- When docs drift, update `docs/context/*` and this file together.

## Context docs

| Doc | Use when |
|-----|----------|
| [docs/context/ARCHITECTURE.md](docs/context/ARCHITECTURE.md) | Runtime shape, phases, packaging |
| [docs/context/KNOWN_ISSUES.md](docs/context/KNOWN_ISSUES.md) | Hotkey / AX / metallib troubleshooting |
| [docs/context/SIGNING.md](docs/context/SIGNING.md) | Developer ID, TCC, notary |
| [docs/context/SESSION_SUMMARY.md](docs/context/SESSION_SUMMARY.md) | Historical session notes |
| [PRIVACY.md](PRIVACY.md) | Telemetry contract |
| [README.md](README.md) | User-facing overview |

## Out of scope unless asked

- Leaderboard / public rankings (tracked as GitHub idea; privacy-sensitive)
- Changing bundle ID or Team ID
- Shipping without a version bump when behavior changes for end users

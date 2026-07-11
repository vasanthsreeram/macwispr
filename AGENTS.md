# AGENTS.md — MacWispr

Instructions for coding agents working in this repository.

## Product

**MacWispr** is a macOS menu-bar voice dictation app (Apple Silicon, macOS 14+).

- On-device STT:
  - **Qwen3-ASR** via **MLX** (GPU) — 0.6B / 1.7B 8-bit
  - **Parakeet TDT v3** via **Core ML** (Neural Engine) — INT4 / INT8
- Default model: **Qwen 1.7B** when system RAM **> 16 GB**, else **Qwen 0.6B** (user can override; Parakeet is opt-in)
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
| `ASRModelSize.swift` | On-device model catalog (Qwen + Parakeet) + RAM default |
| `HotkeyManager.swift` | CGEvent tap + Carbon hotkey + NSEvent backup |
| `TranscriptionEngine.swift` | Local **Qwen3ASR** (MLX) + **ParakeetASR** (Core ML) actor |
| `ListeningHUDController.swift` | Optional banner under menu bar (Listening / Done + STT latency) |
| `FeedbackSounds.swift` | Configurable system-sound chimes + volume |
| `Telemetry.swift` | Opt-in PostHog batch client (whitelisted events only) |
| `StatusBarController.swift` / `MenuBarView.swift` | Menu bar UI (live status + timer) |
| `FailureBannerController.swift` | Non-activating failure banner |
| `OnboardingView.swift` | First-run checklist |
| `SettingsView.swift` | Simplified tabs: General / Transcription / Hotkeys / About |
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

### Status surfaces

- **Primary:** system **menu bar** `NSStatusItem` (Apple’s Mac surface for live status — not Dynamic Island).
- **Optional banner:** floating non-activating capsule **under** the menu bar (Listening + timer; Done + word count + STT latency). Not a notch-integrated island (no third-party API for that on Mac).
- Failure: non-activating banner with Fix Accessibility / Open Setup.

### Sounds

- Master toggle + **volume** + **per-event chime** (start / stop / done / error) via `FeedbackSoundPreferences`.
- Soft ceiling so 100% isn’t ear-splitting next to a laptop mic.
- Optional mute detection when chimes are enabled but output is muted.

### Settings layout

- **General:** insertion → time saved (WPM up to **200**) → history → privacy → **post-processing last**
- **Transcription:** status + language → model dropdown (Qwen / Parakeet) → vocabulary → **provider + BYOK keys last** (keys expand only for cloud)
- **Hotkeys:** mode, sounds, banner, permissions

### Dictation modes

| Mode | ⌥Space |
|------|--------|
| Hold | Down start / up stop+transcribe |
| Toggle | Down toggles start/stop |

### On-device engines

| Engine | Hardware | Custom vocab context |
|--------|----------|----------------------|
| Qwen3-ASR | MLX / GPU | Yes |
| Parakeet TDT v3 | Core ML / ANE | No |

## Build & local test (before release)

```bash
# Full Xcode.app required (not CLT alone) for mlx.metallib
./scripts/preflight-xcode.sh

# Local install (Developer ID if .env.signing present; skip notary with unset MACWISPR_NOTARY_PROFILE)
set -a && source .env.signing && set +a
unset MACWISPR_NOTARY_PROFILE
export MACWISPR_VERSION=1.2.2
./scripts/build-app.sh
rm -rf /Applications/MacWispr.app && cp -R dist/MacWispr.app /Applications/
open -a MacWispr
```

## Release (short)

1. Bump `Info.plist` / scripts version if shipping a new version number
2. `./scripts/build-app.sh` (+ Developer ID / notarize when ready)
3. `sign_update` on zip → update `website/appcast.xml`
4. `./scripts/release.sh vX.Y.Z`
5. `wrangler pages deploy website --project-name=fuckwisprflow`

See `docs/SPARKLE.md` and `docs/context/SIGNING.md`.

## Do not

- Commit `.env.signing`, `.signing/`, private Sparkle keys, or `dist/`
- Force-push `main` or rewrite published release tags without explicit user request
- Reintroduce a fake Dynamic Island / notch overlay as “system integration”
- Send transcript content through telemetry

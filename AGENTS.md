# AGENTS.md — MacWispr

Instructions for coding agents working in this repository.

## Product

**MacWispr** is a macOS menu-bar voice dictation app (Apple Silicon, macOS 14+).

- On-device STT (UI labels — language coverage first):
  - **Qwen 0.6B (En + Asian)** / **Qwen 1.7B (En + Asian)** via **MLX** (GPU)
  - **Parakeet v3 (En + EU)** via **Core ML** (Neural Engine)
- Dashboard chip shows **Local** (or OpenAI / ElevenLabs); model detail is in the menu / subtitle
- Default model: **Qwen 1.7B** when system RAM **> 16 GB**, else **Qwen 0.6B** (user can override; Parakeet is opt-in)
- Optional: BYOK cloud STT (OpenAI / ElevenLabs) + optional **local polish** (Qwen3.5-0.8B SFT via MLX; R&D — see [POLISH_TRAINING.md](docs/context/POLISH_TRAINING.md))
- Global hotkey: **⌥Space** (hold or toggle)
- Inserts text system-wide (Accessibility required for paste / event tap)
- Marketing site: [fuckwisprflow.com](https://fuckwisprflow.com)
- Sparkle updates: appcast at `https://fuckwisprflow.com/appcast.xml`
- Latest ship line: **1.2.3** from **`main`** only (Developer ID Team `UTSTY3J6NS`; Parakeet + Qwen)
- **Do not** include branch `feat/native-lfm-polish` (LFM2.5 fine-tuned polish) in 1.2.3 — keep that branch separate until a later release ([docs/context/RELEASE_1.2.3.md](docs/context/RELEASE_1.2.3.md))

## Repo map

| Path | Role |
|------|------|
| `Sources/` | Swift app (SwiftPM product `MacWispr`) |
| `scripts/` | build, sign, DMG, release, install |
| `website/` | Marketing (edgy) + **Sparkle appcast** (Cloudflare Pages `fuckwisprflow`) |
| `website-macwispr/` | Soft product site (Cloudflare Pages `macwispr` → `macwispr.lintware.com`) |
| `docs/` | GitHub Pages product page + agent context |
| `docs/context/` | Architecture, language/stack choice, signing, known issues (agent-oriented) |
| `docs/context/POLISH_TRAINING.md` | On-device **polish** SFT log (Qwen3.5 Base, two-pass data, metrics) — R&D |
| `docs/context/POLISH_RND_PUBLIC_BRIEF.md` | Public-facing R&D copy deck for website timeline |
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
| `StatusBarController.swift` / `MenuBarView.swift` | Menu bar popover (stats + nav; single hosting controller) |
| `DashboardView.swift` | Time Saved + top-right Local model chip |
| `FailureBannerController.swift` | Non-activating failure banner |
| `OnboardingView.swift` | First-run checklist |
| `SettingsView.swift` | Simplified tabs: General / Transcription / Hotkeys / About |
| `TextPolisher.swift` | On-device MLX polish (bare `### Input`/`### Output`; polish **before** paste) |
| `PolishLocalModel.swift` | Local polish pack catalog (default `PolishModel` = Qwen enum SFT; optional LFM) |
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
- **Transcription:** status + language → model dropdown → vocabulary → **provider + BYOK keys last** (keys expand only for cloud)
- **Hotkeys:** mode, sounds, banner, permissions
- **Dashboard:** top-right **Local** chip with model menu (same catalog as Settings)

### Dictation modes

| Mode | ⌥Space |
|------|--------|
| Hold | Down start / up stop+transcribe |
| Toggle | Down toggles start/stop |

### On-device engines (user labels)

| UI name | Hardware | Languages (cue) | Custom vocab |
|---------|----------|-----------------|--------------|
| Qwen 0.6B (En + Asian) | MLX / GPU | English + Asian | Yes |
| Qwen 1.7B (En + Asian) | MLX / GPU | English + Asian | Yes |
| Parakeet v3 (En + EU) | Core ML / ANE | English + European | No |

Catalog: `ASRModelSize.swift` (`displayName` / `shortName`).

## Build & local test (before release)

```bash
# Full Xcode.app required (not CLT alone) for mlx.metallib
./scripts/preflight-xcode.sh

# Local install (Developer ID if .env.signing present; skip notary with unset MACWISPR_NOTARY_PROFILE)
set -a && source .env.signing && set +a
unset MACWISPR_NOTARY_PROFILE
export MACWISPR_VERSION=1.2.3
./scripts/build-app.sh
rm -rf /Applications/MacWispr.app && cp -R dist/MacWispr.app /Applications/
open -a MacWispr
```

## Release (short)

**Always ship from `main`.** For 1.2.3 scope and “what is not included,” see [docs/context/RELEASE_1.2.3.md](docs/context/RELEASE_1.2.3.md).

1. Confirm branch is `main` (not `feat/native-lfm-polish`)
2. Bump `Info.plist` / scripts version if shipping a new version number
3. `source .env.signing && export MACWISPR_VERSION=… && ./scripts/build-app.sh` (Developer ID + notary)
4. `sign_update` on zip → update `website/appcast.xml`
5. `./scripts/release.sh vX.Y.Z`
6. `wrangler pages deploy website --project-name=fuckwisprflow`

See `docs/SPARKLE.md` and `docs/context/SIGNING.md`.

**Stack choice:** stay on **Swift**. Size/RAM are model + MLX-bound, not language-bound. Do not rewrite in Rust/Zig/Bun for “lighter” alone — [docs/context/LANGUAGE_STACK.md](docs/context/LANGUAGE_STACK.md).

## Do not

- Commit `.env.signing`, `.signing/`, private Sparkle keys, or `dist/`
- Force-push `main` or rewrite published release tags without explicit user request
- Reintroduce a fake Dynamic Island / notch overlay as “system integration”
- Send transcript content through telemetry
- Full rewrite in Rust / Zig / Bun / JS unless explicitly requested (see [LANGUAGE_STACK.md](docs/context/LANGUAGE_STACK.md))
- Merge **`feat/native-lfm-polish`** into a **1.2.3** release (LFM fine-tune stays on that branch)

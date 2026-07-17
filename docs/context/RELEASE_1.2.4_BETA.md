# MacWispr 1.2.4-beta — polish beta

**Status:** **Published** GitHub **pre-release** `v1.2.4-beta.1` (2026-07-17).  
**Repo version (`Info.plist` / scripts default):** **1.2.4-beta.1**.  
**Does not replace** stable **1.2.3** as Sparkle / [`releases/latest`](https://github.com/vasanthsreeram/macwispr/releases/latest).  
**Ship from:** `main` only (Qwen polish SFT path — **not** `feat/native-lfm-polish`).

| | |
|---|---|
| **Release page** | https://github.com/vasanthsreeram/macwispr/releases/tag/v1.2.4-beta.1 |
| **DMG** | [MacWispr-1.2.4-beta.1-macos-arm64.dmg](https://github.com/vasanthsreeram/macwispr/releases/download/v1.2.4-beta.1/MacWispr-1.2.4-beta.1-macos-arm64.dmg) (~1.2–1.3 GB) |
| **Zip** | [MacWispr-1.2.4-beta.1-macos-arm64.zip](https://github.com/vasanthsreeram/macwispr/releases/download/v1.2.4-beta.1/MacWispr-1.2.4-beta.1-macos-arm64.zip) (~1.2 GB) |
| **Signing** | **Developer ID** Team `UTSTY3J6NS` (hardened runtime) |
| **Notarization** | **Yes** — stapled (`notarytool` profile `MacWispr-notary`; submission `c85f4f1b-…` **Accepted**) |
| **Sparkle** | **Not** promoted — `website/appcast.xml` stays on **1.2.3** |
| **`spctl`** | `accepted` · `source=Notarized Developer ID` |

## What’s in 1.2.4-beta.1

| Area | Change |
|------|--------|
| **Local polish (bundled)** | Qwen3.5-0.8B full-SFT pack (`PolishModel` = enum-continued) via **MLX** |
| **Polish before paste** | Formatted text is inserted at the cursor (not history/clipboard-only) |
| **No hardcoded filler strip** | Removed fixed uh/um/so… regex list; polish model owns cleanup |
| **Dev capture (opt-in)** | Settings → Developer: local WAV + raw STT / post-process / polished under Application Support |
| **#14 / #15** | Merged from `fix/14-15-window-and-history`: single AppKit dashboard (no dual SwiftUI `Window`), Cmd+Q works; history **only** in detail pane |
| **Polish telemetry (content-free)** | Opt-in buckets: polish on/off class, polish latency/word-count buckets, shape flags (`has_newlines`, `looks_like_list`), coarse `ui_open` — **never** transcript text or keystrokes |
| **Installer DMG** | Large icons + branded drag-to-Applications background (`dmgbuild`) |
| **Everything from 1.2.3** | Parakeet v3 En+EU, Qwen 0.6B/1.7B En+Asian, model chip, GPU free on switch, etc. |

Training / R&D: [POLISH_TRAINING.md](./POLISH_TRAINING.md). Privacy: [PRIVACY.md](../../PRIVACY.md).

## Explicitly out

| Item | Notes |
|------|--------|
| **LFM / Sotto polish** | Still on **`feat/native-lfm-polish` only** |
| **Sparkle auto-update to beta** | Appcast stays on stable 1.2.3 |
| **Personal / federated fine-tune** | Not in this beta |
| **Transcript / keystroke telemetry** | Forbidden — local **dev capture** only for full pre/post text |

## Install (end user)

1. Download the **DMG** from the [pre-release](https://github.com/vasanthsreeram/macwispr/releases/tag/v1.2.4-beta.1)  
2. **Quit** any running MacWispr  
3. Drag **MacWispr** into **Applications** (replace older build)  
4. Open **from Applications** (not a repo `dist/` folder)  
5. Grant **Microphone** + **Accessibility**  
6. Optional: Settings → Post-Processing → **Local LLM** polish  

> Large download: polish weights ship **inside** the app (~1.4 GB on disk).  
> Polish is **off by default**.  
> Notarized builds should open without the “Apple could not verify…” block.

### Dev capture (optional)

Settings → General → **Developer → Save audio + text locally**:

`~/Library/Application Support/MacWispr/dev-captures/<timestamp>_<id>/`

- `audio.wav`, `01_raw_stt.txt`, `02_postprocess.txt`, `03_polished.txt`, `meta.json`  
- **Never** uploaded by telemetry  
- Env force: `MACWISPR_DEV_CAPTURE=1`

### Clean install / “wrong binary” pitfall

macOS LaunchServices can open an **older** `MacWispr.app` that still lives under a **repo `dist/`** path (same bundle id `com.vasanthsreeram.macwispr`). Symptom: multi-window / missing #14–#15 fixes even though `/Applications` shows 1.2.4-beta.1.

**Check which binary is running:**

```bash
pgrep -x MacWispr | while read p; do ps -p "$p" -o command=; done
# Expect: /Applications/MacWispr.app/Contents/MacOS/MacWispr
# Bad:    …/Documents/macwispr/dist/MacWispr.app/…
```

**Hard clean:**

```bash
pkill -x MacWispr || true
rm -rf /Applications/MacWispr.app
# Disable leftover build products (do not leave as MacWispr.app)
# e.g. mv dist/MacWispr.app dist/MacWispr.OLD-DISABLED.app
ditto /path/to/fresh/MacWispr.app /Applications/MacWispr.app
open /Applications/MacWispr.app
```

Re-register if needed:  
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MacWispr.app`

## Build / republish (maintainer)

```bash
git checkout main
export MACWISPR_VERSION=1.2.4-beta.1
export MACWISPR_SIGN_IDENTITY="Developer ID Application: Vasanth Sreeram (UTSTY3J6NS)"
export MACWISPR_NOTARY_PROFILE="MacWispr-notary"   # required for Gatekeeper-clean beta
export POLISH_MODEL_SRC="$HOME/.cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-enum"
./scripts/build-app.sh          # sign + notary + staple + zip
./scripts/build-dmg.sh          # dmgbuild layout + background

# Pre-release only — do NOT use --latest
gh release upload "v${MACWISPR_VERSION}" \
  "dist/MacWispr-${MACWISPR_VERSION}-macos-arm64.zip" \
  "dist/MacWispr-${MACWISPR_VERSION}-macos-arm64.dmg" \
  --clobber
```

Verify:

```bash
spctl -a -vv dist/MacWispr.app
# accepted · source=Notarized Developer ID
xcrun stapler validate dist/MacWispr.app
```

Do **not** update `website/appcast.xml` for beta unless intentionally promoting.

## Relationship to 1.2.3

| Line | Role |
|------|------|
| **1.2.3** | Stable ship + Sparkle + `releases/latest` |
| **1.2.4-beta.1** | Opt-in polish beta (pre-release only); larger download |

When polish is ready for everyone: cut a non-beta **1.2.4+**, update appcast, mark GitHub Latest.

See also: [RELEASE_1.2.3.md](./RELEASE_1.2.3.md), [POLISH_TRAINING.md](./POLISH_TRAINING.md), [SIGNING.md](./SIGNING.md), [KNOWN_ISSUES.md](./KNOWN_ISSUES.md).

# MacWispr 1.2.4-beta — polish beta

**Status:** **Published** GitHub **pre-release** `v1.2.4-beta.1` (2026-07-17).  
**Repo version (`Info.plist` / scripts default):** **1.2.4-beta.1**.  
**Does not replace** stable **1.2.3** as Sparkle / [`releases/latest`](https://github.com/vasanthsreeram/macwispr/releases/latest).  
**Ship from:** `main` only (Qwen polish SFT path — **not** `feat/native-lfm-polish`).

| | |
|---|---|
| **Release page** | https://github.com/vasanthsreeram/macwispr/releases/tag/v1.2.4-beta.1 |
| **DMG** | [MacWispr-1.2.4-beta.1-macos-arm64.dmg](https://github.com/vasanthsreeram/macwispr/releases/download/v1.2.4-beta.1/MacWispr-1.2.4-beta.1-macos-arm64.dmg) (~1.2 GB) |
| **Zip** | [MacWispr-1.2.4-beta.1-macos-arm64.zip](https://github.com/vasanthsreeram/macwispr/releases/download/v1.2.4-beta.1/MacWispr-1.2.4-beta.1-macos-arm64.zip) (~1.2 GB) |
| **Signing** | **Developer ID** Team `UTSTY3J6NS` (hardened runtime) |
| **Notarization** | **Not** stapled in this beta (no notary profile at cut time) — first launch may need **right-click → Open** |
| **Sparkle** | **Not** promoted — `website/appcast.xml` stays on **1.2.3** |

## What’s in 1.2.4-beta.1

| Area | Change |
|------|--------|
| **Local polish (bundled)** | Qwen3.5-0.8B full-SFT pack (`PolishModel` = enum-continued) via **MLX** |
| **Polish before paste** | Formatted text is inserted at the cursor (not history/clipboard-only) |
| **No hardcoded filler strip** | Removed fixed uh/um/so… regex list (broke phrases like “and so on”); polish model owns cleanup |
| **Dev capture (opt-in)** | Settings → Developer: local WAV + raw STT / post-process / polished under Application Support |
| **#14 / #15** | Single dashboard window + Cmd+Q; history only in detail pane (not duplicated sidebar) |
| **Polish telemetry (content-free)** | Opt-in buckets only: polish on/off, latency/word-count buckets, shape flags — **no** transcript text, **no** keystrokes |
| **Everything from 1.2.3** | Parakeet v3 En+EU, Qwen 0.6B/1.7B En+Asian, model chip, GPU free on switch, etc. |

Training / R&D detail: [POLISH_TRAINING.md](./POLISH_TRAINING.md). Public timeline: `/rnd` on fuckwisprflow.

## Explicitly out

| Item | Notes |
|------|--------|
| **LFM / Sotto polish** | Still on **`feat/native-lfm-polish` only** — do not merge into beta/stable cut |
| **Sparkle auto-update to beta** | Appcast intentionally stays on stable 1.2.3 |
| **Notarized Gatekeeper path** | Revisit for 1.2.4 final / next beta when notary credentials available |
| **Personal / federated fine-tune** | Not in this beta |

## Install (end user)

1. Download the **DMG** (or zip) from the [pre-release](https://github.com/vasanthsreeram/macwispr/releases/tag/v1.2.4-beta.1)  
2. Drag **MacWispr** into **Applications** (replace any older build)  
3. If macOS blocks open: **right-click → Open** (or Privacy & Security → Open Anyway)  
4. Grant **Microphone** + **Accessibility**  
5. Optional: Settings → Post-Processing → **Local LLM** polish to load the bundled model  

> Large download because polish weights ship **inside** the app (~1.4 GB on disk; ~1.2 GB compressed).  
> Polish is **off by default**.

### Dev capture (optional)

Settings → General → **Developer → Save audio + text locally** writes:

`~/Library/Application Support/MacWispr/dev-captures/<timestamp>_<id>/`

- `audio.wav` — 16 kHz mono  
- `01_raw_stt.txt` / `02_postprocess.txt` / `03_polished.txt`  
- `meta.json`  

Never uploaded by telemetry. Or force with env `MACWISPR_DEV_CAPTURE=1`.

## Build / republish (maintainer)

```bash
git checkout main
export MACWISPR_VERSION=1.2.4-beta.1
export MACWISPR_SIGN_IDENTITY="Developer ID Application: Vasanth Sreeram (UTSTY3J6NS)"
unset MACWISPR_NOTARY_PROFILE   # set profile when notarizing
export POLISH_MODEL_SRC="$HOME/.cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-enum"
./scripts/build-app.sh
./scripts/build-dmg.sh   # needs extra HFS headroom for polish pack

# Pre-release only — do NOT pass --latest (keeps 1.2.3 as Latest)
gh release create "v${MACWISPR_VERSION}" \
  "dist/MacWispr-${MACWISPR_VERSION}-macos-arm64.zip" \
  "dist/MacWispr-${MACWISPR_VERSION}-macos-arm64.dmg" \
  --title "MacWispr v${MACWISPR_VERSION}" \
  --prerelease \
  --notes-file docs/context/RELEASE_1.2.4_BETA.md
# or: gh release upload … --clobber if the tag/release already exists
```

Do **not** update `website/appcast.xml` for beta unless intentionally promoting a channel.

## Relationship to 1.2.3

| Line | Role |
|------|------|
| **1.2.3** | Stable ship + Sparkle + `releases/latest` |
| **1.2.4-beta.1** | Opt-in polish beta; larger download; pre-release only |

When polishing is ready for everyone: cut **1.2.4** (or later) non-beta from `main`, notarize, update appcast, then mark GitHub Latest.

See also: [RELEASE_1.2.3.md](./RELEASE_1.2.3.md), [POLISH_TRAINING.md](./POLISH_TRAINING.md), [SIGNING.md](./SIGNING.md), [PRIVACY.md](../../PRIVACY.md).

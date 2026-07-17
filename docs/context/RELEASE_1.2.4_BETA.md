# MacWispr 1.2.4-beta — polish beta

**Status:** **Beta / pre-release** on GitHub (`v1.2.4-beta.1`).  
**Does not replace** stable **1.2.3** as Sparkle / `releases/latest`.  
**Ship from:** `main` (Qwen polish SFT path — **not** `feat/native-lfm-polish`).

## What’s in 1.2.4-beta.1

| Area | Change |
|------|--------|
| **Local polish (bundled)** | Qwen3.5-0.8B full-SFT pack (`PolishModel`, enum-continued) via MLX |
| **Polish before paste** | Formatted text is inserted at the cursor (not history/clipboard-only) |
| **No hardcoded filler strip** | Removed fixed uh/um/so… regex list; polish model owns cleanup |
| **Dev capture (opt-in)** | Settings → Developer: local WAV + raw/post/polished text stages |
| **Everything from 1.2.3** | Parakeet + Qwen ASR, model chip, etc. |

## Explicitly out

| Item | Notes |
|------|--------|
| **LFM / Sotto polish** | Still on `feat/native-lfm-polish` only |
| **Sparkle promotion of beta** | Appcast stays on stable 1.2.3 until a non-beta cut |
| **Personal / federated fine-tune** | Not in this beta |

## Install (beta)

1. Download DMG or zip from the GitHub **pre-release** `v1.2.4-beta.1`  
2. Drag to Applications (or replace existing test build)  
3. Grant **Microphone** + **Accessibility**  
4. Settings → Post-Processing → **Local LLM** polish to try the bundled model  

> Large download (~1.5+ GB compressed) because the polish weights ship inside the app.

## Build (maintainer)

```bash
git checkout main
export MACWISPR_VERSION=1.2.4-beta.1
export MACWISPR_SIGN_IDENTITY="Developer ID Application: Vasanth Sreeram (UTSTY3J6NS)"
unset MACWISPR_NOTARY_PROFILE   # optional for beta if notary profile missing
export POLISH_MODEL_SRC="$HOME/.cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-enum"
./scripts/build-app.sh
./scripts/build-dmg.sh
# Publish as pre-release (do not use --latest)
gh release create "v${MACWISPR_VERSION}" \
  dist/MacWispr-${MACWISPR_VERSION}-macos-arm64.zip \
  dist/MacWispr-${MACWISPR_VERSION}-macos-arm64.dmg \
  dist/MacWispr-macos-arm64.dmg \
  --title "MacWispr v${MACWISPR_VERSION}" \
  --prerelease \
  --notes-file docs/context/RELEASE_1.2.4_BETA.md
```

See also: [POLISH_TRAINING.md](./POLISH_TRAINING.md), [RELEASE_1.2.3.md](./RELEASE_1.2.3.md).

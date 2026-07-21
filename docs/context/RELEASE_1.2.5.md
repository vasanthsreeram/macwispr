# MacWispr 1.2.5 (stable)

**Version:** 1.2.5  
**Channel:** production (`main` + Sparkle appcast + GitHub Latest)  
**Not included:** fine-tuned LFM polish (`feat/native-lfm-polish`)

## What’s new

| Change | Notes |
|--------|--------|
| **Lean Sparkle zip** | Polish weights **not** bundled (~1.2 GB → ~100–150 MB) |
| **Polish download-on-enable** | Settings → Local LLM downloads **MLX 4-bit** pack (~400 MB) from HF once |
| **Single `mlx.metallib`** | Removed duplicate `default.metallib` copies (~200 MB saved) |
| **HF pack** | `vasanth009/macwispr-polish-qwen35-08b-v3-4bit` (4-bit structure SFT v3; older enum pack remains at `vasanth009/macwispr-qwen35-08b-polish`) |
| **Live waveform HUD** | "Listening" chrome replaced by a moving RMS-driven waveform; disappears once live words start dictating |
| **Mid-recording mic switch** | Capture rebinds when the system default input changes or the device config changes (Continuity/Bluetooth mic fix) |

Polish remains **off by default**. ASR models still download separately to cache.

## Ship checklist

```bash
set -a && source .env.signing && set +a
export MACWISPR_VERSION=1.2.5
# Models are never embedded (no BUNDLE_POLISH flag).
./scripts/build-app.sh
./scripts/build-dmg.sh

SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update 2>/dev/null | head -1)"
"$SIGN_UPDATE" dist/MacWispr-1.2.5-macos-arm64.zip
./scripts/ci-update-appcast.sh 1.2.5 "<edSignature>" <length>
./scripts/release.sh v1.2.5
# deploy website/appcast.xml to fuckwisprflow.com
```

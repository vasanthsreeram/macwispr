# MacWispr 1.2.6 (stable)

**Version:** 1.2.6  
**Channel:** production (`main` + Sparkle appcast + GitHub Latest)

## What’s new

| Change | Notes |
|--------|--------|
| **Parakeet live partials** | Growing-buffer live draft while holding ⌥Space (same path as Qwen) |
| **Qwen download repair** | Incomplete HF cache → auto-purge + re-download (fixes “file couldn’t be opened”) |
| **Honest download status** | Shows “Downloading…” when weights are not on disk yet |
| **SuperWhisper-style Settings** | Left sidebar: Models · Vocabulary · Appearance · Configuration · Sound · About |
| **Models catalog** | Icon-first Voice + Polish + Cloud rows (no status-pill clutter) |
| **Appearance tiles** | Window Classic / Mini / None + **Liquid Glass** Clear / Tinted (system `glassEffect`) |
| **No model bundling** | STT + polish still download-on-demand (lean zip, same as 1.2.5) |

## Ship checklist

```bash
set -a && source .env.signing && set +a
export MACWISPR_VERSION=1.2.6
./scripts/build-app.sh          # Developer ID + notary
./scripts/build-dmg.sh
SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update 2>/dev/null | head -1)"
"$SIGN_UPDATE" dist/MacWispr-1.2.6-macos-arm64.zip
# → edSignature + length → website/appcast.xml via scripts/ci-update-appcast.sh
./scripts/release.sh v1.2.6
wrangler pages deploy website --project-name=fuckwisprflow
```

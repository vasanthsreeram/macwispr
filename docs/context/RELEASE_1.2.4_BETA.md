# MacWispr 1.2.4 beta line

**Latest beta:** **1.2.4-beta.2** (live Qwen partials)  
**Prior beta:** 1.2.4-beta.1 (polish bundle + #14/#15)  
**Stable production:** **1.2.3** (GitHub Latest / Sparkle production feed)  
**Not included:** fine-tuned LFM polish (`feat/native-lfm-polish`)

## 1.2.4-beta.2 — what’s new

| Feature | Notes |
|---------|--------|
| **Live Qwen partials** | While holding ⌥Space, re-run local Qwen on the growing buffer; monochrome 4-line HUD morphs words in |
| **Default ASR** | **Qwen 0.6B** (lighter); 1.7B and Parakeet remain selectable |
| **Final pass** | On release: full-buffer STT → optional polish → insert |
| **Polish order** | Still **before paste** (same as beta.1); live drafts are raw STT only |
| **Docs** | [LIVE_PARTIALS.md](./LIVE_PARTIALS.md) |

Plus everything in **1.2.4-beta.1**:

- Bundled Qwen3.5 local polish path
- #14 / #15 window + history
- Content-free polish telemetry (opt-in)
- Dev capture (optional)

## Ship checklist

```bash
set -a && source .env.signing && set +a
export MACWISPR_VERSION=1.2.4-beta.2
./scripts/build-app.sh          # Developer ID + notary
./scripts/build-dmg.sh

SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update 2>/dev/null | head -1)"
"$SIGN_UPDATE" dist/MacWispr-1.2.4-beta.2-macos-arm64.zip
# → paste length + edSignature into website/appcast.xml if promoting on Sparkle

# Pre-release (does not replace Latest 1.2.3)
gh release create v1.2.4-beta.2 \
  --prerelease \
  --title "MacWispr v1.2.4-beta.2" \
  --notes-file … \
  dist/MacWispr-1.2.4-beta.2-macos-arm64.zip \
  dist/MacWispr-1.2.4-beta.2-macos-arm64.dmg
```

**Sparkle:** Stable feed still points at **1.2.3** so auto-update does not push betas to all users unless the appcast is intentionally updated. Beta testers install from GitHub pre-release DMG/zip.

## Related

- [LIVE_PARTIALS.md](./LIVE_PARTIALS.md)
- [RELEASE_1.2.3.md](./RELEASE_1.2.3.md) — stable line
- [SPARKLE.md](../SPARKLE.md)

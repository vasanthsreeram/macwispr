# MacWispr 1.2.4 (stable)

**Version:** 1.2.4  
**Channel:** production (`main` + Sparkle appcast + GitHub Latest)  
**Not included:** fine-tuned LFM polish (`feat/native-lfm-polish`)

## What’s new

| Feature | Notes |
|---------|--------|
| **Live Qwen partials** | Hold ⌥Space → monochrome HUD grows with text (cap ~4 lines, then scroll) |
| **Default ASR** | **Qwen 0.6B**; 1.7B and Parakeet still selectable |
| **Polish off by default** | Inserts raw STT; enable Local LLM / OpenAI polish in Settings if desired |
| **Mic input picker** | Menu bar + Settings (Core Audio device) |
| **#14 / #15** | Single dashboard window, Cmd+Q, history layout |
| **CI workflows** | GitHub Actions CI + release pipeline scripts (optional secrets) |

## Ship checklist

```bash
set -a && source .env.signing && set +a
export MACWISPR_VERSION=1.2.4
./scripts/build-app.sh          # Developer ID + notary
./scripts/build-dmg.sh

SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update 2>/dev/null | head -1)"
"$SIGN_UPDATE" dist/MacWispr-1.2.4-macos-arm64.zip
# → length + edSignature → website/appcast.xml

./scripts/release.sh v1.2.4
wrangler pages deploy website --project-name=fuckwisprflow
```

## Related

- [LIVE_PARTIALS.md](./LIVE_PARTIALS.md)
- [RELEASE_1.2.3.md](./RELEASE_1.2.3.md)
- [SPARKLE.md](../SPARKLE.md)

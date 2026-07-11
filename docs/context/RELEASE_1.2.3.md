# MacWispr 1.2.3 — release scope

**Status (agent-maintained):** **Notarized** (submission `615fc1c0-…`, Accepted + stapled). Public ship = GitHub `v1.2.3` + appcast.  
**Version string in repo:** **1.2.3**.  
**Ship from:** `main` only (`6158724` + release doc/notes commits).  
**Do not ship from:** `feat/native-lfm-polish` (or any LFM / Sotto fine-tune polish work).

## What’s in 1.2.3 (`main`)

| Area | Change |
|------|--------|
| **Parakeet v3** | Core ML **En + EU** on-device ASR (Neural Engine), next to Qwen |
| **Qwen 0.6B / 1.7B** | MLX **En + Asian** (unchanged stack; RAM-aware default) |
| **Model UX** | Dashboard **Local** chip + quick-switch; labels by language coverage |
| **GPU free on switch** | Unload MLX + clear Metal cache when changing model / provider (#12) |
| **Parakeet short clips** | MultiArray shape fix for brief dictations |
| **Existing optional polish** | Settings: off / local **Qwen3-0.6B-Chat CoreML** / OpenAI BYOK — already on `main`, not the new LFM work |

## Explicitly out of 1.2.3

| Item | Where it lives | Notes |
|------|----------------|--------|
| **Fine-tuned AI polish (LFM2.5-350M + course-correction LoRA)** | Branch **`feat/native-lfm-polish`** | Native MLX fused model, `PolishModel` bundle, bench pipeline. **Do not merge into 1.2.3 release.** |
| Bench / Grok data / polish_server | `bench/polish_finetune/`, branch WIP | Dev only |

Keep LFM polish as a **separate branch** until a later version (e.g. 1.3.x) is intentionally cut from that work.

## Not the same as the first notary attempt

An earlier notary submission was built **before** packaging “full main” (Parakeet + post-1.2.2 UX).  
The **1.2.3 public binary** must be rebuilt from current `main`, Developer ID signed, then notarized. Treat old notary IDs as obsolete if the binary changed.

## Publish checklist

```bash
git checkout main
# Info.plist already 1.2.3 for this line

source .env.signing
export MACWISPR_VERSION=1.2.3
# Do NOT set MACWISPR_SKIP_NOTARIZE for the public ship
./scripts/build-app.sh
./scripts/build-dmg.sh

# Verify
codesign -dv --verbose=4 dist/MacWispr.app 2>&1 | grep -E 'Authority|TeamIdentifier|flags'
# expect Developer ID + runtime (not adhoc)
spctl -a -vv dist/MacWispr.app   # accepted after notary + staple

SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update | head -1)"
"$SIGN_UPDATE" dist/MacWispr-1.2.3-macos-arm64.zip
# → update website/appcast.xml (version, length, edSignature, notes)

./scripts/release.sh v1.2.3
wrangler pages deploy website --project-name=fuckwisprflow
```

## Website / marketing

- Download buttons use GitHub `latest` (becomes 1.2.3 after release).
- Appcast: `website/appcast.xml` must list **1.2.3** with Sparkle signature of the **same** zip as the GitHub asset.
- Install copy may note first-launch Gatekeeper trust until notarization is stapled.

## Related docs

- [AGENTS.md](../../AGENTS.md) — agent rules + product map  
- [SIGNING.md](./SIGNING.md) — Developer ID + notary  
- [SPARKLE.md](../SPARKLE.md) — appcast  
- [ARCHITECTURE.md](./ARCHITECTURE.md) — engines (Qwen + Parakeet)  
- [SESSION_SUMMARY.md](./SESSION_SUMMARY.md) — milestones  

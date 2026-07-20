# MacWispr 1.2.7 (stable)

**Version:** 1.2.7  
**Channel:** production (`main` + Sparkle appcast + GitHub Latest)

## What’s new

| Change | Notes |
|--------|--------|
| **Mic picker** | Top-right + Home + menu bar choose input device (replaces crashy toolbar Dictate button) |
| **Crash fix** | macOS 26 SwiftUI Button/`MainActor.assumeIsolated` crash on toolbar dictate |
| **No Dictate sidebar** | Dictation is ⌥Space / your hotkey only |
| **Recordable hotkeys** | Configuration → Keyboard Shortcuts — click to record Dictation + Cancel (Esc) |
| **AI Models** | Polish packs under “Show experimental models” (SuperWhisper-style) |
| **Toolbar chrome** | Disabled Icon and Text / Icon Only customization menu |
| **Lean zip** | Same download-on-demand models as 1.2.5/1.2.6 |

## Ship checklist

```bash
set -a && source .env.signing && set +a
export MACWISPR_VERSION=1.2.7
./scripts/build-app.sh
./scripts/build-dmg.sh
SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update 2>/dev/null | head -1)"
"$SIGN_UPDATE" dist/MacWispr-1.2.7-macos-arm64.zip
./scripts/ci-update-appcast.sh 1.2.7 "<edSignature>" <length>
git tag -a v1.2.7 -m "MacWispr 1.2.7"
# gh release + wrangler pages deploy website
```

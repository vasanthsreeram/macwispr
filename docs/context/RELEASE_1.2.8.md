# MacWispr 1.2.8 (stable)

**Version:** 1.2.8
**Channel:** production (`main` + Sparkle appcast + GitHub Latest)
**Previous:** 1.2.7 (GitHub Latest, 2026-07-20)

## What's new

| Change | Notes |
|--------|--------|
| **Live waveform HUD** | "Listening" chrome replaced by a moving RMS-driven waveform (26 bars, 24 Hz); disappears once live words start dictating |
| **Mid-recording mic switch** | Capture rebinds (device + format + tap) when the system default input changes or the engine config changes — fixes silent/quiet audio after switching to iPhone Continuity / Bluetooth mics |

Shipped in commit `6c5358c` (`Sources/AudioRecorder.swift`, `Sources/ListeningHUDController.swift`).

## Ship checklist

```bash
set -a && source .env.signing && set +a
export MACWISPR_VERSION=1.2.8
./scripts/build-app.sh
./scripts/build-dmg.sh

SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update 2>/dev/null | head -1)"
"$SIGN_UPDATE" dist/MacWispr-1.2.8-macos-arm64.zip
./scripts/ci-update-appcast.sh 1.2.8 "<edSignature>" <length>
./scripts/release.sh v1.2.8
# deploy website/appcast.xml to fuckwisprflow.com
```

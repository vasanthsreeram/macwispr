# MacWispr 1.2.9 (stable)

**Version:** 1.2.9  
**Channel:** production (`main` + Sparkle appcast + GitHub Latest)  
**Base:** 1.2.7 dictation path (no mid-recording mic rebind from 1.2.8)

## What's new

| Change | Notes |
|--------|--------|
| **Public leaderboard** | Opt-in sidebar Leaderboard — rank by words dictated |
| **Public name** | Optional competitive name, or stay anonymous animal |
| **Listening waveform** | Mic-level bars while listening (metering only) |
| **No Keychain for board** | Participant token in app prefs — no system password prompts |
| **Board API** | Stats never decrease on empty/partial sync |

## Intentionally not included

- 1.2.8 mid-recording AVAudioEngine rebind (caused stuck dictation)
- Polish LLM default remains **off**

## Ship

```bash
git tag -a v1.2.9 -m "MacWispr 1.2.9"
git push origin v1.2.9
# Release workflow: sign, notarize, GitHub Latest, appcast
```

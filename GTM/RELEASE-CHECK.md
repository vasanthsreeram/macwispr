# Release & site check (prep run)

**Checked:** 1.2.3 packaging session  
**Public latest (until 1.2.3 ships):** **v1.2.2** — https://github.com/vasanthsreeram/macwispr/releases/tag/v1.2.2  
**Next ship:** **v1.2.3** from **`main` only** — scope [docs/context/RELEASE_1.2.3.md](../docs/context/RELEASE_1.2.3.md)  
**Not in 1.2.3:** `feat/native-lfm-polish` (LFM fine-tuned polish)

## Assets on GitHub (current public)

| Asset | Size | Notes |
|-------|------|--------|
| `MacWispr-macos-arm64.dmg` | ~103 MB | ✅ latest alias target |
| `MacWispr-1.2.2-macos-arm64.dmg` | same | versioned |
| `MacWispr-1.2.2-macos-arm64.zip` | ~102 MB | zip alternate |

`/releases/latest/download/MacWispr-macos-arm64.dmg` → **HTTP 302** → v1.2.2 DMG until v1.2.3 is published ✅  

## Release notes quality

Good enough for launch:

- Install steps present  
- Gatekeeper note present  
- Site links present  
- What’s new listed  

### Optional polish (not blocking)

- Lead the release body with the **launch hook** (&lt;0.5s, free, local) above telemetry bullets — social visitors scan for value first  
- Pin a short “Launch week” section once PH is live  

Draft launch-first blurb (for future edit — do not change without ask):

```
## Why this exists
Free on-device dictation for Mac. Under 0.5s. No account for local ASR. MIT.
Site: https://fuckwisprflow.com
```

## Site

| Check | Result |
|-------|--------|
| https://fuckwisprflow.com | 200 |
| OG image | 200, ~70KB PNG |
| Download CTA → GitHub latest DMG | used in site HTML |

## Local tree note

`dist/` may hold a 1.2.3 Developer ID build while notary runs. **Do not point marketing at 1.2.3 until** GitHub release + appcast are updated. Never cut 1.2.3 from `feat/native-lfm-polish`.

## Verdict

**v1.2.2** is still the public download until 1.2.3 is published. **v1.2.3** = Parakeet + Qwen + model UX from `main` (see RELEASE_1.2.3.md).

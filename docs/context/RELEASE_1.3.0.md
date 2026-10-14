# MacWispr 1.3.0 — Parakeet Redux only

**Shipped:** 2026-10-14 · Developer ID signed, notarized and stapled (app + DMG).
**Downloads:** https://macwispr.lintlabs.org/download/MacWispr-1.3.0-macos-arm64.dmg and
https://fuckwisprflow.com/download/MacWispr-1.3.0-macos-arm64.dmg (served from R2 bucket
`macwispr-downloads` by `functions/download/[[path]].js`; Pages caps static files at 25 MiB).

## Product
- One speech model: Moondream `parakeet-redux` (ternary Parakeet TDT v3, 178 MB) on the Photon runtime.
  No model picker, no cloud providers, no polish LLM. Any saved choice from older builds migrates
  to Redux (`ModelCatalog.migrate`).
- Main window: Home · History · Settings (was 9 panes). Settings: speech status, permissions,
  shortcut / mode / mic / sounds, and an Advanced disclosure.
- New icon from `scripts/brand/make_logo.py` (`--repo` regenerates every app, docs and site asset).

## Runtime setup
- The app bundles `uv` 0.13.1 (`Contents/Helpers/uv`, pinned + SHA-256 checked in `build-app.sh`).
  First launch creates a uv-managed CPython 3.12 venv under
  `~/Library/Application Support/MacWispr/photon` and installs `moondream==2.6.1 kestrel==0.9.1`.
  No Homebrew/system Python needed. Fallback: system python3 + pip (`PhotonSetupPlan`).
- Weights download to the Hugging Face cache; once present the sidecar runs with `HF_HUB_OFFLINE=1`.
- The sidecar restarts itself if it died; long audio is chunked like Parakeet v3.

## Accessibility
- Text goes on the pasteboard first, then ⌘V / type-out only when `AXIsProcessTrusted() ||
  CGPreflightPostEventAccess()` and Secure Event Input is off (`InsertionDecision`).
- "Turn On…" prompts and opens Privacy → Accessibility; a second click resets this app's own
  stale TCC entry (`tccutil reset Accessibility <bundle id>`) and prompts again.

## Checks
- `swift test` (ModelCatalog / PhotonSetupPlan / InsertionDecision tests).
- `bench/redux_english_wer.py dist/MacWispr.app/Contents/MacOS/MacWispr` — drives
  `MacWispr --transcribe-file` (real TranscriptionEngine → PhotonSidecar). 1.3.0: LibriSpeech
  test-clean sample WER 3.2%, overall 3.5%.
- `MacWispr --render-ui <dir>` renders Home/Settings/History/onboarding/menu offscreen.
- `MACWISPR_SELFTEST_NO_INJECT=1 MacWispr --self-test` skips the global ⌥Space injection.

## Not done
- Sparkle appcast still lists 1.2.10 (unchanged on purpose); GitHub release not created.

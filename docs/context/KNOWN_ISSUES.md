# Known issues & troubleshooting

## ⌥Space does nothing

**Code path was verified** with `--self-test` (synthetic handler + CGEvent inject) when Accessibility is granted.

The hotkey uses three layers: **CGEvent tap** (swallows Space), **Carbon RegisterEventHotKey**, and NSEvent monitors as backup. UI “armed” means tap **or** Carbon is live — monitors alone no longer report success (they install without Accessibility but never fire).

Checklist:

1. Click menu bar waveform → look for **“⌥Space armed”** vs **“needs Accessibility”** / **“not registered”**.
2. Click **Fix** (or Settings → Repair Hotkey).
3. System Settings → Privacy & Security → **Accessibility** → enable **MacWispr**.
4. After reinstall/codesign/update on **ad-hoc** builds, **remove and re-add** the app (TCC binds to the binary hash). **Developer ID** builds keep the grant — see [SIGNING.md](./SIGNING.md).
5. Also check **Input Monitoring** if present.
6. Model / cloud provider must be ready (status green **Ready**); otherwise you hear a soft “not ready” chime.
7. If dictation “works” but nothing is typed: text may only be on the clipboard — grant Accessibility so paste can run (failure banner / warning in 1.2.x).
8. Fallback: use **Hold to Speak** or **Start Listening** in the panel (no global hotkey needed).

```bash
/Applications/MacWispr.app/Contents/MacOS/MacWispr --self-test
```

## Parakeet: MultiArray shape (1×128×200) vs (1×128×3000)

**Symptom:** Banner/error
`Transcription failed: MultiArray shape (1 x 128 x 200) does not match the shape (1 x 128 x 3000) specified in the model description`.

**Cause:** Hugging Face re-exported the Parakeet Core ML encoder as a **fixed** mel shape `[1, 128, 3000]` (~30 s). Older speech-swift padding still chose the nearest *enumerated* size (100 / 200 / …) for short dictation, which Core ML rejects. The INT4 HF repo was also retired.

**Fix (app-side, macOS 14 pin):**
- Both Parakeet picker values load **INT8** (`aufklarer/Parakeet-TDT-v3-CoreML-INT8`).
- `TranscriptionEngine.prepareParakeetSamples` zero-pads short PCM so mel frames land in `(2000, 3000]` (pad target 3000) and trims longer audio to the encoder max.
- Warm-up uses the same padding (library `warmUp()` still uses 1 s silence and would fail).

If you still see INT4 download failures, delete the stale cache and re-pick Parakeet in Settings:

```bash
rm -rf ~/Library/Caches/qwen3-speech/models/aufklarer/Parakeet-TDT-v3-CoreML-INT4
```

Upstream speech-swift main now discovers shapes and defaults to `…-INT8-30s`, but requires **macOS 15** — MacWispr stays on a macOS 14-compatible pin until a platform bump.

## Floating HUD looks wrong / still has long text

Current design is **minimal**: glowing phase dot + elapsed digits only (no “Listening…” / “release to…” copy).

- File: `Sources/ListeningHUDController.swift`
- Toggle: Settings / onboarding **Listening HUD**
- If you still see old copy, quit MacWispr fully and reinstall from a rebuild (`./scripts/install.sh`)

## Sounds too loud or silent

- Volumes are intentionally **soft** (`FeedbackSounds` ~0.22–0.32). Do not “fix” by raising near 1.0.
- If chimes are silent: menu bar may show **output muted**; unmute Mac sound or disable mute detection banner by fixing output volume.
- Settings → sound feedback toggle.

## Menu bar icon missing

- Use current build with `StatusBarController` (not MenuBarExtra-only).
- Look for SF Symbol **waveform.circle**, not Dock.
- Confirm process: `pgrep -x MacWispr`.

## App quits immediately / metallib error

```
MLX error: Failed to load the default metallib
```

**Most common (dev machines):** only **Command Line Tools** are installed. Full **Xcode.app** is required — CLT cannot provide the `metal` compiler, so no metallib is produced and MLX fails at runtime even though `swift build` succeeded.

```bash
./scripts/preflight-xcode.sh
# or:
xcrun -sdk macosx metal --version
# If that fails:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
xcodebuild -downloadComponent MetalToolchain   # once if needed
```

For a packaged app, also rebuild so `mlx.metallib` is embedded:

```bash
./scripts/install.sh
```

## Space still types into the focused field

Event tap not active (Accessibility). Monitors can still start dictation but cannot suppress Space.

## Dashboard blank / doesn’t open

Use menu **Open Dashboard** (AppKit window). Prefer closing popover first (current code does). If stuck, `open -a MacWispr --args --open-dashboard`.

## Telemetry not appearing in PostHog

1. User must **opt in** (Settings → Privacy → Share anonymous usage data). Default is off.
2. Build must embed a real project `phc_…` key (not a TODO placeholder) — see `Sources/Telemetry.swift`.
3. Events are fail-silent; check PostHog project US cloud, not a different region/project.
4. Never expect transcript content in analytics (by design).

## Gatekeeper

Unsigned local builds: right-click → Open, or:

```bash
xattr -dr com.apple.quarantine /Applications/MacWispr.app
```

Developer ID signed builds (Team `UTSTY3J6NS`) should open more cleanly. Notarization requires Keychain profile `MacWispr-notary` — if missing, builds still sign but skip staple (see [SIGNING.md](./SIGNING.md)).

## Notarytool profile missing

```
Error: No Keychain password item found for profile: MacWispr-notary
```

Re-run:

```bash
xcrun notarytool store-credentials "MacWispr-notary" \
  --apple-id "you@example.com" \
  --team-id "UTSTY3J6NS" \
  --password "app-specific-password"
```

Or build/test with `MACWISPR_SKIP_NOTARIZE=1`.

## Release zip vs source

GitHub release artifacts may lag behind local experiments. Prefer `./scripts/install.sh` for day-to-day testing. Sparkle users only get what is in the published zip **and** live appcast on fuckwisprflow.com.

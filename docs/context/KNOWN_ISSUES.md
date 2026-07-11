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
6. Model / cloud provider must be ready (status green **Ready**); otherwise you hear a low “not ready” sound.  
7. If dictation “works” but nothing is typed: text may only be on the clipboard — grant Accessibility so paste can run (1.2.1 shows a warning for this).  
8. Fallback: use **Hold to Speak** or **Start Listening** in the panel (no global hotkey needed).

```bash
/Applications/MacWispr.app/Contents/MacOS/MacWispr --self-test
```

## Menu bar icon missing

- Use current build with `StatusBarController` (not MenuBarExtra-only).  
- Look for SF Symbol **waveform.circle**, not Dock.  
- Confirm process: `pgrep -x MacWispr`.  

## App quits immediately / metallib error

```
MLX error: Failed to load the default metallib
```

Rebuild with packaging that includes metallib:

```bash
xcodebuild -downloadComponent MetalToolchain   # once if needed
./scripts/install.sh
```

## Space still types into the focused field

Event tap not active (Accessibility). Monitors can still start dictation but cannot suppress Space.

## Dashboard blank / doesn’t open

Use menu **Open Dashboard** (AppKit window). Prefer closing popover first (current code does). If stuck, `open -a MacWispr --args --open-dashboard`.

## Gatekeeper

Unsigned local builds: right-click → Open, or:

```bash
xattr -dr com.apple.quarantine /Applications/MacWispr.app
```

## Release zip vs source

GitHub release artifacts may lag behind `main` (e.g. metallib packaging). Prefer `./scripts/install.sh` until a new release is published.

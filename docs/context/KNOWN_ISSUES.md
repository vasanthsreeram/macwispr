# Known issues & troubleshooting

## ⌥Space does nothing

**Code path was verified** with `--self-test` (synthetic handler + CGEvent inject) when Accessibility is granted.

Checklist:

1. Click menu bar waveform → look for **“⌥Space armed”** vs **“needs Accessibility”**.  
2. System Settings → Privacy & Security → **Accessibility** → enable **MacWispr**.  
3. After reinstall/codesign, **remove and re-add** the app (TCC binds to the binary).  
4. Also check **Input Monitoring** if present.  
5. Quit MacWispr completely; reopen `/Applications/MacWispr.app`.  
6. Model must be loaded (status green **Ready**); startRecording no-ops if not.  
7. Fallback: use **Hold to Speak** or **Start Listening** in the panel (no global hotkey needed).

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

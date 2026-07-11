#!/usr/bin/env bash
# Tag + publish a GitHub Release with zip + DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 v1.2.1 [--rebuild]" >&2
  exit 1
fi
VERSION="${VERSION#v}"
TAG="v$VERSION"
export MACWISPR_VERSION="$VERSION"

if [[ "${2:-}" == "--rebuild" || ! -d "$ROOT/dist/MacWispr.app" ]]; then
  "$ROOT/scripts/build-app.sh"
fi

ZIP="$ROOT/dist/MacWispr-${VERSION}-macos-arm64.zip"
DMG="$ROOT/dist/MacWispr-${VERSION}-macos-arm64.dmg"
DMG_STABLE="$ROOT/dist/MacWispr-macos-arm64.dmg"

if [[ ! -f "$ZIP" && -d "$ROOT/dist/MacWispr.app" ]]; then
  # Re-zip if only .app exists
  (
    cd "$ROOT/dist"
    ditto -c -k --sequesterRsrc --keepParent MacWispr.app "MacWispr-${VERSION}-macos-arm64.zip"
  )
fi

"$ROOT/scripts/build-dmg.sh"

if [[ ! -f "$ZIP" ]]; then
  echo "error: missing $ZIP" >&2
  exit 1
fi
if [[ ! -f "$DMG" || ! -f "$DMG_STABLE" ]]; then
  echo "error: missing DMG assets" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI required to publish. Assets ready under dist/" >&2
  exit 1
fi

# Honest signing status for release notes
SIGN_NOTE="Unsigned / ad-hoc build — right-click → Open the first time if Gatekeeper prompts. After each update, re-check **Accessibility** (ad-hoc TCC does not survive rebuilds)."
if codesign -dv --verbose=4 "$ROOT/dist/MacWispr.app" 2>&1 | grep -q "Developer ID Application"; then
  SIGN_NOTE="**Developer ID** signed (and notarized if credentials were configured). Accessibility grants persist across updates of this app."
fi

NOTES=$(cat <<EOF
## MacWispr ${TAG}

Voice dictation for macOS (Apple Silicon) — on-device by default, optional BYOK cloud.

### Easy install (DMG)
1. Download **MacWispr-macos-arm64.dmg** (or the versioned DMG below)
2. Open the DMG → drag **MacWispr** into **Applications**
3. Open it, grant **Microphone** + **Accessibility**
4. Hold **⌥Space**, speak, release

> ${SIGN_NOTE}

Direct download:
https://github.com/vasanthsreeram/macwispr/releases/latest/download/MacWispr-macos-arm64.dmg

### What's new in 1.2.1
- **Hotkey reliability** — Carbon \`RegisterEventHotKey\` alongside the CGEvent tap (detection can survive a dropped Accessibility grant)
- **Honest “armed” status** — menu bar only shows ⌥Space ready when tap or Carbon is live (not monitors-only)
- **Live re-arm** — polls Accessibility and re-registers without relaunch; Fix / Repair Hotkey in UI
- **Paste without AX is no longer silent** — transcription is copied; UI warns that Accessibility is required to auto-paste
- **Mic permission** requested on launch; empty-audio feedback if capture fails
- **Release tooling** for Developer ID + hardened runtime + notarization (\`docs/context/SIGNING.md\`) — durable TCC is the real end-state for “shortcut died after update”

### Site
- https://fuckwisprflow.com/
- https://vasanthsreeram.github.io/macwispr/

### Build from source

    git clone https://github.com/vasanthsreeram/macwispr.git
    cd macwispr
    ./scripts/install.sh
EOF
)

if [[ -n "$(git status --porcelain)" ]]; then
  echo "warning: working tree dirty — publishing assets only (skipping tag push if already tagged)" >&2
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  if [[ -z "$(git status --porcelain)" ]]; then
    git tag -a "$TAG" -m "MacWispr $TAG"
    git push origin "$TAG"
  else
    echo "error: cannot create tag with dirty tree" >&2
    exit 1
  fi
else
  git push origin "$TAG" 2>/dev/null || true
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ZIP" "$DMG" "$DMG_STABLE" --clobber
  gh release edit "$TAG" --title "MacWispr $TAG" --notes "$NOTES" --latest
else
  gh release create "$TAG" "$ZIP" "$DMG" "$DMG_STABLE" --title "MacWispr $TAG" --notes "$NOTES" --latest
fi

echo "✓ Published $TAG"
echo "  Zip:  $ZIP"
echo "  DMG:  $DMG"
echo "  Direct: https://github.com/vasanthsreeram/macwispr/releases/latest/download/MacWispr-macos-arm64.dmg"

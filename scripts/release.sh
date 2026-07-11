#!/usr/bin/env bash
# Tag + publish a GitHub Release with zip + DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 v1.2.3 [--rebuild]" >&2
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

### What's new in 1.2.3
- **Parakeet v3 (Core ML)** — on-device **En + EU** model via Neural Engine (alongside Qwen 0.6B / 1.7B for En + Asian)
- **Model quick-switch** — dashboard chip to change local model without digging through Settings
- **Clearer model labels** — language coverage first (En+Asian / En+EU), not jargon
- **Free GPU memory on model switch** — switching sizes or local ↔ cloud unloads MLX weights and clears Metal cache so RAM actually drops (#12)
- **Parakeet short-clip fix** — correct MultiArray shape on brief dictations
- **RAM-aware defaults** — sensible Qwen size pick for machine memory


### Site
- https://fuckwisprflow.com/
- https://vasanthsreeram.github.io/macwispr/

### Build from source

    git clone https://github.com/vasanthsreeram/macwispr.git
    cd macwispr
    ./scripts/install.sh
EOF
)

# Tag the current HEAD commit even if the worktree is dirty (dist/ and local
# site edits often leave the tree unclean; the tag points at HEAD, not the index).
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "warning: dirty worktree — tagging HEAD $(git rev-parse --short HEAD) only" >&2
  fi
  git tag -a "$TAG" -m "MacWispr $TAG"
  git push origin "$TAG"
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

#!/usr/bin/env bash
# Upload release assets to an existing git tag (GitHub Actions).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?usage: ci-publish-github-release.sh vX.Y.Z}"
VERSION="${TAG#v}"
export MACWISPR_VERSION="$VERSION"

DIST="$ROOT/dist"
ZIP="$DIST/MacWispr-${VERSION}-macos-arm64.zip"
DMG="$DIST/MacWispr-${VERSION}-macos-arm64.dmg"
DMG_STABLE="$DIST/MacWispr-macos-arm64.dmg"
NOTES_FILE="${2:-}"

for f in "$ZIP" "$DMG" "$DMG_STABLE"; do
  if [[ ! -f "$f" ]]; then
    echo "error: missing $f" >&2
    exit 1
  fi
done

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI is required" >&2
  exit 1
fi

SIGN_NOTE="**Developer ID** signed (and notarized when Apple credentials are configured)."
if ! codesign -dv --verbose=4 "$DIST/MacWispr.app" 2>&1 | grep -q "Developer ID Application"; then
  SIGN_NOTE="Unsigned / ad-hoc build."
fi

if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
  NOTES="$(cat "$NOTES_FILE")"
else
  NOTES="$(cat <<EOF
## MacWispr ${TAG}

${SIGN_NOTE}

### Install
1. Download **MacWispr-macos-arm64.dmg**
2. Drag **MacWispr** into **Applications**
3. Grant **Microphone** + **Accessibility**
4. Hold **⌥Space** to dictate

https://github.com/vasanthsreeram/macwispr/releases/latest/download/MacWispr-macos-arm64.dmg
EOF
)"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ZIP" "$DMG" "$DMG_STABLE" --clobber
  gh release edit "$TAG" --title "MacWispr $TAG" --notes "$NOTES" --latest
else
  gh release create "$TAG" "$ZIP" "$DMG" "$DMG_STABLE" \
    --title "MacWispr $TAG" \
    --notes "$NOTES" \
    --latest
fi

echo "✓ Published GitHub Release $TAG"
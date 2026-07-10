#!/usr/bin/env bash
# Tag + publish a GitHub Release with the packaged .app zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 v1.1.0" >&2
  exit 1
fi
VERSION="${VERSION#v}"
TAG="v$VERSION"
export MACWISPR_VERSION="$VERSION"

"$ROOT/scripts/build-app.sh"
ZIP="$ROOT/dist/MacWispr-${VERSION}-macos-arm64.zip"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI required to publish. Zip ready at: $ZIP" >&2
  exit 1
fi

NOTES="$(cat <<EOF
## MacWispr $TAG

On-device voice dictation for macOS (Apple Silicon).

### Easy install
1. Download **MacWispr-${VERSION}-macos-arm64.zip**
2. Unzip and drag **MacWispr.app** to Applications
3. Open it, grant **Microphone** + **Accessibility**
4. Hold **⌥Space**, speak, release

> Unsigned local build — right-click → Open the first time if Gatekeeper prompts.

### What's new
- Renamed to **MacWispr**
- Weekly **word count** + **time saved** dashboard
- Persistent history + menu-bar weekly stats
- One-command packaging via \`scripts/build-app.sh\`

### Build from source
\`\`\`bash
git clone https://github.com/vasanthsreeram/macwispr.git
cd macwispr
./scripts/install.sh
\`\`\`
EOF
)"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists"
else
  git tag -a "$TAG" -m "MacWispr $TAG"
  git push origin "$TAG"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ZIP" --clobber
  gh release edit "$TAG" --title "MacWispr $TAG" --notes "$NOTES"
else
  gh release create "$TAG" "$ZIP" --title "MacWispr $TAG" --notes "$NOTES"
fi

echo "✓ Published $TAG"

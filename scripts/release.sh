#!/usr/bin/env bash
# Tag + publish a GitHub Release with the packaged .app zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 v1.2.0" >&2
  exit 1
fi
VERSION="${VERSION#v}"
TAG="v$VERSION"
export MACWISPR_VERSION="$VERSION"

# Skip rebuild if zip already present (pass --rebuild to force)
if [[ "${2:-}" == "--rebuild" || ! -f "$ROOT/dist/MacWispr-${VERSION}-macos-arm64.zip" ]]; then
  "$ROOT/scripts/build-app.sh"
fi
ZIP="$ROOT/dist/MacWispr-${VERSION}-macos-arm64.zip"
if [[ ! -f "$ZIP" ]]; then
  echo "error: missing $ZIP" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI required to publish. Zip ready at: $ZIP" >&2
  exit 1
fi

# Unquoted EOF expands VERSION/TAG; avoid shell backticks inside notes.
NOTES=$(cat <<EOF
## MacWispr ${TAG}

Voice dictation for macOS (Apple Silicon) — on-device by default, optional BYOK cloud.

### Easy install
1. Download **MacWispr-${VERSION}-macos-arm64.zip**
2. Unzip and drag **MacWispr.app** to Applications
3. Open it, grant **Microphone** + **Accessibility**
4. Hold **⌥Space**, speak, release

> Unsigned local build — right-click → Open the first time if Gatekeeper prompts.

### What's new in 1.2.0
- **BYOK speech-to-text** — bring your own **OpenAI** (gpt-4o-mini-transcribe) or **ElevenLabs** (scribe_v2) API key
- Keys stored only in the **macOS Keychain** (never in UserDefaults)
- **Transcript polish** — Off · local Qwen chat LLM · or OpenAI
- **Local models** — Qwen3-ASR **0.6B / 1.7B 8-bit** (selectable in Settings)
- **Custom vocabulary** for local + cloud providers
- Default insert mode **Both** (clipboard + type into active app)
- End sound plays **after transcription finishes**, not on mic release
- Metallib packaging fix retained for reliable MLX launch

### Site
- https://vasanthsreeram.github.io/macwispr/

### Build from source

    git clone https://github.com/vasanthsreeram/macwispr.git
    cd macwispr
    ./scripts/install.sh
EOF
)

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree dirty — commit changes before releasing" >&2
  git status --porcelain >&2
  exit 1
fi

git push origin HEAD:main 2>/dev/null || git push origin HEAD

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists (local)"
else
  git tag -a "$TAG" -m "MacWispr $TAG"
fi
git push origin "$TAG" 2>/dev/null || git push origin "refs/tags/$TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ZIP" --clobber
  gh release edit "$TAG" --title "MacWispr $TAG" --notes "$NOTES" --latest
else
  gh release create "$TAG" "$ZIP" --title "MacWispr $TAG" --notes "$NOTES" --latest
fi

echo "✓ Published $TAG"
echo "  Asset: $ZIP"
echo "  https://github.com/vasanthsreeram/macwispr/releases/tag/$TAG"

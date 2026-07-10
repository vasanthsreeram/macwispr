#!/usr/bin/env bash
# One-command local install for MacWispr (Apple Silicon, macOS 14+).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "MacWispr only runs on macOS." >&2
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "MacWispr requires Apple Silicon (arm64)." >&2
  exit 1
fi

echo "==> Building MacWispr.app..."
"$ROOT/scripts/build-app.sh"

APP="$ROOT/dist/MacWispr.app"
DEST="/Applications/MacWispr.app"

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo ""
echo "✓ Installed MacWispr to /Applications"
echo ""
echo "First launch:"
echo "  open -a MacWispr"
echo ""
echo "Then grant Microphone + Accessibility when prompted."
echo "Hold ⌥Space to dictate."

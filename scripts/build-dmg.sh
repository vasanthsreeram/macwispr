#!/usr/bin/env bash
# Package MacWispr.app into a polished drag-to-Applications .dmg
# (large icons, custom background, fixed window layout via dmgbuild).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${MACWISPR_VERSION:-1.2.4-beta.1}"
APP="${1:-$ROOT/dist/MacWispr.app}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
DMG_VERSIONED="$DIST_DIR/MacWispr-${VERSION}-macos-arm64.dmg"
DMG_STABLE="$DIST_DIR/MacWispr-macos-arm64.dmg"
VOLNAME="MacWispr ${VERSION}"
BG_SRC="$ROOT/scripts/dmg-assets/background.png"
BG_GEN="$ROOT/scripts/dmg-assets/generate_background.py"
SETTINGS="$ROOT/scripts/dmg-assets/dmgbuild_settings.py"

# Prefer project venv (has dmgbuild), then PATH.
PYTHON="${MACWISPR_PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
  if [[ -x "$HOME/.cache/macwispr-minicpm-bench/.venv/bin/python3" ]]; then
    PYTHON="$HOME/.cache/macwispr-minicpm-bench/.venv/bin/python3"
  else
    PYTHON="python3"
  fi
fi

if [[ ! -d "$APP" ]]; then
  echo "error: app not found at $APP — run scripts/build-app.sh first" >&2
  exit 1
fi

if ! "$PYTHON" -c "import dmgbuild" 2>/dev/null; then
  echo "error: dmgbuild not installed for $PYTHON" >&2
  echo "  $PYTHON -m pip install dmgbuild" >&2
  exit 1
fi

if [[ ! -f "$BG_SRC" ]] || [[ "${DMG_REGEN_BG:-}" == "1" ]]; then
  echo "==> Generating DMG background..."
  "$PYTHON" "$BG_GEN"
fi
if [[ ! -f "$BG_SRC" ]]; then
  echo "error: missing $BG_SRC" >&2
  exit 1
fi

# Detach leftover volume
if [[ -d "/Volumes/${VOLNAME}" ]]; then
  hdiutil detach "/Volumes/${VOLNAME}" -force 2>/dev/null || true
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_VERSIONED" "$DMG_STABLE"

export MACWISPR_VERSION="$VERSION"
export MACWISPR_DMG_APP="$APP"
export MACWISPR_DMG_BG="$BG_SRC"

echo "==> Building DMG with dmgbuild (icon layout + background)..."
echo "    volume: $VOLNAME"
echo "    app:    $APP"
"$PYTHON" -m dmgbuild \
  -s "$SETTINGS" \
  "$VOLNAME" \
  "$DMG_VERSIONED"

cp "$DMG_VERSIONED" "$DMG_STABLE"

echo ""
echo "✓ DMG:     $DMG_VERSIONED"
echo "✓ Stable:  $DMG_STABLE"
echo "  Size:    $(du -h "$DMG_VERSIONED" | awk '{print $1}')"
echo "  Open:    open \"$DMG_VERSIONED\""

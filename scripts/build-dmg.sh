#!/usr/bin/env bash
# Package MacWispr.app into a drag-to-Applications .dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${MACWISPR_VERSION:-1.2.0}"
APP="${1:-$ROOT/dist/MacWispr.app}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
DMG_VERSIONED="$DIST_DIR/MacWispr-${VERSION}-macos-arm64.dmg"
# Stable name so /releases/latest/download/MacWispr-macos-arm64.dmg always works
DMG_STABLE="$DIST_DIR/MacWispr-macos-arm64.dmg"
RW_DMG="$DIST_DIR/.MacWispr-rw.dmg"
VOLNAME="MacWispr ${VERSION}"

if [[ ! -d "$APP" ]]; then
  echo "error: app not found at $APP — run scripts/build-app.sh first" >&2
  exit 1
fi

APP_BYTES=$(du -sk "$APP" | awk '{print $1}')
# HFS+ image size in MB: app + Applications link + padding
SIZE_MB=$(( APP_BYTES / 1024 + 80 ))
if (( SIZE_MB < 200 )); then SIZE_MB=200; fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_VERSIONED" "$DMG_STABLE" "$RW_DMG"

# Detach any leftover volume with the same name
if [[ -d "/Volumes/${VOLNAME}" ]]; then
  hdiutil detach "/Volumes/${VOLNAME}" -force 2>/dev/null || true
fi

echo "==> Creating ${SIZE_MB}MB RW image..."
hdiutil create \
  -size "${SIZE_MB}m" \
  -fs HFS+ \
  -volname "$VOLNAME" \
  -ov \
  "$RW_DMG"

echo "==> Mounting..."
MOUNT_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")
MOUNT_DIR=$(echo "$MOUNT_OUT" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
  # Fallback parse
  MOUNT_DIR="/Volumes/${VOLNAME}"
fi
if [[ ! -d "$MOUNT_DIR" ]]; then
  echo "error: could not mount DMG (got: $MOUNT_OUT)" >&2
  exit 1
fi

cleanup() {
  if [[ -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
  fi
  rm -f "$RW_DMG"
}
trap cleanup EXIT

echo "==> Copying app to $MOUNT_DIR ..."
# ditto preserves resource forks / code signature better than cp -R
ditto "$APP" "$MOUNT_DIR/MacWispr.app"
ln -s /Applications "$MOUNT_DIR/Applications"

cat > "$MOUNT_DIR/README.txt" <<EOF
MacWispr ${VERSION}
==================

1. Drag MacWispr into Applications
2. Open MacWispr (right-click → Open the first time if macOS blocks it)
3. Grant Microphone + Accessibility
4. Hold Option+Space, speak, release

Unsigned build — if Gatekeeper complains:
  xattr -dr com.apple.quarantine /Applications/MacWispr.app

https://github.com/vasanthsreeram/macwispr
EOF

sync
echo "==> Detaching..."
hdiutil detach "$MOUNT_DIR"
MOUNT_DIR=""

echo "==> Compressing to UDZO..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_VERSIONED"
rm -f "$RW_DMG"
cp "$DMG_VERSIONED" "$DMG_STABLE"
trap - EXIT

echo ""
echo "✓ DMG:     $DMG_VERSIONED"
echo "✓ Stable:  $DMG_STABLE"
echo "  Size:    $(du -h "$DMG_VERSIONED" | awk '{print $1}')"

#!/usr/bin/env bash
# Build a double-clickable MacWispr.app (unsigned) from the Swift package.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacWispr"
VERSION="${MACWISPR_VERSION:-1.1.0}"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
CONFIG="${CONFIG:-release}"
BIN="$BUILD_DIR/$CONFIG/$APP_NAME"
APP="$DIST_DIR/$APP_NAME.app"

echo "==> Building $APP_NAME ($CONFIG)..."
swift build -c "$CONFIG" --product MacWispr

if [[ ! -x "$BIN" ]]; then
  # SPM sometimes nests the binary under apple/Products
  BIN="$(find "$BUILD_DIR" -type f -name MacWispr -perm -111 | head -n1)"
fi
if [[ -z "${BIN:-}" || ! -x "$BIN" ]]; then
  echo "error: could not find MacWispr binary after build" >&2
  exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/MacWispr"
chmod +x "$APP/Contents/MacOS/MacWispr"

# Info.plist (inject version if present)
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
else
  cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
fi

# App icon (.icns from PNG if available)
ICON_SRC="$ROOT/docs/assets/logo.png"
if [[ -f "$ICON_SRC" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 64 128 256 512; do
    sips -z "$s" "$s" "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    double=$((s * 2))
    sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
elif [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.png"
fi

# Ad-hoc sign so macOS Gatekeeper is slightly happier on local builds
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

# Zip for GitHub Releases
mkdir -p "$DIST_DIR"
ZIP="$DIST_DIR/${APP_NAME}-${VERSION}-macos-arm64.zip"
rm -f "$ZIP"
(
  cd "$DIST_DIR"
  ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$ZIP")"
)

echo ""
echo "✓ App:  $APP"
echo "✓ Zip:  $ZIP"
echo ""
echo "Open with:  open \"$APP\""
echo "Or install:  cp -R \"$APP\" /Applications/"

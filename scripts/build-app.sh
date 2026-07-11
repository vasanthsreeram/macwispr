#!/usr/bin/env bash
# Build a double-clickable MacWispr.app from the Swift package.
#
# Signing:
#   default                          → ad-hoc (TCC Accessibility resets on each update)
#   MACWISPR_SIGN_IDENTITY=...       → Developer ID + hardened runtime
#   + MACWISPR_NOTARY_PROFILE=...    → notarize + staple
# See docs/context/SIGNING.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacWispr"
VERSION="${MACWISPR_VERSION:-1.2.1}"
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

# MLX loads GPU shaders from mlx.metallib next to the executable (or via a
# SwiftPM resource bundle). The GitHub release crash was:
#   MLX error: Failed to load the default metallib. library not found
# Build it from the mlx-swift metal kernels and ship it inside the .app.
echo "==> Building MLX Metal library (mlx.metallib)..."
MLX_SWIFT_DIR="$BUILD_DIR/checkouts/mlx-swift"
if [[ -d "$MLX_SWIFT_DIR/.git" || -f "$MLX_SWIFT_DIR/.git" ]]; then
  # mlx-swift vendors mlx via git submodules; SPM may leave them empty.
  git -C "$MLX_SWIFT_DIR" submodule update --init --recursive
fi
METALLIB_SCRIPT="$BUILD_DIR/checkouts/speech-swift/scripts/build_mlx_metallib.sh"
if [[ ! -x "$METALLIB_SCRIPT" && ! -f "$METALLIB_SCRIPT" ]]; then
  echo "error: missing $METALLIB_SCRIPT (run swift build first)" >&2
  exit 1
fi
BUILD_DIR="$BUILD_DIR" bash "$METALLIB_SCRIPT" "$CONFIG"

METALLIB=""
for candidate in \
  "$BUILD_DIR/$CONFIG/mlx.metallib" \
  "$(dirname "$BIN")/mlx.metallib"
do
  if [[ -f "$candidate" ]]; then
    METALLIB="$candidate"
    break
  fi
done
# Fallback: search under .build (SPM layout varies)
if [[ -z "$METALLIB" ]]; then
  METALLIB="$(find "$BUILD_DIR" -type f -name 'mlx.metallib' 2>/dev/null | head -n1 || true)"
fi
if [[ -z "$METALLIB" || ! -f "$METALLIB" ]]; then
  echo "error: mlx.metallib not found after metal build" >&2
  echo "hint: install Metal Toolchain: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/MacWispr"
chmod +x "$APP/Contents/MacOS/MacWispr"
# Colocated with the binary — first path MLX searches at runtime.
cp "$METALLIB" "$APP/Contents/MacOS/mlx.metallib"
# Also ship as default.metallib for loaders that use METAL_PATH.
cp "$METALLIB" "$APP/Contents/MacOS/default.metallib"
cp "$METALLIB" "$APP/Contents/Resources/default.metallib"

# Info.plist (inject version if present)
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
else
  cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
fi

# App icon + bundled logo for About / UI (.icns from PNG)
ICON_SRC="$ROOT/docs/assets/logo.png"
if [[ -f "$ICON_SRC" ]]; then
  # PNG used by About screen and any runtime UI.
  cp "$ICON_SRC" "$APP/Contents/Resources/AppLogo.png"
  if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 64 128 256 512; do
      sips -z "$s" "$s" "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
      double=$((s * 2))
      sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
  else
    cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.png"
  fi
fi

# Sign (Developer ID when MACWISPR_SIGN_IDENTITY is set; else ad-hoc)
if command -v codesign >/dev/null 2>&1; then
  "$ROOT/scripts/sign-and-notarize.sh" "$APP"
fi

# Zip for GitHub Releases (after sign/staple so the zip carries the ticket)
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
if [[ -n "${MACWISPR_SIGN_IDENTITY:-}" && "${MACWISPR_SIGN_IDENTITY}" != "-" ]]; then
  echo "✓ Signed: Developer ID (stable TCC / Accessibility across updates)"
else
  echo "⚠ Signed: ad-hoc — Accessibility will not survive the next update"
  echo "  Set MACWISPR_SIGN_IDENTITY to fix permanently (docs/context/SIGNING.md)"
fi
echo ""
echo "Open with:  open \"$APP\""
echo "Or install:  cp -R \"$APP\" /Applications/"

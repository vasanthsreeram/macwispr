#!/usr/bin/env bash
# Package MacWispr.app into a polished drag-to-Applications .dmg
# (large icons, custom background, fixed window layout via dmgbuild).
#
# Signing (same env as sign-and-notarize.sh):
#   MACWISPR_SIGN_IDENTITY=...                      → Developer ID sign the DMG
#   + MACWISPR_NOTARY_PROFILE=... (or MACWISPR_APPLE_ID / MACWISPR_TEAM_ID /
#     MACWISPR_APP_PASSWORD)                        → notarize + staple + verify
#   MACWISPR_SKIP_NOTARIZE=1                        → sign only
# Without MACWISPR_SIGN_IDENTITY the DMG is left unsigned (local/dev builds).
# Gatekeeper checks the DMG itself on open, so a notarized app inside an
# unsigned DMG still triggers the "cannot be verified" warning.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${MACWISPR_VERSION:-1.2.4}"
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

IDENTITY="${MACWISPR_SIGN_IDENTITY:-}"
DMG_STATUS="unsigned"

notary_auth() {
  if [[ -n "${MACWISPR_NOTARY_PROFILE:-}" ]]; then
    NOTARY_AUTH=(--keychain-profile "$MACWISPR_NOTARY_PROFILE")
  elif [[ -n "${MACWISPR_APPLE_ID:-}" && -n "${MACWISPR_TEAM_ID:-}" && -n "${MACWISPR_APP_PASSWORD:-}" ]]; then
    NOTARY_AUTH=(--apple-id "$MACWISPR_APPLE_ID" --team-id "$MACWISPR_TEAM_ID" --password "$MACWISPR_APP_PASSWORD")
  else
    return 1
  fi
}

notarize_dmg() {
  # The app must already carry its own ticket; otherwise users who copy it
  # out of the DMG while offline get a Gatekeeper prompt for the app.
  if ! xcrun stapler validate "$APP" >/dev/null 2>&1; then
    echo "error: $APP is not notarized + stapled; notarize the app before the DMG" >&2
    exit 1
  fi

  local result status id
  result="$(mktemp -t MacWispr-dmg-notary)"
  echo "==> Submitting DMG to Apple notary service..."
  xcrun notarytool submit "$DMG_VERSIONED" "${NOTARY_AUTH[@]}" \
    --wait --output-format json >"$result" || true  # status checked below
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
  id="$(plutil -extract id raw -o - "$result" 2>/dev/null || echo unknown)"
  rm -f "$result"
  echo "    submission $id: $status"
  if [[ "$status" != "Accepted" ]]; then
    echo "error: DMG notarization $status" >&2
    if [[ "$id" != "unknown" ]]; then
      xcrun notarytool log "$id" "${NOTARY_AUTH[@]}" >&2 || true
    fi
    exit 1
  fi

  echo "==> Stapling DMG ticket..."
  xcrun stapler staple "$DMG_VERSIONED"
  xcrun stapler validate "$DMG_VERSIONED"
  spctl -a -vvv -t open --context context:primary-signature "$DMG_VERSIONED"
  DMG_STATUS="Developer ID signed + notarized + stapled"
}

if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  echo "==> Skipping DMG signing + notarization (MACWISPR_SIGN_IDENTITY not set)"
  echo "    Gatekeeper will show a \"cannot be verified\" warning — do not publish this DMG."
else
  echo "==> Developer ID sign DMG: $IDENTITY"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG_VERSIONED"
  codesign --verify --strict --verbose=2 "$DMG_VERSIONED"
  DMG_STATUS="Developer ID signed (not notarized)"

  if [[ "${MACWISPR_SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "==> Skipping DMG notarization (MACWISPR_SKIP_NOTARIZE=1)"
  elif notary_auth; then
    notarize_dmg
  else
    echo "==> Skipping DMG notarization (set MACWISPR_NOTARY_PROFILE or APPLE_ID/TEAM_ID/APP_PASSWORD)"
  fi
fi

# Copy after stapling so both release assets carry the ticket.
cp "$DMG_VERSIONED" "$DMG_STABLE"

echo ""
echo "✓ DMG:     $DMG_VERSIONED"
echo "✓ Stable:  $DMG_STABLE"
echo "  Size:    $(du -h "$DMG_VERSIONED" | awk '{print $1}')"
echo "  Signing: $DMG_STATUS"
echo "  Open:    open \"$DMG_VERSIONED\""

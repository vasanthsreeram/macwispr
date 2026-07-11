#!/usr/bin/env bash
# Sign (Developer ID) + optionally notarize a MacWispr.app.
#
# Durable TCC identity requires a stable Team ID from Apple Developer Program.
# Ad-hoc signing (codesign -s -) re-keys Accessibility on every build hash.
#
# Usage:
#   export MACWISPR_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   # Optional notarization (pick one):
#   export MACWISPR_NOTARY_PROFILE="AC_PASSWORD"   # xcrun notarytool store-credentials
#   # OR:
#   export MACWISPR_APPLE_ID="you@example.com"
#   export MACWISPR_TEAM_ID="TEAMID"
#   export MACWISPR_APP_PASSWORD="app-specific-password"
#
#   ./scripts/sign-and-notarize.sh [path/to/MacWispr.app]
#
# Without MACWISPR_SIGN_IDENTITY, falls back to ad-hoc sign and prints a warning.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/MacWispr.app}"
ENTITLEMENTS="${MACWISPR_ENTITLEMENTS:-$ROOT/MacWispr.entitlements}"
IDENTITY="${MACWISPR_SIGN_IDENTITY:-}"

if [[ ! -d "$APP" ]]; then
  echo "error: app not found at $APP" >&2
  exit 1
fi

sign_adhoc() {
  echo "==> Ad-hoc codesign (no Team ID — Accessibility will reset on each update)"
  codesign --force --deep --sign - "$APP"
  codesign --verify --verbose=2 "$APP" 2>&1 | tail -5 || true
  echo ""
  echo "⚠  Ship Developer ID to stop TCC churn:"
  echo "   export MACWISPR_SIGN_IDENTITY=\"Developer ID Application: Name (TEAMID)\""
  echo "   ./scripts/sign-and-notarize.sh"
  echo "   See docs/context/SIGNING.md"
}

sign_developer_id() {
  echo "==> Developer ID sign: $IDENTITY"
  echo "    hardened runtime + entitlements: $ENTITLEMENTS"
  if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "error: missing entitlements at $ENTITLEMENTS" >&2
    exit 1
  fi

  # Deep sign nested binaries first, then the bundle.
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$APP"

  codesign --verify --deep --strict --verbose=2 "$APP"
  echo "✓ Signed with Developer ID"
  codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|flags|Identifier' || true
}

notarize() {
  local zip
  zip="$(mktemp -t MacWispr-notarize).zip"
  echo "==> Zip for notarytool..."
  ditto -c -k --keepParent "$APP" "$zip"

  if [[ -n "${MACWISPR_NOTARY_PROFILE:-}" ]]; then
    echo "==> Submitting to Apple notary service (profile: $MACWISPR_NOTARY_PROFILE)..."
    xcrun notarytool submit "$zip" \
      --keychain-profile "$MACWISPR_NOTARY_PROFILE" \
      --wait
  elif [[ -n "${MACWISPR_APPLE_ID:-}" && -n "${MACWISPR_TEAM_ID:-}" && -n "${MACWISPR_APP_PASSWORD:-}" ]]; then
    echo "==> Submitting to Apple notary service (Apple ID)..."
    xcrun notarytool submit "$zip" \
      --apple-id "$MACWISPR_APPLE_ID" \
      --team-id "$MACWISPR_TEAM_ID" \
      --password "$MACWISPR_APP_PASSWORD" \
      --wait
  else
    rm -f "$zip"
    echo "==> Skipping notarization (set MACWISPR_NOTARY_PROFILE or APPLE_ID/TEAM_ID/APP_PASSWORD)"
    return 0
  fi

  rm -f "$zip"
  echo "==> Stapling ticket..."
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  echo "✓ Notarized + stapled"
}

if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  sign_adhoc
else
  # Verify identity exists
  if ! security find-identity -v -p codesigning | grep -F "$IDENTITY" >/dev/null 2>&1; then
    # Allow partial match (user may pass name without exact string)
    if ! security find-identity -v -p codesigning | grep -qi "Developer ID Application"; then
      echo "error: no Developer ID Application identity in keychain" >&2
      echo "  Install your .p12 / certificate from developer.apple.com" >&2
      exit 1
    fi
  fi
  sign_developer_id
  if [[ "${MACWISPR_SKIP_NOTARIZE:-0}" != "1" ]]; then
    notarize
  fi
fi

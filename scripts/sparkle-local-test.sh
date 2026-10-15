#!/usr/bin/env bash
# Stage a local Sparkle update test WITHOUT touching production appcast.
#
# Flow:
#   1) Install 1.2.3 into /Applications (old production baseline)
#   2) Point its SUFeedURL at http://127.0.0.1:8765/appcast-test.xml
#   3) Ad-hoc re-sign (plist edit invalidates Developer ID — fine for update test)
#   4) You serve sparkle-test/ and click Check for Updates
#
# Prerequisites (already prepared by release prep):
#   dist/MacWispr-1.2.3-macos-arm64.zip
#   dist/MacWispr-1.2.4-macos-arm64.zip  (Sparkle-signed; appcast-test.xml present)
#   sparkle-test/appcast-test.xml
#
# Usage:
#   ./scripts/sparkle-local-test.sh install   # put 1.2.3 + local feed in /Applications
#   ./scripts/sparkle-local-test.sh serve     # HTTP server for appcast + zip
#   Then open MacWispr → Check for Updates…
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT="${SPARKLE_TEST_PORT:-8765}"
FEED_URL="http://127.0.0.1:${PORT}/appcast-test.xml"
APP="/Applications/MacWispr.app"
BASELINE_ZIP="$ROOT/dist/MacWispr-1.2.3-macos-arm64.zip"
TEST_DIR="$ROOT/sparkle-test"

cmd="${1:-}"

case "$cmd" in
  install)
    test -f "$BASELINE_ZIP" || { echo "missing $BASELINE_ZIP" >&2; exit 1; }
    test -f "$TEST_DIR/appcast-test.xml" || { echo "missing appcast-test.xml — run sign_update + generate first" >&2; exit 1; }

    echo "==> Quit MacWispr if running"
    osascript -e 'quit app "MacWispr"' 2>/dev/null || true
    pkill -x MacWispr 2>/dev/null || true
    sleep 1

    echo "==> Install 1.2.3 baseline into /Applications"
    rm -rf "$APP"
    TMP="$(mktemp -d)"
    ditto -x -k "$BASELINE_ZIP" "$TMP"
    # zip contains MacWispr.app at top level
    if [[ -d "$TMP/MacWispr.app" ]]; then
      cp -R "$TMP/MacWispr.app" "$APP"
    else
      # nested layout fallback
      FOUND="$(find "$TMP" -maxdepth 3 -type d -name 'MacWispr.app' | head -1)"
      test -n "$FOUND"
      cp -R "$FOUND" "$APP"
    fi
    rm -rf "$TMP"

    VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
    echo "    installed version: $VER"
    if [[ "$VER" != "1.2.3" ]]; then
      echo "warning: expected 1.2.3, got $VER" >&2
    fi

    echo "==> Point SUFeedURL at local staging feed"
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $FEED_URL" "$APP/Contents/Info.plist"

    echo "==> Ad-hoc re-sign (required after plist edit)"
    codesign --force --deep --sign - "$APP"
    xattr -cr "$APP" 2>/dev/null || true

    echo ""
    echo "✓ Baseline ready: $APP ($VER)"
    echo "  SUFeedURL = $FEED_URL"
    echo ""
    echo "Next:"
    echo "  1) ./scripts/sparkle-local-test.sh serve"
    echo "  2) open -a MacWispr"
    echo "  3) Menu bar → Check for Updates…  (or Settings → About)"
    echo "  4) Accept 1.2.4, wait for download (~1.2 GB), confirm About says 1.2.4"
    echo ""
    echo "Note: first launch after ad-hoc re-sign may need right-click → Open once."
    ;;

  serve)
    test -f "$TEST_DIR/appcast-test.xml" || { echo "missing $TEST_DIR/appcast-test.xml" >&2; exit 1; }
    test -e "$TEST_DIR/MacWispr-1.2.4-macos-arm64.zip" || {
      ln -sfn ../dist/MacWispr-1.2.4-macos-arm64.zip "$TEST_DIR/MacWispr-1.2.4-macos-arm64.zip"
    }
    echo "==> Serving $TEST_DIR on http://127.0.0.1:${PORT}/"
    echo "    appcast: $FEED_URL"
    echo "    zip:     http://127.0.0.1:${PORT}/MacWispr-1.2.4-macos-arm64.zip"
    echo "    Ctrl+C to stop"
    echo ""
    cd "$TEST_DIR"
    exec python3 -m http.server "$PORT" --bind 127.0.0.1
    ;;

  status)
    echo "App: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo missing)"
    echo "Feed: $(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" 2>/dev/null || echo missing)"
    echo "Staging appcast:"
    curl -sS "http://127.0.0.1:${PORT}/appcast-test.xml" 2>/dev/null | head -20 || echo "  (server not running)"
    ;;

  *)
    echo "Usage: $0 {install|serve|status}" >&2
    exit 1
    ;;
esac

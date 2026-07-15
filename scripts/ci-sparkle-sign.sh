#!/usr/bin/env bash
# Sparkle-sign a release zip and print edSignature + length for appcast.xml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="${1:?usage: ci-sparkle-sign.sh path/to/MacWispr-X.Y.Z-macos-arm64.zip}"

: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY secret is required}"

SIGN_UPDATE=""
for candidate in \
  "$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
  "$(find "$ROOT/.build/artifacts" -type f -name sign_update 2>/dev/null | head -n1)" \
  "$(find "$ROOT/.build" -type f -name sign_update 2>/dev/null | head -n1)"
do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    SIGN_UPDATE="$candidate"
    break
  fi
done

if [[ -z "$SIGN_UPDATE" ]]; then
  echo "error: sign_update not found — run scripts/build-app.sh first" >&2
  exit 1
fi

KEY_FILE="${RUNNER_TEMP:-/tmp}/sparkle_ed_key"
umask 077
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"

echo "==> Sparkle-signing $(basename "$ZIP")..."
OUTPUT="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$ZIP" 2>&1)"
echo "$OUTPUT"

ED_SIG="$(echo "$OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -n1)"
LENGTH="$(stat -f%z "$ZIP" 2>/dev/null || stat -c%s "$ZIP")"

if [[ -z "$ED_SIG" ]]; then
  echo "error: could not parse sparkle:edSignature from sign_update output" >&2
  exit 1
fi

echo "SPARKLE_ED_SIGNATURE=$ED_SIG"
echo "SPARKLE_ENCLOSURE_LENGTH=$LENGTH"
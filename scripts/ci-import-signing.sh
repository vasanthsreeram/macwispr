#!/usr/bin/env bash
# Import Developer ID certificate into an ephemeral keychain (GitHub Actions).
set -euo pipefail

: "${DEVELOPER_ID_CERTIFICATE_P12:?DEVELOPER_ID_CERTIFICATE_P12 secret is required}"
: "${DEVELOPER_ID_CERTIFICATE_PASSWORD:?DEVELOPER_ID_CERTIFICATE_PASSWORD secret is required}"

KEYCHAIN="${RUNNER_TEMP:?}/build.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
CERT_PATH="$RUNNER_TEMP/certificate.p12"

echo "==> Creating CI keychain..."
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

echo "==> Importing Developer ID certificate..."
echo "$DEVELOPER_ID_CERTIFICATE_P12" | base64 --decode > "$CERT_PATH"
security import "$CERT_PATH" \
  -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

# Prefer this keychain for codesign / notarytool in later steps.
EXISTING="$(security list-keychains -d user | sed 's/^[[:space:]]*"\(.*\)".*/\1/' | tr '\n' ' ')"
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

if [[ -z "${MACWISPR_SIGN_IDENTITY:-}" ]]; then
  MACWISPR_SIGN_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" \
    | grep 'Developer ID Application' \
    | head -1 \
    | sed -E 's/.*"([^"]+)"/\1/')"
fi
if [[ -z "${MACWISPR_SIGN_IDENTITY:-}" ]]; then
  echo "error: could not resolve Developer ID Application identity after import" >&2
  exit 1
fi

export MACWISPR_SIGN_IDENTITY
echo "==> Signing identity: $MACWISPR_SIGN_IDENTITY"
security find-identity -v -p codesigning "$KEYCHAIN" | grep 'Developer ID Application' || true

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "MACWISPR_SIGN_IDENTITY=$MACWISPR_SIGN_IDENTITY" >> "$GITHUB_ENV"
fi
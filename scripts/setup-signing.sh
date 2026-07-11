#!/usr/bin/env bash
# One-shot CLI setup for Developer ID + notarization (MacWispr).
#
# Fully automatic cert *issuance* is not possible without an App Store Connect
# API key (Apple still requires authenticated portal/API). This script does
# everything else from the terminal:
#   1. Generate a private key + CSR
#   2. Open Apple's cert page (you upload CSR, download .cer — ~1 minute)
#   3. Import the .cer into your login keychain
#   4. Store notarytool credentials in Keychain
#   5. Write .env.signing (gitignored) for future builds
#
# Usage:
#   ./scripts/setup-signing.sh
#   ./scripts/setup-signing.sh --import ~/Downloads/developerID_application.cer
#   source .env.signing && ./scripts/build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM_ID="${MACWISPR_TEAM_ID:-UTSTY3J6NS}"
NOTARY_PROFILE="${MACWISPR_NOTARY_PROFILE:-MacWispr-notary}"
WORKDIR="${MACWISPR_SIGNING_DIR:-$ROOT/.signing}"
ENV_FILE="$ROOT/.env.signing"
KEY_PATH="$WORKDIR/DeveloperID.key"
CSR_PATH="$WORKDIR/DeveloperID.certSigningRequest"
CER_PATH="$WORKDIR/developerID_application.cer"

mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR" 2>/dev/null || true

# Ensure .signing + .env.signing stay local
if [[ -f "$ROOT/.gitignore" ]]; then
  grep -qxF '.signing/' "$ROOT/.gitignore" 2>/dev/null || echo '.signing/' >> "$ROOT/.gitignore"
  grep -qxF '.env.signing' "$ROOT/.gitignore" 2>/dev/null || echo '.env.signing' >> "$ROOT/.gitignore"
fi

die() { echo "error: $*" >&2; exit 1; }

have_developer_id() {
  security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"
}

print_identity() {
  security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" || true
}

import_cer() {
  local cer="$1"
  [[ -f "$cer" ]] || die "certificate not found: $cer"
  echo "==> Importing $(basename "$cer") into login keychain..."
  security import "$cer" -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null \
    || security import "$cer" -k ~/Library/Keychains/login.keychain-db
  # Allow codesign to use the key without GUI prompt (best-effort)
  if [[ -f "$KEY_PATH" ]]; then
    security import "$KEY_PATH" -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null || true
  fi
  # Pairing: Apple issues cert for the public key in CSR; private key must already be in keychain
  if ! have_developer_id; then
    echo "⚠  Cert imported but no valid 'Developer ID Application' identity yet."
    echo "   Usually means the private key for this CSR is missing from Keychain."
    echo "   Re-run this script from scratch so the key is created *before* the CSR upload."
    security find-identity -p codesigning 2>&1 || true
    exit 1
  fi
  echo "✓ Developer ID identity ready:"
  print_identity
}

generate_csr() {
  if [[ -f "$KEY_PATH" && -f "$CSR_PATH" ]]; then
    echo "==> Reusing existing key + CSR in $WORKDIR"
    return 0
  fi
  echo "==> Generating private key + CSR (RSA 2048)..."
  openssl genrsa -out "$KEY_PATH" 2048
  chmod 600 "$KEY_PATH"
  # Common Name is cosmetic; Team ID is bound by Apple when they issue the cert
  openssl req -new -key "$KEY_PATH" -out "$CSR_PATH" \
    -subj "/emailAddress=developer@macwispr.local/CN=Developer ID Application/C=SG"
  # Import private key first so the later .cer pairs into a full identity
  security import "$KEY_PATH" -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -T /usr/bin/security
  echo "✓ CSR: $CSR_PATH"
  echo "✓ Key imported into login keychain"
}

open_apple_cert_page() {
  echo ""
  echo "────────────────────────────────────────────────────────────"
  echo "  Apple cannot issue Developer ID certs purely offline."
  echo "  Do this once in the browser (~1 min):"
  echo ""
  echo "  1. Open: https://developer.apple.com/account/resources/certificates/add"
  echo "  2. Choose:  Developer ID Application  → Continue"
  echo "  3. Upload:  $CSR_PATH"
  echo "  4. Download the .cer"
  echo "  5. Come back here (or re-run with --import path/to.cer)"
  echo "────────────────────────────────────────────────────────────"
  echo ""
  open "https://developer.apple.com/account/resources/certificates/add" 2>/dev/null || true
  open -R "$CSR_PATH" 2>/dev/null || true
}

# Status messages go to stderr so callers can capture only the path on stdout.
wait_for_cer() {
  echo "Waiting for certificate..." >&2
  echo "  • Drop the .cer into: $WORKDIR/" >&2
  echo "  • Or into ~/Downloads/ (named developerID*.cer)" >&2
  echo "  • Or press Enter and paste a path" >&2
  echo "" >&2

  local deadline=$((SECONDS + 600))
  while (( SECONDS < deadline )); do
    # Prefer explicit workdir
    if [[ -f "$CER_PATH" ]]; then
      printf '%s\n' "$CER_PATH"
      return 0
    fi
    # Any .cer dropped into workdir
    local found
    found="$(find "$WORKDIR" -maxdepth 1 -name '*.cer' -type f 2>/dev/null | head -1 || true)"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return 0
    fi
    # Common Downloads names from Apple
    found="$(find "$HOME/Downloads" -maxdepth 1 \( -name 'developerID_application*.cer' -o -name 'developerID*.cer' \) -type f 2>/dev/null | head -1 || true)"
    if [[ -n "$found" ]]; then
      cp "$found" "$CER_PATH"
      printf '%s\n' "$CER_PATH"
      return 0
    fi
    # Non-blocking check every 2s; allow Enter+path
    if read -r -t 2 path 2>/dev/null; then
      path="${path/#\~/$HOME}"
      if [[ -f "$path" ]]; then
        cp "$path" "$CER_PATH"
        printf '%s\n' "$CER_PATH"
        return 0
      fi
      echo "  not a file: $path" >&2
    fi
  done
  die "timed out waiting for .cer (10 min). Re-run: $0 --import /path/to.cer"
}

setup_notary() {
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "✓ Notary profile already stored: $NOTARY_PROFILE"
    return 0
  fi

  echo ""
  echo "==> Notarization credentials (stored in Keychain as '$NOTARY_PROFILE')"
  echo "    Create an app-specific password first:"
  echo "    https://appleid.apple.com/account/manage → Sign-In → App-Specific Passwords"
  echo ""
  local apple_id password
  read -r -p "Apple ID email: " apple_id
  [[ -n "$apple_id" ]] || die "Apple ID required"
  read -r -s -p "App-specific password (xxxx-xxxx-xxxx-xxxx): " password
  echo ""
  [[ -n "$password" ]] || die "password required"

  xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --apple-id "$apple_id" \
    --team-id "$TEAM_ID" \
    --password "$password"
  echo "✓ Notary credentials stored"
}

write_env() {
  local identity
  identity="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
  [[ -n "$identity" ]] || die "could not resolve Developer ID identity string"

  cat > "$ENV_FILE" <<EOF
# Generated by scripts/setup-signing.sh — do not commit
export MACWISPR_TEAM_ID="$TEAM_ID"
export MACWISPR_SIGN_IDENTITY="$identity"
export MACWISPR_NOTARY_PROFILE="$NOTARY_PROFILE"
EOF
  chmod 600 "$ENV_FILE"
  echo "✓ Wrote $ENV_FILE"
  echo ""
  echo "Ship a signed + notarized build with:"
  echo "  source .env.signing && ./scripts/build-app.sh"
}

# ── main ──────────────────────────────────────────────────────────
IMPORT_ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --import) IMPORT_ONLY="${2:-}"; shift 2 ;;
    --team-id) TEAM_ID="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

echo "MacWispr signing setup  (Team ID: $TEAM_ID)"
echo ""

if [[ -n "$IMPORT_ONLY" ]]; then
  import_cer "$IMPORT_ONLY"
elif have_developer_id; then
  echo "✓ Developer ID already present:"
  print_identity
else
  generate_csr
  open_apple_cert_page
  cer="$(wait_for_cer)"
  import_cer "$cer"
fi

setup_notary
write_env
echo ""
echo "All set."

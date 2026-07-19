#!/usr/bin/env bash
# Prepend a Sparkle appcast <item> for a new release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: ci-update-appcast.sh VERSION ED_SIGNATURE ENCLOSURE_LENGTH [notes-file]}"
ED_SIGNATURE="${2:?missing edSignature}"
ENCLOSURE_LENGTH="${3:?missing enclosure length}"
NOTES_FILE="${4:-}"

APPCAST="$ROOT/website/appcast.xml"
TAG="v$VERSION"
ZIP_NAME="MacWispr-${VERSION}-macos-arm64.zip"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
  NOTES_HTML="$(cat "$NOTES_FILE")"
else
  NOTES_HTML="<h2>MacWispr ${VERSION}</h2><p>See the <a href=\"https://github.com/vasanthsreeram/macwispr/releases/tag/${TAG}\">GitHub release notes</a>.</p>"
fi

if grep -q "<sparkle:version>${VERSION}</sparkle:version>" "$APPCAST"; then
  echo "error: appcast already contains version ${VERSION}" >&2
  exit 1
fi

ITEM_FILE="$(mktemp)"
cat > "$ITEM_FILE" <<EOF
    <item>
      <title>MacWispr ${VERSION}</title>
      <link>https://github.com/vasanthsreeram/macwispr/releases/tag/${TAG}</link>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <description><![CDATA[
        ${NOTES_HTML}
      ]]></description>
      <enclosure
        url="https://github.com/vasanthsreeram/macwispr/releases/download/${TAG}/${ZIP_NAME}"
        length="${ENCLOSURE_LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIGNATURE}"
      />
    </item>

EOF

# Insert after the channel header block (before the first existing <item>).
python3 - "$APPCAST" "$ITEM_FILE" <<'PY'
import sys
from pathlib import Path

appcast = Path(sys.argv[1])
item = Path(sys.argv[2]).read_text()
text = appcast.read_text()
needle = "    <item>"
if needle not in text:
    raise SystemExit("could not find insertion point in appcast.xml")
text = text.replace(needle, item + needle, 1)
appcast.write_text(text)
PY

rm -f "$ITEM_FILE"
echo "==> Updated $APPCAST for MacWispr ${VERSION}"
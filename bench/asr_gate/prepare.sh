#!/usr/bin/env bash
# Fetch / generate the ASR gate audio (everything lands in gitignored bench/data/).
#   - LibriSpeech test-clean (~350 MB) if missing
#   - Multilingual clips spoken by macOS `say`, from manifest.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DATA="bench/data/librispeech"
if [[ ! -d "$DATA/LibriSpeech/test-clean" ]]; then
  mkdir -p "$DATA"
  if [[ ! -f "$DATA/test-clean.tar.gz" ]]; then
    echo "==> Downloading LibriSpeech test-clean (~350 MB)"
    curl -L --fail -o "$DATA/test-clean.tar.gz.partial" https://www.openslr.org/resources/12/test-clean.tar.gz
    mv "$DATA/test-clean.tar.gz.partial" "$DATA/test-clean.tar.gz"
  fi
  echo "==> Extracting"
  tar -xzf "$DATA/test-clean.tar.gz" -C "$DATA"
fi

TTS_DIR="bench/data/asr_gate/tts"
mkdir -p "$TTS_DIR"
python3 - "$TTS_DIR" <<'EOF'
import json, subprocess, sys, pathlib
out = pathlib.Path(sys.argv[1])
items = json.loads(pathlib.Path("bench/asr_gate/manifest.json").read_text())["items"]
made = 0
for it in items:
    tts = it.get("tts")
    if not tts:
        continue
    wav = out / tts["file"]
    if wav.exists():
        continue
    aiff = wav.with_suffix(".aiff")
    subprocess.run(["say", "-v", tts["voice"], "-o", str(aiff), it["text"]], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)], check=True)
    aiff.unlink()
    made += 1
print(f"==> TTS clips ready ({made} new) in {out}")
EOF

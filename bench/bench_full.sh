#!/usr/bin/env bash
# Full ASR suite: latency + WER for Qwen MLX / hybrid CoreML / full CoreML / Parakeet.
# Usage:
#   ./bench/bench_full.sh
#   ./bench/bench_full.sh --max-files 20
#   ./bench/bench_full.sh --latency-only
#   ./bench/bench_full.sh --only qwen-0.6b-mlx-8bit,parakeet-v3-coreml
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/preflight-xcode.sh"

DEFAULT_CLIP="$ROOT/bench/clips/speech_12s_16k.wav"
CLIP="$DEFAULT_CLIP"
EXTRA=()
for arg in "$@"; do
  if [[ "$arg" == *.wav ]]; then
    CLIP="$arg"
  else
    EXTRA+=("$arg")
  fi
done

if [[ ! -f "$CLIP" ]]; then
  echo "Missing clip: $CLIP" >&2
  exit 1
fi

if [[ ! -d "$ROOT/bench/data/librispeech/LibriSpeech/test-clean" ]]; then
  echo "LibriSpeech not found — downloading via Python harness helper…"
  # Reuse ensure path from bench_wer (downloads if needed) without full WER.
  uv run --with soundfile python - <<'PY' || python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0, "bench")
# Minimal ensure using same URLs as bench_wer
import tarfile, urllib.request
ROOT = Path(".")
DATA = ROOT / "bench" / "data" / "librispeech"
TAR = DATA / "test-clean.tar.gz"
EXTRACT = DATA / "LibriSpeech" / "test-clean"
URL = "https://www.openslr.org/resources/12/test-clean.tar.gz"
DATA.mkdir(parents=True, exist_ok=True)
if not EXTRACT.exists() or not any(EXTRACT.rglob("*.flac")):
    if not TAR.exists():
        print(f"Downloading {URL} …")
        urllib.request.urlretrieve(URL, TAR)
    print(f"Extracting {TAR} …")
    with tarfile.open(TAR, "r:gz") as tf:
        tf.extractall(DATA, filter="data")
print("LibriSpeech ready:", EXTRACT)
PY
fi

echo "→ Building BenchFull (release)…"
(
  cd "$ROOT"
  swift build -c release --product BenchFull
)

# MLX metallib next to binary
METALLIB_SRC="$(find "$ROOT/.build" -type f -name 'mlx.metallib' 2>/dev/null | head -n1 || true)"
if [[ -n "$METALLIB_SRC" ]]; then
  cp -f "$METALLIB_SRC" "$ROOT/.build/release/mlx.metallib"
  cp -f "$METALLIB_SRC" "$ROOT/.build/release/default.metallib"
fi

BENCH="$ROOT/.build/release/BenchFull"
echo "→ Running full suite…"
echo "  clip: $CLIP"
echo "  args: ${EXTRA[*]:-(defaults)}"
exec "$BENCH" "$CLIP" "${EXTRA[@]}"

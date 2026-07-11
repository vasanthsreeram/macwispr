#!/usr/bin/env bash
# Fast dictation latency — in-process bench (load once + warmup + 16kHz).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Full Xcode.app required for Metal / MLX (Command Line Tools alone are not enough).
"$ROOT/scripts/preflight-xcode.sh"

# Prefer real speech clip; fall back to older sample, then generate speech via `say`.
DEFAULT_CLIP="$ROOT/bench/clips/speech_12s_16k.wav"
CLIP="${1:-}"
if [[ -z "$CLIP" ]]; then
  if [[ -f "$DEFAULT_CLIP" ]]; then
    CLIP="$DEFAULT_CLIP"
  else
    CLIP="$ROOT/bench/clips/sample_10s_16k.wav"
  fi
fi
BENCH="$ROOT/.build/release/BenchLatency"
EXTRA_ARGS=("${@:2}")

mkdir -p "$ROOT/bench/clips"

if [[ ! -f "$CLIP" ]]; then
  if command -v say >/dev/null 2>&1 && command -v ffmpeg >/dev/null 2>&1; then
    echo "→ Generating speech sample via macOS say → $CLIP"
    say -o /tmp/macwispr_bench_say.aiff \
      "Hello, this is a dictation latency benchmark for Mac Whisper."
    ffmpeg -y -i /tmp/macwispr_bench_say.aiff -ac 1 -ar 16000 "$CLIP" -loglevel error
  elif command -v ffmpeg >/dev/null 2>&1; then
    # Last resort: tone (not useful for quality; still ok for raw latency smoke)
    ffmpeg -y -f lavfi -i "sine=frequency=440:duration=10" -ac 1 -ar 16000 "$CLIP" -loglevel error
  else
    echo "Missing $CLIP and cannot generate (need say+ffmpeg or ffmpeg)." >&2
    exit 1
  fi
fi

echo "→ Building BenchLatency..."
(cd "$ROOT" && swift build -c release --product BenchLatency)

# MLX loads GPU shaders from mlx.metallib next to the executable.
# SwiftPM may put it under .build/arm64-…/release/ while the binary is
# linked at .build/release/ — copy both names so Qwen doesn't SIGSEGV.
METALLIB_SRC="$(find "$ROOT/.build" -type f -name 'mlx.metallib' 2>/dev/null | head -n1 || true)"
if [[ -n "$METALLIB_SRC" ]]; then
  cp -f "$METALLIB_SRC" "$ROOT/.build/release/mlx.metallib"
  cp -f "$METALLIB_SRC" "$ROOT/.build/release/default.metallib"
fi

exec "$BENCH" "$CLIP" "${EXTRA_ARGS[@]}"
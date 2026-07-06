#!/usr/bin/env bash
# Fast dictation latency — in-process bench (load once + warmup + 16kHz).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIP="${1:-$ROOT/bench/clips/sample_10s_16k.wav}"
BENCH="$ROOT/.build/release/BenchLatency"

mkdir -p "$ROOT/bench/clips"

if [[ ! -f "$CLIP" ]]; then
  if command -v ffmpeg >/dev/null 2>&1; then
    # Generate a 10s 440Hz tone if no sample exists (works without large audio files)
    ffmpeg -y -f lavfi -i "sine=frequency=440:duration=10" -ac 1 -ar 16000 "$CLIP" -loglevel error
  else
    echo "Missing $CLIP and ffmpeg not installed. Run: brew install ffmpeg" >&2
    exit 1
  fi
fi

if [[ ! -x "$BENCH" ]]; then
  echo "→ Building BenchLatency (first run only)..."
  (cd "$ROOT" && swift build -c release --product BenchLatency)
fi

exec "$BENCH" "$CLIP"
#!/usr/bin/env bash
# Full ASR comparison: Qwen3 MLX + Parakeet CoreML (Swift) + Nemotron MLX (Python).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
"$ROOT/scripts/preflight-xcode.sh"

CLIP="${1:-$ROOT/bench/clips/speech_12s_16k.wav}"
if [[ ! -f "$CLIP" ]]; then
  echo "Missing clip: $CLIP" >&2
  echo "Generate one with: say -o /tmp/s.aiff 'your text' && ffmpeg -y -i /tmp/s.aiff -ac 1 -ar 16000 $CLIP" >&2
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════"
echo " 1/2  Swift: Qwen3 (MLX) + Parakeet (CoreML)"
echo "═══════════════════════════════════════════════════════════════"
(cd "$ROOT" && swift build -c release --product BenchLatency)
"$ROOT/.build/release/BenchLatency" "$CLIP"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " 2/2  Python mlx-audio: Nemotron 3.5 (mlx-community)"
echo "═══════════════════════════════════════════════════════════════"

if command -v uv >/dev/null 2>&1; then
  # Nemotron needs mlx-audio main (not PyPI 0.4.3 yet).
  # default = Nemotron-8bit + Parakeet TDT v3 MLX (primary FluidVoice-class models).
  uv run --with 'git+https://github.com/Blaizzy/mlx-audio.git' \
    python "$ROOT/bench/bench_mlx_audio.py" "$CLIP" --models default
else
  python3 -c "from mlx_audio.stt import load" 2>/dev/null || {
    echo "Install mlx-audio from GitHub main, or install uv:" >&2
    echo "  brew install uv" >&2
    echo "  pip install 'git+https://github.com/Blaizzy/mlx-audio.git'" >&2
    exit 1
  }
  python3 "$ROOT/bench/bench_mlx_audio.py" "$CLIP" --models default
fi

echo ""
echo "Done."
echo "  Parakeet v3 only (MLX):  python3 bench/bench_mlx_audio.py $CLIP --models parakeet-v3"
echo "  Parakeet v2+v3 (MLX):    python3 bench/bench_mlx_audio.py $CLIP --models parakeet"
echo "  All mlx-community:       python3 bench/bench_mlx_audio.py $CLIP --models all"

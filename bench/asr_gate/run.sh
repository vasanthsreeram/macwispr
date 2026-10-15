#!/usr/bin/env bash
# Run the ASR gate for one engine and check it against the Photon baseline.
#
#   bench/asr_gate/run.sh photon                       # (re)record the baseline
#   bench/asr_gate/run.sh coreml                       # Parakeet v3 Core ML INT8 (speech-swift)
#   bench/asr_gate/run.sh coreml --model-dir <dir>     # any converted Core ML Parakeet
#
# Exit code 0 = PASS. Reports land in bench/results/asr_gate/ (gitignored).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ENGINE="${1:?usage: run.sh photon|coreml [--model-dir DIR] [--name NAME]}"
shift
NAME="$ENGINE"
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

./bench/asr_gate/prepare.sh || exit 1
swift build -c release --product ASRGate || exit 1

OUT="bench/results/asr_gate/$NAME.json"
BASE="bench/results/asr_gate/photon.json"
.build/release/ASRGate --engine "$ENGINE" --out "$OUT" ${ARGS[@]+"${ARGS[@]}"} || exit 1

if [[ "$ENGINE" != "photon" && -f "$BASE" ]]; then
  exec python3 bench/asr_gate/check.py "$OUT" --baseline "$BASE"
else
  exec python3 bench/asr_gate/check.py "$OUT"
fi

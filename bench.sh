#!/usr/bin/env bash
# Benchmark Qwen3-ASR latency on your Mac. One command.
set -euo pipefail
cd "$(dirname "$0")"
# Full Xcode.app required for Metal / MLX metallib (CLT alone is not enough).
./scripts/preflight-xcode.sh
exec ./bench/bench_latency.sh "$@"
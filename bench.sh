#!/usr/bin/env bash
# Benchmark ASR latency on your Mac (Qwen3 MLX + Parakeet TDT v3 CoreML).
# Cross-engine (Nemotron / Parakeet MLX too): ./bench/bench_compare.sh
set -euo pipefail
cd "$(dirname "$0")"
# Full Xcode.app required for Metal / MLX metallib (CLT alone is not enough).
./scripts/preflight-xcode.sh
exec ./bench/bench_latency.sh "$@"
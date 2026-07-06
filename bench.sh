#!/usr/bin/env bash
# Benchmark Qwen3-ASR latency on your Mac. One command.
set -euo pipefail
cd "$(dirname "$0")"
exec ./bench/bench_latency.sh "$@"
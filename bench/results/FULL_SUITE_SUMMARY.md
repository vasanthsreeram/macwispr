# Full ASR suite — latency + WER

**Date:** 2026-07-17  
**Host:** Mac, 32 GB, macOS 26.5.1  
**Latency clip:** `bench/clips/speech_12s_16k.wav` (~9.57 s) — best of 3 after warmup  
**WER set:** LibriSpeech test-clean, first 50 utts in 1–30 s window · **375.6 s** audio · **977** ref words  

Harness: `BenchFull` via `./bench/bench_full.sh`  
Raw JSON: `full_suite_latest.json` + `full_suite_coreml_retry` timestamps under `bench/results/`.

## Latency (9.57 s clip)

| Rank | Model | Backend | Best | RTF | Load |
|-----:|-------|---------|-----:|----:|-----:|
| 1 | **Parakeet TDT v3 CoreML INT8** (in-app) | Core ML / ANE | **0.127 s** | **0.013** | 21.9 s |
| 2 | Qwen3 0.6B hybrid (CoreML enc + MLX dec) | ANE + Metal | 0.291 s | 0.030 | 9.8 s |
| 3 | Qwen3 0.6B MLX-8bit (app default) | MLX / GPU | 0.316 s | 0.033 | 5.1 s |
| 4 | Qwen3 1.7B MLX-8bit | MLX / GPU | 0.738 s | 0.077 | 4.3 s |
| — | Qwen3 0.6B **full** CoreML | — | **FAILED** | — | — |

Full CoreML failure: HF ships `decoder_part1.mlmodelc` + `decoder_part2.mlmodelc`; speech-swift expects a single `decoder.mlmodelc`. Not loadable without a library update.

## Accuracy (WER)

| Rank | Model | Aggregate WER | Mean WER | Errors | S / I / D | RTF (WER set) |
|-----:|-------|-------------:|---------:|-------:|----------:|--------------:|
| 1 | **Qwen3 1.7B MLX-8bit** | **0.82%** | 2.00% | 8 / 977 | 7 / 0 / 1 | 0.071 |
| 2 | Qwen3 0.6B MLX-8bit (app default) | **0.92%** | 2.14% | 9 / 977 | 8 / 0 / 1 | 0.030 |
| 2 | Qwen3 0.6B hybrid CoreML+MLX | **0.92%** | 2.14% | 9 / 977 | 8 / 0 / 1 | 0.028 |
| 4 | Parakeet TDT v3 CoreML INT8 | **1.13%** | 2.36% | 11 / 977 | 10 / 0 / 1 | 0.025 |

Hybrid matches pure MLX 0.6B WER **exactly** on this set (same 9 errors) — encoder swap did not hurt clean English.

## Combined view

| Model | Latency | WER | Role |
|-------|--------:|----:|------|
| Parakeet v3 CoreML | **fastest** (0.13 s) | 1.13% | Speed king; slightly worse EN WER |
| Qwen 0.6B MLX | 0.32 s | 0.92% | Default balance + Asian langs + vocab |
| Qwen 0.6B hybrid | 0.29 s | 0.92% | ≈ same as MLX; ANE encoder (power/GPU free) |
| Qwen 1.7B MLX | 0.74 s | **best** 0.82% | Accuracy when you can wait |

## Core ML Qwen takeaways

1. **Hybrid works** (after fixing fixed-shape `1×128×3000` + `mel_length` in the encoder path) and is **not faster than pure MLX in a meaningful way** (~0.29 vs ~0.32 s). Same WER as MLX 0.6B.
2. **Full Core ML Qwen is not usable today** with current speech-swift + published HF weights (split decoder vs single-file API).
3. Putting Qwen on the Neural Engine **does not** make it Parakeet-class fast. Decode remains AR on Metal for hybrid; full ANE decoder is blocked.

## Product recommendation (from this suite)

| Priority | Pick |
|----------|------|
| **Best quality (EN clean)** | Qwen **1.7B** MLX (0.82% WER; ~2.3× slower than 0.6B) |
| **Best default** | Qwen **0.6B** MLX — ties hybrid accuracy, faster load, already shipped |
| **Max speed / EN+EU** | Parakeet v3 Core ML — ~2.5× faster than Qwen 0.6B; **+0.21 pp WER** on this clean set |
| **When Parakeet “feels bad”** | Switch to Qwen 0.6B or 1.7B (this set agrees: Parakeet is slightly worse, not catastrophic) |
| **Do not ship yet** | Full Core ML Qwen; hybrid only if you want ANE encoder for power/GPU reasons (needs speech-swift encoder fix upstream) |

### Caveats

- LibriSpeech **test-clean** is clean English read speech — understates accent / noise / Asian-language gaps where Qwen’s language coverage matters more than Parakeet’s.
- Hybrid used a **local patch** to speech-swift’s `CoreMLEncoder` (fixed mel + `mel_length`). SPM re-resolve will drop it unless pinned/PR’d.
- Absolute ms vary with thermal state and concurrent load.

## Reproduce

```bash
./bench/bench_full.sh                    # full 50-utt suite
./bench/bench_full.sh --max-files 20     # faster smoke
./bench/bench_full.sh --latency-only
./bench/bench_full.sh --only qwen-0.6b-mlx-8bit,parakeet-v3-coreml
```

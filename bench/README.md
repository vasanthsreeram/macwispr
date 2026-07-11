# ASR benchmarks

MacWispr benches its default **Qwen3-ASR (MLX)** stack against **Parakeet TDT v2/v3** and **Nemotron 3.5** (FluidVoice-class engines) for:

1. **Latency** (single-clip, best-of-3 after warmup)
2. **Accuracy / WER** (LibriSpeech test-clean subset)

Published snapshot (M5): **[results/SUMMARY.md](results/SUMMARY.md)** · full narrative: root [README.md § Benchmark](../README.md#benchmark).

## Quick start

From the repo root:

```bash
# Latency — Qwen3 (MLX) + Parakeet TDT v3 (CoreML via speech-swift)
./bench.sh

# Latency — full cross-engine compare (Swift + mlx-audio)
./bench/bench_compare.sh

# Latency — official mlx-community models only
uv run --with 'git+https://github.com/Blaizzy/mlx-audio.git' \
  python bench/bench_mlx_audio.py bench/clips/speech_12s_16k.wav --models default

# Accuracy (WER) — LibriSpeech test-clean subset
uv run --with 'git+https://github.com/Blaizzy/mlx-audio.git' --with soundfile \
  python bench/bench_wer.py --max-files 50 --models default \
  --out bench/results/wer_m5_50.json
```

### Model selection flags

| Harness | `--models` values |
|---------|-------------------|
| `bench_mlx_audio.py` (latency) | `default` · `parakeet` · `parakeet-v3` · `nemotron` · `all` |
| `bench_wer.py` (accuracy) | `default` · `all` · `qwen` · `parakeet` · `nemotron` · model id |

`default` for WER = Qwen 0.6B 8-bit + Parakeet v2 + Parakeet v3 + Nemotron 8-bit.

## What each path measures

| Harness | Engines | Backend | Metric |
|---------|---------|---------|--------|
| `./bench.sh` → `BenchLatency` | Qwen3-ASR 0.6B/1.7B | MLX (Metal) | Latency |
| same | Parakeet TDT **v3** INT4/INT8 | CoreML (ANE) via speech-swift | Latency |
| `bench/bench_mlx_audio.py` | Nemotron 3.5 · Parakeet v2/v3 | MLX (`mlx-community/*`) | Latency |
| `bench/bench_wer.py` | Qwen · Parakeet v2/v3 · Nemotron | MLX (`mlx-audio`) | **WER + RTF** |
| optional `--include-fluidaudio` | Parakeet v3 | FluidAudio CoreML CLI | WER + wall time |

### Latency method

Load once → warmup → 3 timed runs → report **best** latency and RTF (latency ÷ audio duration).

Default clip: `bench/clips/speech_12s_16k.wav` (~9.6 s, 16 kHz mono).

```bash
./bench.sh path/to/clip.wav
./bench/bench_compare.sh path/to/clip.wav
```

### WER method

1. Download LibriSpeech **test-clean** once (~350 MB → `bench/data/`, gitignored)
2. Take first N utterances in the 1–30 s duration window (`--max-files`, default 50)
3. Transcribe with each model; score with lowercase + strip-punctuation normalizer
4. Report **aggregate WER** (total edits ÷ total ref words), mean per-utt WER, RTF, S/I/D

| Flag | Meaning |
|------|---------|
| `--max-files 50` | Local iteration subset (~376 s / ~977 words on M5 run) |
| `--max-files 0` | Full test-clean (2620 utts) — slow, publication-grade |
| `--models default` | Qwen 0.6B 8-bit + Parakeet v2/v3 + Nemotron 8-bit |
| `--models all` | Also includes Qwen 1.7B 8-bit |
| `--include-fluidaudio` | Optional CoreML Parakeet via `fluidaudiocli` |
| `--out path.json` | JSON report |

## Latest snapshot (Apple M5, 32 GB)

### Latency (~9.6 s clip)

| Model | Latency | RTF |
|-------|--------:|----:|
| Parakeet v2 MLX | **0.081s** | **0.009** |
| Parakeet v3 MLX | **0.091s** | **0.009** |
| Nemotron 8-bit MLX | **0.409s** | **0.043** |
| Qwen 0.6B 8-bit MLX | ~0.4s | **0.040** (from WER harness) |

### WER (50 LibriSpeech utts, 977 words)

| Model | Aggregate WER | Errors |
|-------|--------------:|-------:|
| Parakeet v2 | **0.72%** | 7 |
| Qwen 0.6B 8-bit | **0.92%** | 9 |
| Parakeet v3 | **0.92%** | 9 |
| Nemotron 8-bit | 1.64% | 16 |

See [results/SUMMARY.md](results/SUMMARY.md) for the committed copy of these numbers.

## Requirements

- macOS 14+, Apple Silicon
- Full Xcode (Metal toolchain for Swift/MLX metallib path)
- `ffmpeg` (optional sample generation; used for FluidAudio WAV conversion)
- For Python harnesses: [`uv`](https://github.com/astral-sh/uv) **or**  
  `pip install 'git+https://github.com/Blaizzy/mlx-audio.git' soundfile`

## Interpreting results

- **RTF under 1.0** = faster than realtime (good for dictation)
- **Lower WER** = better accuracy on that set
- Parakeet **v3** = multilingual (25 European languages); **v2** = English-only
- FluidVoice production path is often **CoreML/ANE** (FluidAudio); our primary open compare uses **mlx-community** MLX ports
- MacWispr product default remains **Qwen3-ASR 0.6B MLX-8bit** (WER ties Parakeet v3 here; 52 languages)

Absolute ms and WER vary by chip, power mode, thermal state, and utterance set.

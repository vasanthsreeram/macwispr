# Benchmark snapshot — Apple M5 (32 GB)

Last updated: **2026-07-12**

Re-run:

```bash
# Latency
./bench/bench_compare.sh bench/clips/speech_12s_16k.wav

# WER (writes JSON next to this file when using --out)
uv run --with 'git+https://github.com/Blaizzy/mlx-audio.git' --with soundfile \
  python bench/bench_wer.py --max-files 50 --models default \
  --out bench/results/wer_m5_50.json
```

## Latency (~9.6 s speech clip)

| Model | Backend | Best latency | RTF |
|-------|---------|-------------:|----:|
| Parakeet TDT 0.6B **v2** | MLX | **0.081s** | **0.009** |
| Parakeet TDT 0.6B **v3** | MLX | **0.091s** | **0.009** |
| Parakeet TDT 0.6B v3 | CoreML speech-swift INT8 (in-app, fixed 30s) | **0.13s** | **0.014** |
| Parakeet TDT 0.6B v3 | CoreML FluidAudio CLI (warm wall) | ~0.18s | ~0.019 |
| Parakeet TDT 0.6B v2 | CoreML FluidAudio CLI (warm wall) | ~0.20s | ~0.021 |
| Nemotron 3.5 streaming 0.6B | MLX-8bit | **0.409s** | **0.043** |
| Qwen3-ASR 0.6B 8-bit | MLX (WER-harness RTF on LS) | ~0.4s equiv. | **0.040** |

Clip: `bench/clips/speech_12s_16k.wav` (macOS `say` → 16 kHz mono).

## Accuracy — LibriSpeech test-clean subset

| Setting | Value |
|---------|-------|
| Utterances | 50 (1–30 s duration window) |
| Audio | ~376 s |
| Reference words | 977 |
| Normalizer | lowercase, strip punctuation |
| Harness | `bench/bench_wer.py` + mlx-audio |

| Model | Aggregate WER | Mean WER | Errors / words | S / I / D | RTF |
|-------|--------------:|---------:|---------------:|----------:|----:|
| **Parakeet TDT 0.6B v2** | **0.72%** | 1.71% | 7 / 977 | 5 / 0 / 2 | 0.011 |
| **Qwen3-ASR 0.6B 8-bit** | **0.92%** | 2.14% | 9 / 977 | 8 / 0 / 1 | 0.040 |
| **Parakeet TDT 0.6B v3** | **0.92%** | 2.18% | 9 / 977 | 8 / 0 / 1 | 0.011 |
| Nemotron 3.5 0.6B 8-bit | 1.64% | 3.22% | 16 / 977 | 13 / 1 / 2 | 0.043 |

Raw JSON (local, gitignored): `bench/results/wer_m5_50.json` after you re-run the WER harness.

## Product note

MacWispr ships **Qwen3-ASR 0.6B 8-bit** as the default local engine: matches Parakeet v3 WER on this EN set, covers 52 languages, still ~25× realtime. Parakeet remains the speed leader if we add engine choice later.

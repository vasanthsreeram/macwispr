# Qwen3-ASR Benchmark

In-process latency benchmark for [Qwen3-ASR](https://huggingface.co/collections/Qwen/qwen3-asr) on Apple Silicon via [speech-swift](https://github.com/soniqo/speech-swift).

## Quick start

From the repo root:

```bash
./bench.sh
```

First run downloads models (~300 MB–2 GB) and builds the benchmark binary. Subsequent runs finish in under a minute.

## What it measures

| Step | Why |
|------|-----|
| Load model once | Matches a running dictation app |
| Metal warmup | Compiles GPU kernels before timing |
| 16 kHz mono | Same sample rate as OpenWhispr |
| 3 timed runs | Reports best inference time (not cold-start) |

## Requirements

- macOS 14+
- Apple Silicon (M1–M5)
- Xcode / Swift 5.9+
- `ffmpeg` (to prepare the sample clip)

## Custom audio

```bash
ffmpeg -i your_clip.wav -t 10 -ac 1 -ar 16000 bench/clips/my_clip.wav
./bench.sh bench/clips/my_clip.wav
```

## Models tested

| Model | HuggingFace |
|-------|-------------|
| 0.6B MLX-4bit | [aufklarer/Qwen3-ASR-0.6B-MLX-4bit](https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit) |
| 0.6B MLX-8bit | [aufklarer/Qwen3-ASR-0.6B-MLX-8bit](https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-8bit) |
| 1.7B MLX-4bit | [aufklarer/Qwen3-ASR-1.7B-MLX-4bit](https://huggingface.co/aufklarer/Qwen3-ASR-1.7B-MLX-4bit) |
| 1.7B MLX-8bit | [mlx-community/Qwen3-ASR-1.7B-8bit](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit) |
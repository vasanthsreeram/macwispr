---
license: cc-by-4.0
language: [en, de, fr, es, it, pt, ru, uk, hr, sl, lv, lt, et, fi, sv, da, nl, pl, cs, sk, hu, ro, bg, el, mt]
pipeline_tag: automatic-speech-recognition
tags: [ternary, parakeet, tdt, speech-recognition, cpu, apple-silicon]
---

# Moondream Parakeet Redux

A 1.58-bit version of [parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Same architecture,
same tokenizer, but every encoder weight is -1, 0 or +1. It fits in 178 MB, runs at 113× real
time on eight x86 CPU cores, 2.5× the fastest other Parakeet runtime we measured, and stays within 0.3 WER of the
original on English while beating it on the 25-language FLEURS set and on long-form audio.

| | parakeet-tdt-0.6b-v3 | parakeet-redux |
|---|---|---|
| Open ASR Leaderboard, 7 English sets (WER %) | **6.26** | 6.55 |
| FLEURS, 25 languages (WER %) | 11.62 | **10.56** |
| Business speech, AA-WER style (WER %) | **6.15** | 6.96 |
| Background noise, 9 MUSAN conditions (WER %) | **6.72** | 9.04 |
| TED-LIUM long-form (WER %) | 2.71 | **2.51** |
| Weights | 1.2 GB | **178 MB** |

Its sibling [Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra) is the full-precision version of the
same architecture, trained further, for GPUs: better than the original on every benchmark. Read the
[release post](https://moondream.ai/blog/introducing-parakeet-redux-and-ultra) for the story behind both models.

## Usage

Run it with [Photon](https://moondream.ai/photon), which reads the packed weights directly: AVX-512 VNNI on x86,
NEON on ARM, Metal on Apple GPUs. Every speed number on this page is Photon.

```python
# pip install moondream  (2.4.0 or later)
import moondream as md

# device: "cpu", "mps" or "cuda"; leave it out to take CUDA,
# then Apple silicon, then the CPU
with md.photon("moondream/parakeet-redux", device="cpu") as speech:
    result = speech.transcribe(audio="speech.wav")
    print(result["text"])
    # From the undersurface of the clouds there are continual
    # emissions of lurid light. Electric matter is in continual
    # evolution from their component molecules. The gaseous ...

    # timestamps="segment": one entry per sentence, with its start
    # and end in seconds
    result = speech.transcribe(audio="speech.wav", timestamps="segment")
    for segment in result["segments"]:
        print(segment["start"], segment["end"], segment["text"])
    # 0.32 5.12 From the undersurface of the clouds there are ...
    # 5.12 9.92 Electric matter is in continual evolution from ...
    # 9.92 21.04 The gaseous elements of the air need to be ...

    # timestamps="word": the same sentences, each with the start
    # and end of every word
    result = speech.transcribe(audio="speech.wav", timestamps="word")
    for word in result["segments"][0]["words"][:3]:
        print(word["start"], word["end"], word["word"])
    # 0.32 0.56 From
    # 0.56 0.72 the
    # 0.72 1.44 undersurface
```

## Performance

Real-time factor: seconds of audio transcribed per second of wall clock, one utterance at a time, higher is
faster. The other rows are the fastest other ways we found to run Parakeet on the same machine and the same audio.

### How this was measured

One utterance at a time. Incumbents: parakeet.cpp (ggml), sherpa-onnx and onnx-asr (ONNX Runtime) and, on the
Mac, parakeet-mlx, each at its own defaults. x86: LibriSpeech test-clean (2,620 utterances), every runtime on the
same 8 cores. Apple silicon: a 50-utterance slice of LibriSpeech dev-clean, with cool-downs between runs. WER is
scored the same way as the benchmarks below.

### x86 CPU

AMD EPYC 9575F (Zen 5, up to 5.0 GHz, AVX-512), 8 physical cores of one chiplet, DDR5-6000, Ubuntu 22.04.

| runtime | weights | real time | WER |
|---|---|---|---|
| **Photon, this model** | ternary, 178 MB | **113×** | 1.94 |
| parakeet.cpp (ggml) | q8_0, 0.94 GB | 45× | 1.51 |
| sherpa-onnx (ONNX Runtime) | int8, 0.67 GB | 42× | 1.97 |
| onnx-asr (ONNX Runtime) | int8, 0.67 GB | 28× | 1.93 |

### Apple silicon

MacBook Air with the Apple M2 (4 performance and 4 efficiency CPU cores, 10-core GPU), 16 GB unified memory, macOS 15.

| runtime | weights | CPU | GPU |
|---|---|---|---|
| **Photon, this model** | ternary, 178 MB | **38×** | **43×** |
| parakeet.cpp (ggml) | q8_0, 0.94 GB | 12× | 38× (Metal) |
| parakeet.cpp (ggml) | f16, 1.44 GB | 9× | 39× (Metal) |
| parakeet-mlx | fp32, 2.51 GB | — | 37× |
| onnx-asr (ONNX Runtime) | int8, 0.67 GB | 33× | — |
| sherpa-onnx (ONNX Runtime) | int8, 0.67 GB | 28× | — |

## Benchmarks

Word error rate in percent, lower is better. parakeet-redux is better than the original on FLEURS and on
long-form audio, close to it on English, and behind it in noise. Both models are scored on the same files with the
Open ASR Leaderboard's own pipeline as of September 2026 (its normalizers and compound-merging alignment, with the
FLEURS references prepared as the leaderboard's text column is). parakeet-redux runs in Photon on an NVIDIA GPU, the
original in NeMo in bf16.

### Open ASR Leaderboard

The seven English test sets of the Hugging Face Open ASR Leaderboard: audiobooks (LibriSpeech), meetings (AMI),
earnings calls (Earnings-22), podcasts and YouTube (GigaSpeech), financial calls (SPGISpeech) and parliament
(VoxPopuli).

| set | parakeet-tdt-0.6b-v3 | parakeet-redux |
|---|---|---|
| LibriSpeech test-clean | 1.52 | 1.96 |
| LibriSpeech test-other | 3.13 | 4.34 |
| AMI | 10.86 | 10.80 |
| Earnings-22 | 10.75 | 9.95 |
| GigaSpeech | 8.05 | 8.73 |
| SPGISpeech | 3.63 | 4.01 |
| VoxPopuli | 5.88 | 6.07 |
| **average** | **6.26** | **6.55** |

### FLEURS

The FLEURS test split: read Wikipedia sentences, a few hundred per language, for all 25 languages the model
supports.

| language | parakeet-tdt-0.6b-v3 | parakeet-redux |
|---|---|---|
| Bulgarian | 11.90 | 11.23 |
| Croatian | 10.93 | 9.26 |
| Czech | 10.85 | 10.25 |
| Danish | 16.78 | 15.94 |
| Dutch | 6.18 | 7.45 |
| English | 4.25 | 4.90 |
| Estonian | 13.23 | 9.15 |
| Finnish | 11.05 | 10.38 |
| French | 4.81 | 7.71 |
| German | 4.13 | 5.42 |
| Greek | 35.71 | 32.48 |
| Hungarian | 13.65 | 14.15 |
| Italian | 2.61 | 3.24 |
| Latvian | 21.38 | 12.80 |
| Lithuanian | 21.09 | 17.27 |
| Maltese | 19.13 | 13.65 |
| Polish | 6.70 | 8.59 |
| Portuguese | 4.65 | 4.99 |
| Romanian | 11.54 | 10.32 |
| Russian | 5.91 | 7.91 |
| Slovak | 9.46 | 7.26 |
| Slovene | 21.76 | 16.21 |
| Spanish | 3.12 | 3.71 |
| Swedish | 13.75 | 12.71 |
| Ukrainian | 5.94 | 7.06 |
| **average** | **11.62** | **10.56** |

### Business speech (AA-WER style)

The AMI and VoxPopuli test sets with the Artificial Analysis cleaning applied, and Earnings-22 scored in 30-second
chunks joined per call, the way the AA-WER benchmark does it.

| set | parakeet-tdt-0.6b-v3 | parakeet-redux |
|---|---|---|
| AMI (cleaned) | 9.52 | 9.14 |
| VoxPopuli (cleaned) | 3.02 | 3.86 |
| Earnings-22, 30-second chunks | 5.90 | 7.89 |
| **average** | **6.15** | **6.96** |

### Background noise

The clean sets with MUSAN noise (the half of the corpus not used for training) mixed in at a fixed signal-to-noise
ratio; 0 dB means the noise is as loud as the speech.

| set | parakeet-tdt-0.6b-v3 | parakeet-redux |
|---|---|---|
| LibriSpeech test-other, 10 dB | 4.12 | 5.66 |
| LibriSpeech test-other, 5 dB | 5.49 | 7.32 |
| LibriSpeech test-other, 0 dB | 9.06 | 10.95 |
| FLEURS German, 10 dB | 5.78 | 8.97 |
| FLEURS German, 5 dB | 8.07 | 12.36 |
| FLEURS German, 0 dB | 14.45 | 19.18 |
| FLEURS Spanish, 10 dB | 3.99 | 4.46 |
| FLEURS Spanish, 5 dB | 4.12 | 5.25 |
| FLEURS Spanish, 0 dB | 5.44 | 7.22 |
| **average** | **6.72** | **9.04** |

Noise is where the gap to the original is widest: the ternary encoder's acoustic margin is thinner, and at low SNR
it substitutes similar-sounding words more often. Dropped or invented content is not more frequent than the
original's.

### Long-form

Eleven complete TED-LIUM 3 talks of 10-20 minutes each. parakeet-redux transcribes them through Photon, whose
segmenter cuts each talk at pauses found by the model's VAD head into segments of at most 30 seconds; the original
runs NeMo's own long-audio path.

| set | parakeet-tdt-0.6b-v3 | parakeet-redux |
|---|---|---|
| TED-LIUM 3, 11 full talks of 10-20 minutes | 2.71 | 2.51 |

## Notes

- Based on [parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) by NVIDIA. Languages,
  tokenizer and output conventions (punctuation, casing, numerals) are the original's.
- Runs with [Photon](https://moondream.ai/photon).
- Long audio is segmented by the model itself: the weights carry a small voice-activity head on the encoder's
  subsampler, and Photon uses it to cut recordings at pauses into segments of at most 30 seconds. No external VAD
  model is needed.
- License is CC-BY-4.0, same as the original.

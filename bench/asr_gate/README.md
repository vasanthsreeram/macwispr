# ASR gate

Pass/fail check for changing the speech engine (for example Photon → Core ML on the
Neural Engine, or a new model conversion). One command runs the same 126 audio clips
through an engine, using the app's own 28 s windowing and overlap stitching, and checks
accuracy, speed, and memory against `criteria.json`.

```bash
bench/asr_gate/run.sh photon                     # record the baseline (current 1.3.0 engine)
bench/asr_gate/run.sh coreml                     # Parakeet v3 Core ML INT8 via speech-swift
bench/asr_gate/run.sh coreml --model-dir DIR --name redux-ane   # any converted Core ML Parakeet
```

Exit code 0 means PASS. Reports go to `bench/results/asr_gate/` (gitignored).
`prepare.sh` downloads LibriSpeech test-clean (~350 MB) once and makes the
multilingual clips with macOS `say`.

## Test set (`manifest.json`, committed)

| Set | Clips | What it covers |
|---|---|---|
| `english` | 100 | LibriSpeech test-clean, ~3–20 s: normal dictation length |
| `english_long` | 8 | 23–35 s single utterances: crosses the 28 s window edge |
| `longform` | 2 | Joined utterances, 77 s and 193 s: windowing + stitching |
| `multilingual` | 15 | French, German, Spanish, Italian, Portuguese (3 each, `say` voices) |
| `silence` | 1 | 3 s of silence: must produce no words |

`make_manifest.py` regenerates the manifest deterministically. Changing it invalidates
old reports, so re-record the baseline after.

## Pass criteria (`criteria.json`)

A candidate passes only if **every** check passes.

| Check | Limit | Why |
|---|---|---|
| English WER | ≤ 3.5 %, and ≤ baseline + 0.75 pt | Everyday dictation must not get noticeably worse |
| English long WER | ≤ 6 %, and ≤ baseline + 1 pt | Clips that span two windows |
| Long-form WER | ≤ 3 %, and ≤ baseline + 1.5 pt | Dropped or repeated speech across windows |
| Multilingual WER | ≤ 5 %, and ≤ baseline + 2 pt | The 25-language promise |
| Silence | 0 words | No invented text when nobody speaks |
| Latency p50 / p95 (english) | ≤ 300 ms / ≤ 1 s | Release-to-text feels instant |
| Long-form real-time factor | ≤ 0.05 | 3 min of speech finalizes in under 9 s |
| Peak memory | ≤ 1,200 MB | Goal of the engine swap; current Photon peaks ~2.6 GB |
| Idle memory (model loaded) | ≤ 1,000 MB | |
| Load + first call | ≤ 15 s | Cached model, not first download |

WER normalizes case, accents, and punctuation the same way for every engine.

**Memory** counts the process holding the model. For Core ML it also adds the growth in
system wired memory, because Neural Engine weights are wired by the kernel and do not
show in the process footprint (about 680 MB for Parakeet v3 INT8).

## Results on this Mac (M-series Air, 32 GB, 2026-10-15)

| | Photon / Redux (shipping) | Core ML / Parakeet v3 INT8 |
|---|---|---|
| English WER | 2.15 % | 2.58 % |
| English long WER | 3.97 % | 3.82 % |
| Long-form WER | 0.58 % | **7.40 % FAIL** |
| Multilingual WER | 1.31 % | 0.00 % |
| p50 / p95 latency | 189 / 646 ms | 142 / 436 ms |
| Peak memory | **2,602 MB FAIL** | 859 MB |
| Result | 10/11 | 10/11 |

Core ML v3 fails long-form because some 28 s windows drop or repeat a sentence near the
window edge; the shipped Photon path does not. Short dictation is fine on both.

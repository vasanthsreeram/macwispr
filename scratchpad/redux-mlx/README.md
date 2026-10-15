# Redux → MLX handoff

## Status and files

A real packed-weight MLX runtime transcribes audio end to end. **Strict parity acceptance remains failing on near-silent preprocessing.** The Swift app now has an explicit experimental bridge to a persistent Python MLX process, with runtime selection and memory diagnostics. Model operations remain in Python; a native Swift model implementation is unfinished. Local app-engine tests matched all 41 valid corpus transcripts and the expected short-input rejection. See [`APP_INTEGRATION.md`](APP_INTEGRATION.md) for application evidence and remaining UI checks.

The converted weight-only package is public at [vasanth009/parakeet-redux-mlx](https://huggingface.co/vasanth009/parakeet-redux-mlx), following explicit approval. All eleven remote files were downloaded anonymously and matched trusted local hashes; [`publishing/published-verification.json`](publishing/published-verification.json) records commit `6b9303a5de7f427bb8d711ec7c0ff0442beec28d`. Runtime implementation code was excluded. Application changes remain local and uncommitted. The installed `/Applications/MacWispr.app` and its runtime preferences remain unchanged; replacement was not confirmed.

- Implementation and reproduction commands: [`../../bench/redux_mlx/README.md`](../../bench/redux_mlx/README.md).
- Final evidence: [`results-final.json`](results-final.json), [`app-parity-final.json`](app-parity-final.json), [`tensor-parity-final.json`](tensor-parity-final.json), [`tests-final.log`](tests-final.log), and `perf-*-final.json`.
- Runtime binary/footprint pins: `environment-{mlx,photon}-v2.json`. Near-floor diagnosis: `quiet-diagnostics-v2.json`.
- Ignored local artifacts: `bench/results/redux_mlx/{converted,corpus-v2,reference-v2,candidate-final}`. Retain the WAVs for exact replay. Unsuffixed and other versioned reports are earlier experiments.

The port includes lossless base-3 → affine-2-bit conversion, NumPy features, the complete FastConformer, LSTM predictor, joint head, greedy token/duration decoder and app-style 28-second/2-second-overlap windowing. All 264 trained ternary matrices and 465 other decoded tensors match the original export. Saved-artifact loading authenticates all 993 tensors and works without original weights, Torch or Photon. Standalone inference was also exercised with none of those original runtime modules imported.

## Pins and tested coverage

Model: `moondream/parakeet-redux`, revision `2bf128600aac4b16946f7ed8372e56117fe5e23b`. Original weights SHA256: `78ec25733ee0d0c1586d1346fc86db9d0c2e436e3a8ab1d32a82d1bb8f848d21`. Converted weights SHA256: `03f41729b69807deec2d3bb7dc7d45f5c0285d781fd598c4c4a848079cf1a0d9`.

Reference: moondream 2.6.1, kestrel 0.9.1, kestrel-kernels 0.7.4, kestrel-native 0.1.8, Torch 2.14.1, canonical MPS/FP16. Candidate: MLX 0.31.2. Full dependency, model, tokenizer, source/native binary, corpus and implementation hashes are retained in the code's pin files and final summary. Final report fingerprints were verified against current code.

Hardware: Apple M5, 32 GiB, macOS 26.6.2 arm64. Corpus: 42 cases / 285.875 seconds, including 20 English read utterances from one speaker/chapter, 7 synthetic speech clips (English, French, German, Spanish, Italian, Portuguese), 12 boundary/silence/impulse probes, 2 quiet PCM16 probes and one 101.740-second concatenated English recording. This is smoke coverage.

## Final parity results

| Check | Result |
|---|---|
| Independent app-window transcripts | **41/41 valid cases exactly matched (100%)** |
| Expected 319-sample rejection | Matched in both wrappers; native Photon rejection also captured |
| Inter-engine WER / CER | **0 / 0** on this corpus |
| Known-reference app-window accuracy, both engines | WER **7/728 = 0.9615%**; CER **10/3294 = 0.3036%** |
| Native reference-segment token / duration / frame paths | **44/44 exactly matched**, each category |
| Aligned vocabulary / duration argmax | **2046/2046 matched**, each domain |
| Tensor acceptance | **4 failed checks on 2 quiet cases** |
| Tests | **75 passed, 1 failed**, out of 76; metric/artifact self-tests passed |

The scorer now requires the hash-verified corpus/audio, complete cases, matching metadata and canonical window bounds including the final remainder. Thirty CPU-only scorer tests cover shared omissions and malformed reports. Native-segment known-reference WER/CER are slightly different (6/728 words, 9/3294 characters) because native Photon segmentation differs from fixed app windows.

The unchanged predeclared diagnostic profile requires features allclose `2e-4/2e-4`, activation/logit cosine ≥0.999 and normalized L2 ≤0.02, aligned KL mean ≤0.001 and max ≤0.01, plus exact paths/text. Speech features and all aligned logit gates pass. Speech projected-encoder minimum cosine is `0.999994052`; vocabulary KL max is `0.000236666`, duration KL max `0.00859973`.

`quiet-pcm16` fails normalized features (max absolute error `0.200368`), subsampling normalized L2 (`0.0221272`) and layer-0 normalized L2 (`0.0263529`). `quiet-low` fails feature allclose. The separate floating-point quiet-noise unit probe fails with max normalized-feature difference `0.3542853`. These failures remain unsuppressed. Full reports retain max/mean absolute/relative errors and cosine; KL uses separately aligned vocabulary/duration distributions.

Near-floor log/mean rounding of roughly one or two FP32 ULPs is amplified by the small standard deviation and normalization epsilon. Even identical original log-mel values fed through the candidate mean reduction leave about `0.0972` normalized-feature difference in one quiet case. Native MLX log/mean variants also missed the gate. No unsupported ternary operation blocked execution; exact opaque Photon kernel rounding remains unproven.

## Final performance and footprint

| Metric | Photon | MLX |
|---|---:|---:|
| 4.224 s French — cached-weight cold | 3.934 s | 0.697 s |
| 4.224 s French — warm median, 7 calls | 0.080 s | 0.131 s |
| 101.740 s English — cached-weight cold | 6.030 s | 1.973 s |
| 101.740 s English — warm median, 3 calls | 2.406 s | 1.704 s |
| Long-input peak active GPU | 269.9 MB | 403.4 MB |
| Long-input process peak RSS | 882.0 MB | 619.3 MB |
| Runtime logical disk bytes, excluding weights | 775.2 MB | 294.3 MB |
| Weight safetensors | 177.8 MB | 207.9 MB |

Cold includes imports, integrity checks, loading and first inference; interpreter startup is excluded and OS/Metal caches are unpurged. Photon active memory is a 5 ms sampled lower bound; MLX reports allocator high-water. Memory covers loading through inference. Photon rereads prepared WAVs inside timed calls; MLX receives decoded samples. These are development pipeline measurements with variable timings and different allocator counters. Runtime footprint describes these Python installations, excluding OS frameworks, and does not establish native installer size. All repeated transcripts agree within and across engines.

## Remaining work and access history

Resolve near-floor preprocessing parity; expand human multilingual/noisy/conversational and hour-scale coverage; implement and validate native Swift features/tokenizer/decoder/model operations, including compatibility with the app's pinned Swift MLX version. Native Photon VAD-driven long-form segmentation and batching remain unvalidated in the candidate. Separate runtime-code distribution rights remain unresolved.

Earlier macOS access denials affected the broader 126-case fixture tree, two optional feature-test WAVs, Git inspection and `Package.swift`. After the owner granted filesystem access, Git, the package and Swift builds became accessible. The original parity report remains tied to its retained 42-case corpus. Keep Photon as reference/fallback and obtain separate approval before replacing the installed app or publishing an application release.

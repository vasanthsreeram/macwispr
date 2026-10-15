# Weight-only publication handoff

## Published release

The owner approved creation and public upload to [vasanth009/parakeet-redux-mlx](https://huggingface.co/vasanth009/parakeet-redux-mlx). The verified package was uploaded in commit [`6b9303a5de7f427bb8d711ec7c0ff0442beec28d`](https://huggingface.co/vasanth009/parakeet-redux-mlx/commit/6b9303a5de7f427bb8d711ec7c0ff0442beec28d). Anonymous HTTPS downloads of all eleven files matched the trusted local byte counts and SHA256s. The remote contains those files and Hugging Face's generated `.gitattributes`. See [`published-verification.json`](published-verification.json).

The sections below record the earlier preparation-only phase. Runtime code remains excluded, and runtime distribution rights remain unresolved. Installed application replacement was requested separately and remains unapproved.

## Preparation record

The local package is staged at `bench/results/redux_mlx/hf-release`. It contains 11 regular files totaling **209343750 bytes**. Preparation, verification, and safe-rerun checks passed. No repository creation, upload, credential access, build, package installation, or inference was performed. Only public unauthenticated source-card and legal-text requests were made during authoring. The preparation script itself has no network behavior.

Implementation, templates, instructions, and focused tests are in `bench/redux_mlx/publishing`. This handoff directory contains local evidence only. Neither publishing source directory belongs in the Hugging Face payload. The explicitly requested staging directory is the only write exception outside those source directories. Existing benchmark core files and original handoff evidence were not modified.

## Exact staged contents

| File | Bytes |
|---|---:|
| model.safetensors | 207858007 |
| config.json | 12988 |
| tokenizer.json | 1159960 |
| ternary.json | 57970 |
| conversion.json | 869 |
| packed_tensors.json | 219801 |
| source-model.json | 2815 |
| parity-summary.json | 2733 |
| README.md | 8189 |
| LICENSE | 18657 |
| release-manifest.json | 1761 |
| Total | 209343750 |

`staged-inventory.json` records SHA256 for all eleven files. The release manifest SHA256 is `9044fc7a75cce26108510caa07810d60897a9ca2ba346240bef9cc4cda300bbc`. Converted weights retain SHA256 `03f41729b69807deec2d3bb7dc7d45f5c0285d781fd598c4c4a848079cf1a0d9`. Independent packed tensor pins retain SHA256 `cd74909c621e6c5b1349bd604a8a2d51cfbcfc2d07fa71189f5240a6e11c6f73`.

No Python, Photon, Kestrel, native binary, audio, raw transcript, private report, or dependency environment is staged. Source metadata and tokenizer are byte-identical to the pinned upstream export. The custom model card states that the package is experimental, not a drop-in AutoModel or MLX Audio checkpoint, and not proof of identical floating-point execution. Runtime-code licensing remains unresolved and no runtime code is included.

## License evidence

The authoritative [Redux model card at the pinned revision](https://huggingface.co/moondream/parakeet-redux/raw/2bf128600aac4b16946f7ed8372e56117fe5e23b/README.md) declares `cc-by-4.0` and credits [NVIDIA parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Its raw bytes are retained as `upstream-card.md`, with SHA256 `930055e6bac7d75114e719850ffaffc8d327e73b4295518c38c81399acd63e46`.

The package's full, unmodified license text came from <https://creativecommons.org/licenses/by/4.0/legalcode.txt>. The license overview is <https://creativecommons.org/licenses/by/4.0/>. The legal text has 18657 bytes and SHA256 `9ba9550ad48438d0836ddab3da480b3b69ffa0aac7b7878b5a0039e7ab429411`. All eight sections and the final CC notice are present. `source-fetch.json` records the source URLs and byte digests.

The public card credits both NVIDIA and Moondream. It preserves the source model, pinned card, release post, Ultra, and Photon links. It describes the local modification as lossless packing that preserves trained ternary values, original scales, and other tensors, without calibration, retraining, or requantization. No separately consumed NVIDIA checkpoint revision is invented. The exact consumed checkpoint is the pinned Moondream Redux export.

## Verification evidence

`tests.log` records **19 focused tests passing**. The tests exercise the actual 993-tensor artifact and smaller adversarial safetensors fixtures. They cover independent tensor authentication after a container rehash, changed names, shapes and dtypes, invalid ranges, overlapping ranges, trailing bytes, duplicate JSON keys, unknown and partial directories, symlinks, extra runtime files, modified manifests, summary privacy, explicit publication arguments, and print-only manual commands.

`staging.json` records initial creation. `verification.json` records a successful `python3 -I -S -B` verification. `rerun.json` records an existing-known-release verification with no writes. Tests also confirm unchanged file mtimes on rerun and verification from an unrelated working directory with an empty environment and no site packages. Original weights and third-party runtimes are unnecessary. The verifier checks fixed file hashes and every saved tensor's independent logical-byte digest, not merely a self-generated container manifest.

`scope-and-privacy-proof.json` records all 21 benchmark source pins matching the original final report and all 12 supporting original handoff evidence hashes matching. Public metadata and the unchanged tokenizer pass user-path scans. The public summary is only 2733 bytes and contains aggregate results, evidence hashes, and failure descriptions. It contains no audio or transcript text.

The public summary retains 41/41 valid-case exact transcripts, one expected rejection, and 44/44 exact token, duration, and frame paths. Strict tensor acceptance still fails on four checks across two quiet probes. The original implementation test suite still has one quiet-feature failure, with 75 of 76 passing. These are pinned prior results, not newly run inference results.

## Reproduce and print a manual plan

From the repository root, run the following local commands:

```sh
python3 -I -S -B bench/redux_mlx/publishing/prepare.py prepare
python3 -I -S -B bench/redux_mlx/publishing/prepare.py verify
python3 -B -m unittest discover -s bench/redux_mlx/publishing -p 'test_*.py' -v
python3 -I -S -B bench/redux_mlx/publishing/prepare.py manual-commands \
  --repo-id YOUR_NAMESPACE/YOUR_NEW_MODEL_NAME --visibility private
```

The final command only prints commands. It requires an explicit repo ID and `private` or `public` visibility. It never executes a Hugging Face operation. `manual-command-example.txt` is a private-visibility example for a fictitious destination, not an approved destination. A human must approve the exact artifact and visibility, choose an owned new repository, inspect the printed commands, authenticate separately, verify again, and manually execute them. No upload approval was inferred. A public plan requires `--visibility public` explicitly.

## Decisions and open work

A fixed file-pin registry was chosen over a manifest that merely blesses whatever files are present. Model the Domain shaped that registry. Build the Lever produced the reproducible preparer. Prove It Works shaped verification against the real artifact. Make Operations Idempotent shaped verified no-write reruns and refusal of unknown directories. Test Behavior, Not Implementation shaped the corrupt-artifact and command-boundary tests.

The throughput checkpoint kept source-format and license research ahead of implementation. Those read-only checks ran independently. One worker owned the coupled specification, verifier, templates, and tests because nested subagent tools were unavailable. Shared output writes were serialized. No commits, rebases, PRs, builds, or remote publication were in scope.

The remaining publication decisions are the owner's approval, destination repo ID, and private or public visibility. Runtime-code redistribution rights remain unresolved. Numerical quiet-case failures, broader speech coverage, native VAD segmentation, and native application integration remain outside this weight-only preparation. Remote command execution and remote byte verification remain unperformed by design. Hashes are trust-anchor-relative integrity checks, not cryptographic signatures.

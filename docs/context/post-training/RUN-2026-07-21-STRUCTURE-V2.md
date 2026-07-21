# Run log — structure-v2 post-training (2026-07-21)

Full record of the Qwen3.5-0.8B polish post-training run on the Mac Studio
(`hcserver@100.64.0.4`, M3 Ultra 96 GB). Everything here is reproducible from
`bench/polish_posttrain/` — the pipeline, verifier, eval suite, and reward code
are all in this repo (open source).

## Pipeline

SFT (2400 iters) → fuse → OOD eval → DPO (gold-vs-flat pairs) → eval →
GRPO on hard tags (gated) → best-checkpoint gate → 4-bit quant → eval →
compare vs Claude Sonnet on the shared 40-case OOD suite
(`ood_eval_set.jsonl`, scored by `polish_verifier.py` — same rules as training).

## What happened, stage by stage

| Stage | OOD pass (fp16) | Notes |
|---|---|---|
| SFT (structure-v2, 2400 iters) | **22/40 (55%)** | Clean run, train loss 2.0→1.66, `TRAIN_OK` |
| + DPO (220 pairs, 400 iters) | 20/40 (50%) | **Regression** — checklist 2/4→0/4, mixed 4/8→2/8 |
| + GRPO (first attempt) | — | **Crashed**: `KeyError: 'answer'` (see bugs below) |
| DPO 4-bit (originally shipped to bench) | 19/40 (48%) | Wrong checkpoint got quantized |
| **SFT 4-bit (re-quant, honest best)** | **23/40 (57.5%)** | vs Claude Sonnet 25/40 (62.5%), at 191 ms vs 4407 ms |

Re-scored comparison (Claude outputs cached, no re-run):
`bench/polish_posttrain/results/bench_vs_claude_sonnet_v2.{json,md}`.

## Bugs found and fixed

1. **GRPO data contract** — `mlx_lm_lora`'s `GRPODataset` requires `answer`
   per row (plus optional `system`, `type`); the pipeline only wrote `prompt`.
   Fixed in `run_pipeline.sh` (rows now carry gold answer, a polish system
   prompt overriding the default R1 `<think>/<answer>` one, and tags in `type`).
2. **GRPO reward** — defaults were R1 math-style (`<answer>` extraction),
   meaningless for polish. Added `grpo_rewards.py` registering `polish_reward`
   (scores completions with `polish_verifier.verify`), wired via
   `--reward-functions-file` / `--reward-functions`.
3. **No regression gate** — the pipeline quantized DPO unconditionally.
   Now it picks max pass-rate among SFT/DPO/GRPO before quantizing.

## DPO post-mortem

Pairs were ~all "gold vs flattened-gold" (plus best-of-8 sampling), so DPO only
taught *don't flatten* — and collapsed structural variety (checklists, mixed
styles) as collateral. Lesson: preference negatives must be structure-diverse
(wrong list type, merged lists), not a single failure mode.

## In flight

`run_grpo_on_sft.sh` — standalone GRPO (300 iters, LoRA rank 8, group size 4,
`polish_reward`) on the SFT checkpoint, trained only on hard-tag prompts
(multi_list / mixed_styles / numbered / checklist). Self-gating: fuses, evals,
and only quantizes + rebuilds the Sonnet comparison (`…_v3`) if it beats SFT's
57.5%. Known risk: `mlx_lm_lora` GRPO wraps prompts in the chat template while
eval uses raw `### Input:` completion format — the gate protects against this.

## Next levers (ordered)

1. Fresh hard-tag SFT/RL data (few hundred multi-list + numbered examples with golds)
2. Structure-diverse DPO negatives
3. Verifier audit for `format_checklist` (Sonnet also scores 0/4 — likely a
   `- [ ]` scoring rule neither model satisfies)

## Artifacts (on hcserver)

- `~/macwispr-polish-bench/fused/qwen35-08b-polish-structure-v2{,-4bit,-dpo,-dpo-4bit,-grpo2*}`
- Logs: `~/macwispr-polish-bench/logs/` (`structure_sft_v2_*.log`, `grpo2_run.log`, `pipeline_*.log`)
- Results: `~/macwispr-polish-bench/results/` (synced into `bench/polish_posttrain/results/`)

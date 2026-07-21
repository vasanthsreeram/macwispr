# Execution checklist — polish full-scale SFT + post-training

**Track here:** `docs/context/post-training/plans/EXECUTION-CHECKLIST.md`
**Date started:** 2026-07-21
**Hardware:** Mac Studio M3 Ultra 96 GB (`hcserver@100.64.0.4`), env `~/.cache/macwispr-minicpm-bench/.venv312` (Python 3.12, mlx-lm 0.31.3)
**Benchmarked sweet spot:** batch 4 ≈ 212 tok/s, 37 GB peak (M5 local: batch 1 only, 133 tok/s)

## Phase 0 — Setup
- [x] Studio env: uv + Python 3.12 venv + mlx-lm 0.31.3
- [x] Dataset synced: `bench_sync/qwen35_structure_sft` (3,011 train / 276 val / 173 test)
- [x] Batch sweep done → **batch 4** chosen
- [x] Enum init on Studio (skip rsync): `~/macwispr-polish-bench/fused/qwen35-08b-polish-enum` (1.4 GB complete). Partial DERP copy removed.

## Phase 1 — Full-scale structure SFT (the 0.2-epoch fix)
Old run: ITERS=600 × batch 1 = 600 examples = **0.2 epochs** (root cause of "too fast" + weak multi_list).
- [x] **Completed** on Studio 2026-07-21: `BATCH=4 ITERS=2400 LR=3e-6 MAX_SEQ=1024`, init = enum, full SFT
  - Script: `~/macwispr-polish-bench/scripts/train_structure_sft_v2.sh`
  - Log: `~/macwispr-polish-bench/logs/structure_sft_v2_20260721_011406.log` → **TRAIN_OK**
  - Trainable: 44% (332M/752M) via mlx full FT + default 16 layers; peak mem ~50 GB; ~220 tok/s
  - Val: 2.477 → ~1.66 train loss @ 2400
  - Adapter: `~/macwispr-polish-bench/adapters/qwen35-08b-polish-structure-v2`
  - Fuse: `~/macwispr-polish-bench/fused/qwen35-08b-polish-structure-v2` (bf16, 1.4 GB)
- [x] Watch val loss every 50 steps (saved every 100); used final adapters for fuse
- [x] Fuse → structure-v2 bf16

## Phase 2 — Test sets + eval (before/after gate)
- [x] OOD eval bank: `bench/polish_posttrain/ood_eval_set.jsonl` (40 cases)
- [x] Shared verifier: `bench/polish_posttrain/polish_verifier.py`
- [x] Eval runner: `bench/polish_posttrain/eval_ood.py`
- [x] Baseline structure-4bit: **21/40 = 52.5%** — multi_list 3/8, mixed 3/8, numbered 0/4; mean 231 ms
- [x] Post-SFT v2 bf16: **22/40 = 55.0%** — multi_list 1/8, mixed 4/8, numbered 1/4; mean 255 ms

## Phase 3 — Post-training (RL)
- [x] Gen DPO pairs: best-of-8 @ T=0.9 → **139** ranked pairs + **81** gold_vs_flat = **220** total (`dpo_pairs.jsonl`)
- [x] Install mlx-lm-lora 3.0.0; DPO train LoRA (loss 0.38 → **0.01** by iter ~170)
  - **Abort trap 6** at iter ~175/400 (Metal); recovered **adapters @ save-every-100**
  - Fuse: `…/fused/qwen35-08b-polish-structure-v2-dpo`
- [x] Eval v2-dpo: **20/40 = 50%** — multi_list 1/8, mixed 2/8, bullets 4/4; mean 247 ms
- [x] GRPO attempted (gates <80%); **blocked** (mlx-lm-lora GRPO dataset/reward config exit 1) — see `results/grpo_blocked.txt`

## Phase 4 — Ship candidate
- [x] Quantize DPO fuse → `…/qwen35-08b-polish-structure-v2-dpo-4bit` (~424 MB, 4.5 bpw)
- [x] Re-run OOD on 4-bit: **19/40 = 47.5%** — multi_list 2/8, mixed 1/8, leak=0, mean **200 ms**
  - **Ship gates multi_list/mixed ≥80%: FAIL** (honest). leak=0 and latency ≲400 ms: **PASS**
- [x] Sync pack to MacBook: `~/.cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-structure-v2-dpo-4bit`
  - App symlink: `~/Library/Application Support/MacWispr/PolishModel` → that path
- [x] Update FINDINGS.md with results
- [x] Vibe test (6 hand prompts): **6/6 PASS** on 4-bit (multi_list, mixed, numbered, question, email, prose)

## Results log
| Stage | Model | OOD pass | multi_list | mixed | Notes |
|---|---|---|---|---|---|
| baseline | structure-4bit (old) | 21/40 (52.5%) | 3/8 | 3/8 | numbered 0/4; 231 ms |
| post-SFT | structure-v2 bf16 | 22/40 (55%) | 1/8 | 4/8 | 3.2 epochs full train; 255 ms |
| post-DPO | structure-v2-dpo bf16 | 20/40 (50%) | 1/8 | 2/8 | DPO@100 ckpt after abort; bullets 4/4 |
| ship 4-bit | structure-v2-dpo-4bit | 19/40 (47.5%) | 2/8 | 1/8 | leak 0; **200 ms**; gates multi/mixed **FAIL** |
| vibe | same 4-bit | 6/6 hand | pass | pass | hand prompts simpler than OOD bank |

## Artifacts (Studio)
- SFT fuse: `~/macwispr-polish-bench/fused/qwen35-08b-polish-structure-v2`
- DPO fuse: `~/macwispr-polish-bench/fused/qwen35-08b-polish-structure-v2-dpo`
- Ship 4-bit: `~/macwispr-polish-bench/fused/qwen35-08b-polish-structure-v2-dpo-4bit`
- Results JSON: `~/macwispr-polish-bench/results/ood_*.json`
- Pipeline: `bench/polish_posttrain/run_pipeline.sh`

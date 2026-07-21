# Plan: next actions (ordered)

**Owner:** polish R&D  
**Updated:** 2026-07-21

---

## P0 — Data rebalance (before or with RL)

SFT gold has markers per tag, but **mix is wrong for generalization**.

1. Generate **marker-strict** top-up (two-pass OAuth, same as `gen_structure_sft.py`):
   - +300 hard `multi_list` (two headings, blank lines, optional num+bullets)
   - +200 `mixed_styles` (must pass has_num ∧ has_bul/check)
   - +200 `format_numbered` / +150 `format_checklist`
   - +100 `course_plus_format` (drop retracted items)
2. Reject gold if style_ok fails (stricter than today).
3. Continue full SFT from structure bf16 (e.g. 300–400 iters, LR 2–3e-6) **or** fold into RL prompts only.

---

## P1 — Offline eval harness (always)

1. Keep fixed **20+** suite in repo/cache; never train on it.
2. Score structure-4bit **and** bf16 structure side-by-side.
3. Gate releases on multi_list / mixed / leak metrics (see RL plan).

---

## P2 — Quant quality

1. Baseline = current naive 4-bit structure pack.  
2. Try **DWQ** (or GPTQ) with structure train as calibration.  
3. A/B same 20; ship winner.  
4. Only if still weak: QLoRA on 4-bit or short QAT-style continue.

---

## P3 — RL (generalization)

Follow [RL-POST-TRAINING.md](./RL-POST-TRAINING.md):

1. `polish_verifier.py` from offline scorers  
2. **DPO self-play** (fastest)  
3. Optional **GRPO** on multi_list/mixed only  
4. Re-quant + re-eval  

Paper: SFT first, outcome RL second — [refs HTML](../refs/SFT_Memorizes_RL_Generalizes_2501.17161v2.html).

---

## P4 — Product attach

1. Default dev path: App Support `PolishModel` → **structure-4bit** (not bf16).  
2. Update `PolishLocalModel` devCandidates to prefer `qwen35-08b-polish-structure-4bit` when shipping a build.  
3. HF pack rename/upload only after eval gates pass.

---

## Done recently (do not redo)

- [x] Structure taxonomy + ~3k two-pass data  
- [x] Full SFT 600 iters → structure fused  
- [x] 4-bit convert + app symlink path  
- [x] Independent 20-sample offline eval (~75%)  
- [x] Paper + findings compacted under `docs/context/post-training/`  

---

## Non-goals

- Retrain ASR  
- Merge `feat/native-lfm-polish` into stable without decision  
- Full RLHF human labeling  
- Multi-turn polish in product until latency budget allows  

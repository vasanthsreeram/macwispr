# Plan: RL post-training for polish generalization

**Status:** Plan only (not implemented)  
**Paper:** Chu et al., *SFT Memorizes, RL Generalizes* — [arXiv:2501.17161v2](https://arxiv.org/abs/2501.17161v2)  
**Mirror:** [../refs/SFT_Memorizes_RL_Generalizes_2501.17161v2.html](../refs/SFT_Memorizes_RL_Generalizes_2501.17161v2.html)

---

## Goal

Improve **OOD formatting** (multi-list, mixed numbered+bullets, hard course+format) beyond SFT memorization of synthetic shapes.

---

## Pipeline (paper-aligned)

```text
Qwen3.5-0.8B-Base
  → SFT structure (DONE: fused/qwen35-08b-polish-structure)
  → RL with outcome verifier (TODO)
  → quant 4-bit / DWQ (TODO re-eval)
  → offline OOD suite + optional app attach
```

**Do not** start RL from Base without SFT.  
**Do not** over-SFT until the model collapses on OOD before RL.

---

## Verifier (outcome reward)

Implement once; share with offline eval.

| Signal | Reward idea |
|--------|-------------|
| multi_list intent | + if ≥2 headed list blocks; − if flat single list |
| mixed_styles | + if `1.` **and** (`-` or `- [ ]`); else − |
| numbered / bullets / checklist | + style match |
| answer_leak | large − |
| over-list prose/question | − |
| item coverage | + fraction of raw content words preserved |
| residual “no wait” / “scratch that” | − |

Return `(score: float, feedback: str)` for optional sequential revision.

---

## Algorithms (pick by cost)

| Method | Effort | Notes |
|--------|--------|-------|
| **DPO** (self-play) | Lowest | chosen = gold / best-of-N; rejected = flat fail; offline |
| **GRPO** | Medium | G=4–8 samples/raw; group-relative; Sotto-like |
| **PPO multi-turn** | Highest | Closest to paper; revision history in prompt |

**Mac / mlx_lm:** no one-flag PPO. Plan: custom `train_polish_rl.py` or DPO first.

---

## Sequential revision (train-time only)

```text
attempt_0 = generate(raw)
r0, fb0 = VER(raw, attempt_0)
if r0 low:
  attempt_1 = generate(raw + prior + fb0)
  r1, fb1 = VER(...)
```

Product inference stays **single-shot** unless product adds a “reformat” pass.

---

## Data for RL

- Prompts: structure + **OOD raws** (new phrasings, domains)
- Gold optional (bootstrap / DPO chosen)
- Anti-hack mix: preserve_prose, preserve_question, light

---

## Scripts to add (cache or `bench/`)

```text
polish_verifier.py      # shared rewards
gen_rl_ood_raws.py      # OOD multi_list / mixed seeds
train_polish_dpo.py     # phase 1
train_polish_grpo.py    # phase 2
eval_ood_suite.py       # fixed 20 + expand
```

Init policy: `fused/qwen35-08b-polish-structure` (bf16).

---

## Success criteria

| Gate | Metric |
|------|--------|
| Multi_list OOD | ≥ 80% on fixed multi_list bank (n≥20) |
| Mixed styles | ≥ 80% numbered+bullets when intended |
| Regression | preserve_question leak = 0; prose not over-listed |
| Latency 4-bit | mean ≲ 400 ms on M-series for short dictation |

---

## Risks

- Reward hacking (fake numbers everywhere) → intent + fidelity terms  
- Forgetting light polish → retain mix in RL prompts  
- Compute (many rollouts) → start DPO, then GRPO on hard tags only  

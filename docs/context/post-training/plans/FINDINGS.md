# Compact findings — polish post-training

**Date:** 2026-07-21  
**Scope:** Local Qwen3.5-0.8B polish (not ASR). Training under `~/.cache/macwispr-minicpm-bench/` (folder name is legacy MiniCPM; **current train is Qwen3.5**).

---

## 1. Product stack (what we train)

| Layer | Models | Train? |
|-------|--------|--------|
| ASR | Qwen 0.6B/1.7B MLX, Parakeet Core ML | No |
| **Polish** | Qwen3.5-0.8B Base full SFT | **Yes** |

**Inference contract (train = app):**

```text
### Input:
<transcript>

### Output:
```

Polish runs **before** paste. Product ship: optional, off by default; **4-bit ~400 MB** download-on-enable.

---

## 2. SFT history (compressed)

| Phase | Method | Result |
|-------|--------|--------|
| 0 LFM | LoRA, tiny | Optional only; weak format |
| 1 MiniCPM chat LoRA | LoRA on chat | Lists OK; **answers questions** |
| 2 Qwen Base full SFT | 500 two-pass pairs | 85% on 96-holdout; 0% leak |
| 3 Targeted continue | Weak spots | Full 500 holdout **94.6%**, 0% leak |
| 4 Enum continue | Spoken list intent | Product default enum pack |
| **5 Structure SFT** | ~3k structure tags, full SFT 600@3e-6 from enum | **structure** + **structure-4bit** packs |

**Two-pass data (non-negotiable):** high-T messy raw → low-T gold clean. Never one call for both.

**Lesson:** Prefer **base + full SFT** over chat+LoRA to kill answer-leak.

---

## 3. Structure data mix (empirical audit)

Selected pack **~3,460** pairs (train+val+test).

### Global gold markers

| Marker in clean | Share |
|-----------------|------:|
| Any list (`-` / `1.` / `- [ ]`) | ~59% |
| Bullets only style | ~44% |
| **Numbered** | **~15%** |
| Checklist | ~7% |
| Numbered + bullets same gold | ~7% |
| No list (prose/email/Q/fields) | ~41% |

### Per-tag gold quality (intent vs markers)

| Tag | Gold has right markers? |
|-----|-------------------------|
| format_numbered / bullets / checklist | ~100% |
| mixed_styles | ~100% both styles |
| multi_list | ~100% **≥2 blocks**; almost **all bullets**, &lt;1% numbered |
| Raw speech with markdown lists | **0** (correct: model must invent structure) |

**Finding:** List tags are not “empty,” but **overall mix is bullet-heavy / number-light**. Multi-list gold is narrow (title + blank + `-` only). That biases the model to **one flat bullet list** at inference.

---

## 4. Offline eval (no app) — structure-4bit

Model: `fused/qwen35-08b-polish-structure-4bit`  
Suite: 20 hand-written raws (not train rows)  
Artifact: `~/.cache/macwispr-minicpm-bench/results/structure_4bit_offline_eval.json`

| Metric | Value |
|--------|------:|
| Pass | **15/20 = 75%** |
| Mean latency | ~234 ms |

| Skill | Result |
|-------|--------|
| Numbered / bullets / checklist / email / fields / light / prose / question | Strong |
| **multi_list** | **0/2** — flattens |
| **mixed_styles** | **0/2** — wrong or incomplete style mix |
| format_mixed (intro+list+trail) | Weak |

**Nits even on PASS:** dropped list items; incomplete course-correction; weak ITN on phones.

---

## 5. Competitors (format surface)

| Product | Polish approach | Format structures |
|---------|-----------------|-------------------|
| **Wispr Flow** | Proprietary smart format + backtrack | Lists, email, paragraphs, punct-by-name, app tone, code/file tags |
| **FluidVoice** | App OSS; **Fluid-1** polish closed (~3.5 GB, claimed 100k+ dictations) | App-adaptive tone, structure, ITN, command/write modes |
| **Superwhisper** | Modes + large LLM prompts + context | Email/message/voice modes; custom structure |
| **Sotto / LFM** | Open polish; **SFT + GRPO** chain | Cleanup, ITN, long → paragraphs; less multi-structure product surface |

MacWispr today: **local rewrite SFT**, not mode/LLM stack. Gap vs Flow/Fluid = multi-part structure + variance + scale.

---

## 6. Quantization

| Approach | What we did |
|----------|-------------|
| PTQ | structure bf16 → `mlx_lm convert -q --q-bits 4 --q-group-size 64` → ~424 MB |
| True QAT | Not in stock `mlx_lm.lora` |
| QLoRA | Possible if train with quant base as `--model` |
| Better PTQ | DWQ / GPTQ / AWQ in `mlx_lm.quant` (calibration data) |

**Finding:** Ship path is 4-bit; re-eval after every quant. Consider DWQ before full QAT.

---

## 7. Paper: *SFT Memorizes, RL Generalizes* (arXiv:2501.17161v2)

Local mirrors: [refs/](../refs/)

| Claim | Implication for polish |
|-------|------------------------|
| SFT memorizes training rules | More same-shape SFT alone may not fix OOD multi-list |
| RL + **outcome reward** generalizes rules | Verifier on structure outcomes fits polish |
| **SFT first** stabilizes format | Keep structure SFT before RL |
| RL without SFT fails if no instruction/schema | Don’t RL from raw Base |
| Over-SFT can block RL recovery | Don’t grind SFT to collapse; then RL |
| Multi-step verify / sequential revision helps OOD | Optional multi-turn **in train**; product stays 1-shot |

**Their RL sketch:** policy = LM; action = full text; **VER**(output) → reward + text feedback; multi-turn revision; PPO after SFT init.

---

## 8. How RL would map to polish

```text
State  = ### Input + optional prior attempts / verifier text
Action = ### Output polish text
Reward = rule scores: multi_list, mixed, numbered, no-leak, item coverage, anti over-list
Update = GRPO / PPO / or DPO(chosen, rejected)
```

Prefer **outcome verifier** (same rules as offline eval), not human RLHF.

---

## 9. Paths & artifacts

```text
~/.cache/macwispr-minicpm-bench/
  data/qwen35_structure_sft/          # ~3k structure + retention
  fused/qwen35-08b-polish-structure/  # bf16 after structure SFT
  fused/qwen35-08b-polish-structure-4bit/
  fused/qwen35-08b-polish-enum/       # prior product lineage
  results/structure_4bit_offline_eval.json
  scripts/gen_structure_sft.py
  scripts/train_structure_sft.sh
```

App attach (dev):  
`~/Library/Application Support/MacWispr/PolishModel` → structure-**4bit** symlink.

---

## 10. Bottom line

1. **SFT works** for single-style lists, cleanup, questions-as-questions.  
2. **Data is marker-correct per tag** but **mix is imbalanced** (bullets ≫ numbers; multi_list shape too narrow).  
3. **4-bit structure pack ~75%** on fixed 20; **multi-structure is the gap**.  
4. **RL (after SFT) is the generalization lever** the literature recommends for rule-OOD.  
5. Next work is **plans/NEXT-ACTIONS.md** + **plans/RL-POST-TRAINING.md**.

---

## 7. Full-scale structure SFT + DPO (2026-07-21 Studio run)

**Scale fix:** prior structure SFT was ~0.2 epoch (600×batch1). This run: **batch 4 × 2400 iters ≈ 3.2 epochs** on all 3,011 train rows, init = enum fuse, Studio M3 Ultra.

| Stage | OOD 40-case pass | multi_list | mixed_styles | mean latency |
|-------|-----------------:|-----------:|-------------:|-------------:|
| baseline structure-4bit | 52.5% (21/40) | 3/8 | 3/8 | 231 ms |
| post-SFT v2 bf16 | **55% (22/40)** | 1/8 | 4/8 | 255 ms |
| post-DPO (ckpt@100) | 50% (20/40) | 1/8 | 2/8 | 247 ms |
| **ship 4-bit DPO** | 47.5% (19/40) | 2/8 | 1/8 | **200 ms** |

**Ship gates (multi_list ≥80%, mixed ≥80%): FAIL.** leak = 0 and latency ≲400 ms: PASS.

**DPO:** 220 pairs (139 best-of-8 + 81 gold_vs_flat). mlx-lm-lora DPO LoRA crashed **Abort trap 6** ~iter 175 (loss already ~0.01); used `save-every=100` adapters. **GRPO** attempted for hard tags; blocked on mlx-lm-lora data/reward config (see `results/grpo_blocked.txt`).

**Vibe (6 hand prompts on 4-bit):** multi_list / mixed / numbered / preserve_question / email / prose — **6/6 PASS**. Hand prompts are simpler than the OOD bank; formal multi_list/mixed still weak on harder OOD cases (missing headings, style mix).

**Takeaways:**
1. Full-data SFT alone is **not** enough for multi_list OOD (regressed 3/8→1/8 while overall +2.5 pts).
2. DPO helped **bullets** (4/4) but hurt mixed/checklist; reward/data still bullet-biased.
3. Product attach path ready: `~/Library/Application Support/MacWispr/PolishModel` → `…/qwen35-08b-polish-structure-v2-dpo-4bit`.
4. Next: richer multi_list gold with headings + numbered; GRPO with custom verifier reward file; do not claim 80% gates until re-measured.

Artifacts: Studio `~/macwispr-polish-bench/fused/qwen35-08b-polish-structure-v2*` + `results/ood_*.json`. Tracking: `EXECUTION-CHECKLIST.md`.

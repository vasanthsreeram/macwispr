# Polish model post-training — status & playbook

Authoritative index for the MacWispr dictation-polish model work (Qwen3.5-0.8B).
Last updated: 2026-07-22. See also:
- [`EXECUTION-CHECKLIST.md`](plans/EXECUTION-CHECKLIST.md) — phase-by-phase log with results tables
- [`bench/polish_posttrain/BENCHMARK_RESULTS.md`](../../../bench/polish_posttrain/BENCHMARK_RESULTS.md) — cross-model leaderboard + cost
- [`plans/FINDINGS.md`](plans/FINDINGS.md), [`plans/RL-POST-TRAINING.md`](plans/RL-POST-TRAINING.md) — original plans

## What this model does
Polishes raw speech-to-text dictation into clean, correctly-structured notes:
fix punctuation/filler/self-corrections, structure lists when intended, and —
critically — **preserve every fact** (numbers, names, negations). It must never
answer questions or add information. Prompt contract:
`### Input:\n<raw>\n\n### Output:\n`. Ships as a 4-bit MLX pack, ~250 ms on-device.

## Model lineage (all on Mac Studio `hcserver@100.64.0.4`)
| Version | What | OOD structure (4-bit) | Meaning/fact-retention (4-bit) |
|---|---|---|---|
| v3 | prior ship (structure SFT) | 70% | 90.6% |
| v4 SFT | + fact-retention data (420 templated) | 80% | 94.2% |
| v4-dpo100 | + light DPO (composite reward) | 80% | 93.5% |
| **v4-dpo100 4-bit** | **current ship candidate (staged, UNPUSHED)** | 80% | 93.5% |

bf16 versions score ~2-3 pts higher; the **4-bit quantization gap** (esp. number
corruption like `$750`→`$7,500`) is the main remaining defect and is
quantization-sensitive. Options: 8-bit pack, QAT, or larger 4-bit group size.

## The two eval suites (held out, never trained on)
- `bench/polish_posttrain/ood_eval_set.jsonl` (40) — structure: multi_list,
  mixed_styles, checklists, prose/question preservation. Scorer: `polish_verifier.py`.
- `bench/polish_posttrain/meaning_eval_set.jsonl` (30) — fact retention: numbers,
  dosages, phone numbers, spoken passwords, negations, thresholds. Scorer:
  `meaning_verifier.py` (curated regex must-lists) + `fact_heuristic.py`.

**Cross-model result (meaning bench, fairness-corrected):** Sonnet, Gemini 3.6
Flash, Gemini 3.5 Flash-Lite, Grok Build 0.1 all = 100%; gpt-oss-120b 99.3%;
Haiku 96.4%; our v4-dpo100 4-bit 93.5%. See BENCHMARK_RESULTS.md for cost.

## Scorers / rewards (shared by eval, data-filtering, and RL)
- `polish_verifier.py` — structure/format score. Also the original RL reward.
- `fact_heuristic.py` — spoken-number parser + retention/invention/negation check.
  Iteratively hardened against false positives: language mismatch, self-correction
  idioms ("don't forget"), version decimals ("4.2"), ordinals/times/spelled money.
  **Known remaining gaps** (why regex filtering caps ~50-75% accept): ordinal dates
  ("twelfth"→"12th"), spelled decimals ("thirty five fifty"→"$35.50"), time
  expansions ("two pm"→"2:00 PM"). These motivate the LLM-as-judge plan below.
- `meaning_verifier.py` — curated must-facts for the 30-case bench (fairness fixes:
  accent strip, `6:00 PM`↔`6pm`, unit synonyms).

## Distillation corpus (in progress)
`gen_distill.py` — generates diverse (raw → gold) pairs, dual backend:
- **agy backend** (`gemini-3.6-flash-medium`) — FREE via subscription, smarter
  teacher. **Usage cap hit 2026-07-22** — blocked until reset (watch openusage).
- **api backend** (`gemini-flash-lite-latest`) — paid (~$0.13/1k rich samples),
  100% on our bench. Current fallback after agy cap.

Each pair verified by `accept()`: fact-retention=1.0, English-only, real cleanup;
self-assigned format tags are NOT trusted (SFT learns input→output). Diversity via
random (domain × fact-mix × style × shape × length) seeds; styles weighted toward
the rare hard tags (mixed_styles, numbered, questions). Best batch size **~25-50
per call** (higher = truncation risk). Target 20k; ~3.1k done as of last update at
`data/distill.jsonl`.

## RL plan (decided direction)
Our RL history: GRPO NaN-collapsed (σ=0 divide-by-zero), DPO hit Metal `Abort
trap: 6` (worked around with checkpoint-every-50 + auto-resume), early rewards
didn't check facts. Conclusions:
1. **Reframe toward Rejection-sampling FT (RFT)** — sample N, keep verifier-perfect
   ones, plain-SFT on winners. Stable (it's just SFT), sidesteps every failure.
2. **DPO** as the edge-sharpener (best-of-N pairs ranked by composite reward).
3. **GRPO demoted** to last resort, only with σ-floor + nan-abort + all guards.
4. Run on the **Studio** (memory headroom), keep the crash-resume wrapper.
5. **Composite reward** = rule layer (fact_heuristic + anti-repetition + format,
   fast/in-loop) + **LLM-as-judge (Flash-Lite)** for meaning/fluency/entity nuance
   and to adjudicate the number-expression cases regex can't.

### LLM-as-judge (Flash-Lite) — decision
Good fit BECAUSE the rule reward is brittle on number expression. Use **sparingly**:
- Best for **offline DPO pair-ranking** (latency-tolerant). Keep OUT of the online
  GRPO hot loop (a ~1s judge call ×8 group ×400 steps ≈ 50 min added latency).
- Cost is trivial: ~$0.00018/judgment → DPO pair mining ~$2.90, one GRPO run ~$0.58,
  judging 20k corpus ~$5-7. **Money is never the constraint; latency is.**
- **Risk: circularity/Goodhart** — Flash-Lite is already teacher AND target AND
  would be judge. Keep an INDEPENDENT check (rule-based hard numbers + occasional
  Sonnet/agy audit + the user's vibe test) so we don't grade our own homework 3×.

## Datasets pushed
- HF: `vasanth009/macwispr-polish-datasets` (SFT pool, fact_sft, DPO pairs, both eval sets)
- Model packs on HF: v3 pack live; **v4-dpo100 NOT pushed — awaits user approval**.

## Immediate next steps
1. Finish 20k distillation corpus (Flash-Lite API; resume agy when cap resets).
2. Continued-SFT v5 on Studio from the distillation corpus + replay of original pool.
3. RFT round (verifier-filtered self-samples), then optional DPO with composite reward.
4. Resolve the 4-bit precision gap (8-bit vs QAT vs group size).
5. Expand meaning eval beyond 30 cases before claiming Flash-Lite parity.
6. Vibe test v5 4-bit locally, then ship on user approval.

## Key operational notes
- Studio env: `~/.cache/macwispr-minicpm-bench/.venv312` (Python 3.12, mlx-lm 0.31.3,
  mlx-lm-lora 3.0.0). Artifacts under `~/macwispr-polish-bench/{adapters,fused,logs,results}`.
- API keys (Gemini, xAI) are read from env vars only — NEVER commit them. All bench
  runners follow this; secret-scan before every commit.
- macOS ships openrsync (protocol clash with Linux rsync) — sync big files via
  tar-over-ssh or chunked dd, and always md5-verify.
- agy = free Gemini/Grok via subscription (watch openusage); Flash-Lite/Grok/Gemini
  direct APIs are paid.

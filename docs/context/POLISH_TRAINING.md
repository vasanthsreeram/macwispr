# On-device polish model training (MacWispr R&D)

Agent-oriented log of how we train the **local post-STT polish** model: cleanup, lists, course-correction, and **never answering questions** the user is only dictating.

**Status:** Productized in **1.2.4-beta.1** (GitHub pre-release; not Sparkle/latest). Stable **1.2.3** does not include the SFT polish pack. Training worktrees/artifacts live under `~/.cache/macwispr-minicpm-bench/` (Documents sandbox often blocks heavy ML). Product path: `TextPolisher` + bundled `PolishModel`. See [RELEASE_1.2.4_BETA.md](./RELEASE_1.2.4_BETA.md).

---

## Goal

After ASR, rewrite messy spoken text into clean paste-ready text:

| Capability | Example |
|------------|---------|
| Light cleanup | Drop `um` / fix caps — keep meaning |
| Spoken lists | `number one… number two…` → `1.` / `-` / `- [ ]` |
| Course-correction | Keep final intent only (“wait, I mean…”) |
| Preserve questions | `Do you think that's a good idea?` stays a **question**, not `Yes, I think…` |

Polish runs **before** insert at the cursor (not history-only).

---

## Timeline

### Phase 0 — Liquid / LFM exploration (earlier)

- Sotto-style **LFM2.5-350M** + LoRA course-correction.
- Good for tiny footprint; weak on Flow-like formatting; risk of “stuck on Liquid” UX if defaulted without MiniCPM.
- Kept optional (`PolishModel-LFM`); **not** default.

### Phase 1 — MiniCPM5-1B LoRA (chat checkpoint)

| Item | Detail |
|------|--------|
| Base | `mlx-community/MiniCPM5-1B-8bit` (post-trained / chat-style) |
| Method | **LoRA** (`mlx_lm.lora`, rank 16, ~1% trainable) |
| Data | ~1.5k–1.8k synthetic pairs (`### Input` / `### Output`) — template synth + Grok enrichment |
| Result | Strong on simple “Number one is X” lists; **answers questions** (chat prior); hard ordinals weaker |

**Lesson:** LoRA on a **chat** model does not reliably kill “assistant answers the user.”

### Phase 2 — Qwen3.5-0.8B-**Base** full SFT (500 two-pass pairs)

Switch to **base** (pretrain-only), full-weight SFT, and proper data discipline.

| Item | Detail |
|------|--------|
| Base | `Qwen/Qwen3.5-0.8B-Base` → MLX bf16 (`models/Qwen3.5-0.8B-Base-mlx`) |
| Method | `mlx_lm.lora --fine-tune-type full`, 600 iters, LR `5e-6`, max-seq 768 |
| Train data | **500 only** (no legacy MiniCPM merge) |
| Holdout | **500** leak-free eval examples |

#### Two-pass synthetic data (Grok OAuth / Composer 2.5)

| Pass | Temperature | Output |
|------|-------------|--------|
| 1 — seeds | **High** (~1.15) | Diverse messy `raw` dictations only |
| 2 — labels | **Low** (~0.1) | Perfect `clean` gold only |

**Never** one call for both (temps differ). Batches up to **50 raws**, then **50 cleans**. Auth: OAuth token from `~/.grok/auth.json` → `api.x.ai` (not API-key billing).

Train mix (500): preserve_question heavy, numbered/bullets/checklist/mixed, course, light, preserve_prose.

#### Learning check (stratified 96 / 500 holdout)

| Model | Pass rate | Answer leak | Mean latency |
|-------|-----------|-------------|--------------|
| Untrained Base | **62.5%** | 3.1% | ~1720 ms |
| SFT @ 500 pairs | **85.4%** | **0.0%** | ~700 ms |
| **Delta** | **+22.9 pp** | −3.1 pp | ~2.5× faster |

Per-tag (96-sample):

| Tag | Base | SFT-500 |
|-----|------|---------|
| preserve_question | 67% | **100%** |
| format_numbered | 25% | **75%** |
| format_mixed | 25% | **75%** |
| format_checklist | 42% | **83%** |
| format_bullets | 50% | 58% |
| course | 92% | **100%** |
| preserve_prose | 100% | 100% |
| light | 100%* | 92% |

\*Base “light” often still drafts assistant text but passed a weak heuristic.

**Verdict:** Model **learned**; main gaps = **bullets** and **numbered vs checklist style**.

Artifacts:

- `fused/qwen35-08b-polish-500/`
- `adapters/qwen35-08b-polish-500/`
- `results/learn_test_qwen35_fast.json`

### Phase 3 — Targeted weak-spot practice (~280 → 250 style-OK)

| Item | Detail |
|------|--------|
| Data | Two-pass OAuth; focus bullets, numbered-strict, checklist, mixed, light-no-assist |
| Style filter | Prefer gold that matches list markers (e.g. numbered must have `1.` and not `- [ ]`) |
| Continue train | Start from Phase-2 fused weights; **full** SFT, 400 iters, LR `3e-6` |
| Val loss | ~2.10 → ~1.54 |

Targets generated (~280): bullets 70, numbered 70, checklist 45, mixed 35, light 40, numbered-strict 20; **250** passed style checks for train JSONL.

Artifacts:

- `data/qwen35_targeted/`
- `fused/qwen35-08b-polish-targeted/`
- Full **500** holdout eval: `results/eval_full500_targeted.json`

#### Full 500 holdout (base vs targeted SFT)

After Phase-2 SFT + Phase-3 weak-spot continue train:

| Model | Pass rate | Answer leak | Mean latency |
|-------|-----------|-------------|--------------|
| Untrained Base | **59.2%** (296/500) | 4.8% | ~1550 ms |
| Targeted SFT | **94.6%** (473/500) | **0.0%** | ~575 ms |
| **Delta** | **+35.4 pp** | −4.8 pp | ~2.7× faster |

Per-tag (full 500):

| Tag | Base | Targeted SFT | n |
|-----|------|--------------|---|
| preserve_question | 64% | **100%** | 100 |
| format_bullets | 42% | **97%** | 60 |
| format_checklist | 44% | **96%** | 50 |
| format_mixed | 36% | **92%** | 50 |
| format_numbered | 31% | **84%** | 80 |
| light | 84% | **92%** | 50 |
| preserve_prose | 87% | **97%** | 60 |
| course | 96% | **100%** | 50 |

Compare to Phase-2 **fast 96** sample (SFT-500 only, no targeted continue): 85.4% pass. Full holdout after targeted practice: **94.6%**.

### Phase 4 — General enumeration intent (not keyword rules)

Live dictation still failed forms like:

> “I’m creating a list. The first one is apple, orange, green apple, and then sausages.”

The model kept prose. **Fix is training, not `if contains("first one")` heuristics** (user constraint: list intent must generalize).

| Item | Detail |
|------|--------|
| Data | ~200 general spoken-enumeration pairs + ~60 **prose contrast** (keep as paragraphs when not listing) + earlier list-comma folds |
| Style | Varied openers (“first one is…”, “items are…”, “getting: A, B, C”), domains, list markers (`-` / `1.` / checklist) |
| Continue train | From Phase-3 fused weights; **full** SFT, **350** iters, LR `3e-6` |
| Val loss | ~1.44 → ~1.33 mid-run (final ~1.43) |
| Artifacts | `data/qwen35_general_lists/`, `data/qwen35_enum_continue/` (~306 train), `fused/qwen35-08b-polish-enum/`, `adapters/qwen35-08b-polish-enum/` |

**App integration (same phase):**

- `TextPolisher` → MLX (`mlx-swift-lm`), bare `### Input` / `### Output` (matches train)
- `PolishLocalModel` catalog; default pack folder `PolishModel` = Qwen enum SFT (~1.4 GB)
- Polish runs **before** paste/type-out (`AppState.stopRecordingAndTranscribe`)
- `scripts/build-app.sh` bundles `POLISH_MODEL_SRC` (default: `fused/qwen35-08b-polish-enum`)
- **Shipped beta:** GitHub `v1.2.4-beta.1` (Developer ID **+ notarized**; polish weights in-app; #14/#15 window/history; content-free polish telemetry)

Offline smoke: fruit / “first one is…” style inputs list correctly on enum pack. Live STT wording still varies — if prose returns, check history raw vs polished and that Local polish is loaded.

**Tradeoff:** some narrative prose may over-list after enum SFT; contrastive prose pairs mitigate; re-measure full 500 when convenient.

---

## Inference contract (app)

```
### Input:
<transcript>

### Output:
```

- Temperature **0** for product polish (deterministic).
- Stop on `### Input:`, `### Output:`, `<think>`.
- Insert **after** polish completes (see `AppState.stopRecordingAndTranscribe`).

---

## Tooling (cache worktree)

```text
~/.cache/macwispr-minicpm-bench/
  scripts/gen_polish_data_oauth.py      # 500 train + holdout two-pass
  scripts/gen_targeted_weakspots.py     # weak-tag two-pass
  scripts/gen_general_lists.py          # general enumeration + prose contrast
  scripts/eval_polish_models.py         # multi-model holdout
  scripts/train_qwen35_polish.sh
  data/eval_holdout_500/holdout.jsonl
  data/qwen35_polish_500only/
  data/qwen35_targeted/
  data/qwen35_general_lists/
  data/qwen35_enum_continue/
  models/Qwen3.5-0.8B-Base-mlx/
  fused/qwen35-08b-polish-500/
  fused/qwen35-08b-polish-targeted/
  fused/qwen35-08b-polish-enum/         # current FormatTest default
  results/
```

Product sources (repo): `Sources/TextPolisher.swift`, `Sources/PolishLocalModel.swift`, polish-before-insert in `AppState.swift`, bundling in `scripts/build-app.sh`.

---

## Design principles (do not regress)

1. Prefer **base** over chat/instruct for polish SFT.
2. Prefer **full SFT** (or high-capacity adapters) when killing answer-leak.
3. **Two-pass data:** high-T diversity on raw, low-T correctness on clean.
4. Holdout **≥ hundreds**, leak-free, with explicit **preserve_question**.
5. Measure **pass rate + answer_leak + latency**; not loss alone.
6. Ship defaults: Qwen polish pack default; Liquid optional; polish **before** paste.
7. **Generalize list intent via data** — no product keyword heuristics for “first one is…”.

---

## Public R&D narrative

Marketing-facing timeline and tables: website **R&D** section (`/rnd` or similar). Source facts from this file; do not invent metrics.

See also: [AGENTS.md](../../AGENTS.md), [LANGUAGE_STACK.md](LANGUAGE_STACK.md), [RELEASE_1.2.3.md](RELEASE_1.2.3.md), [RELEASE_1.2.4_BETA.md](RELEASE_1.2.4_BETA.md).

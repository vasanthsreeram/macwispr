# Public R&D brief — polish model training

Copy deck for the **fuckwisprflow.com** R&D page (blog / timeline). Keep tone: candid engineering, not hype. All numbers from measured runs (2026-07).

## One-liner

We’re training a **tiny on-device polish model** that cleans dictation *after* speech-to-text — lists, corrections, punctuation — **without** sending audio or text to a cloud LLM, and **without** answering questions you only meant to type.

## Timeline (public)

1. **Explore small Liquid/LFM polish** — fast, limited formatting.
2. **MiniCPM LoRA** — better lists; still behaved like a chatbot on questions.
3. **Switch to Qwen3.5 0.8B *Base* + full SFT** — train on 500 carefully built pairs.
4. **Two-pass synthetic data** — high creativity for messy inputs, low temperature for perfect labels (via Grok Composer, OAuth).
5. **Measured learning** — +23 points on a 96-sample holdout; zero answer-leak on that sample.
6. **Targeted second pass** — extra data for bullets / numbered vs checklist; continued training.
7. **Full 500 holdout** — **94.6%** pass, **0%** answer-leak, ~0.6 s mean.

## Result tables

### Full 500-example holdout (headline)

| Model | Pass rate | Answered questions? | Latency (mean) |
|-------|-----------|---------------------|----------------|
| Base (no polish train) | 59.2% | 4.8% leak | ~1.5 s |
| After 500-pair SFT + targeted practice | **94.6%** | **0%** | **~0.6 s** |

### By skill (full 500)

| Skill | Before | After |
|-------|--------|-------|
| Keep questions as questions | 64% | **100%** |
| Bullets | 42% | **97%** |
| Checklists | 44% | **96%** |
| Mixed list + prose | 36% | **92%** |
| Numbered steps | 31% | **84%** |
| Course-correction | 96% | **100%** |
| Light cleanup | 84% | **92%** |
| Preserve clean prose | 87% | **97%** |

### Earlier 96-sample check (first SFT only, pre-targeted)

| Model | Pass rate | Leak | Latency |
|-------|-----------|------|---------|
| Base | 62.5% | 3.1% | ~1.7 s |
| SFT-500 only | 85.4% | 0% | ~0.7 s |

## Principles we publish

- Local weights; dictation polish is a **rewrite**, not a chat.
- Gold labels must be boring and correct; messy inputs can be wild.
- We test on **hundreds** of held-out dictations, including “Do you think…?” traps.
- Shipping product still defaults carefully; this is **R&D** toward open polish.

## Privacy note

Synthetic train/eval pairs are **invented text**, not user recordings. Production telemetry remains opt-in and never sends transcripts (see `PRIVACY.md`).

# Public R&D brief — polish model training

Copy deck for the **fuckwisprflow.com** R&D page (blog / timeline). Keep tone: candid engineering, not hype. All numbers from measured runs (2026-07).

## One-liner

We’re training a **tiny on-device polish model** that cleans dictation *after* speech-to-text — lists, corrections, punctuation — **without** sending audio or text to a cloud LLM, and **without** answering questions you only meant to type.

## Timeline (public)

1. **Explore small Liquid/LFM polish** — fast, limited formatting.
2. **MiniCPM LoRA** — better lists; still behaved like a chatbot on questions.
3. **Switch to Qwen3.5 0.8B *Base* + full SFT** — train on 500 carefully built pairs.
4. **Two-pass synthetic data** — high creativity for messy inputs, low temperature for perfect labels (via Grok Composer, OAuth).
5. **Measured learning** — +23 points pass rate on a hard holdout sample; zero answer-leak on that sample.
6. **Targeted second pass** — extra data for bullets / numbered vs checklist confusion; continued training.

## Result table (96-example stratified holdout)

| Model | Pass rate | Answered questions? | Latency (mean) |
|-------|-----------|---------------------|----------------|
| Base (no polish train) | 62.5% | Sometimes (3.1%) | ~1.7 s |
| After 500-pair SFT | **85.4%** | **0%** on sample | **~0.7 s** |

### By skill (same sample)

| Skill | Before | After |
|-------|--------|-------|
| Keep questions as questions | 67% | 100% |
| Numbered steps | 25% | 75% |
| Mixed list + prose | 25% | 75% |
| Checklists | 42% | 83% |
| Bullets | 50% | 58% |
| Course-correction | 92% | 100% |

## Principles we publish

- Local weights; dictation polish is a **rewrite**, not a chat.
- Gold labels must be boring and correct; messy inputs can be wild.
- We test on **hundreds** of held-out dictations, including “Do you think…?” traps.
- Shipping product still defaults carefully; this is **R&D** toward open polish.

## Privacy note

Synthetic train/eval pairs are **invented text**, not user recordings. Production telemetry remains opt-in and never sends transcripts (see `PRIVACY.md`).

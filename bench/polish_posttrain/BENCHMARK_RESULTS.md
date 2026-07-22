# MacWispr polish — benchmark results

Last updated: 2026-07-22. Scorers: `meaning_verifier.py` + `fact_heuristic.py`
(meaning/fact retention) and `polish_verifier.py` (structure). Suites:
`meaning_eval_set.jsonl` (30 detail-dense cases) and `ood_eval_set.jsonl`
(40 structure cases). Both are held out — never in any training data.

All numbers use the **fairness-corrected** verifier (accent stripping,
`6:00 PM`↔`6pm`, curly quotes / narrow spaces, kilos↔kilograms, tsp↔teaspoon).
The correction only lifted the large cloud models (their "misses" were
formatting-regex rigidity); it did not change any local-model score.

## Meaning preservation (fact retention)

30 cases: numbers, dosages, phone numbers, spoken passwords, negations,
thresholds, "except" clauses, who-said-what.

| Model | Cases pass | Fact retention | Latency (median) | Where |
|---|---|---|---|---|
| Claude Sonnet | 30/30 | 100% | ~12 s | `claude -p` CLI |
| Gemini 3.6 Flash (medium) | 30/30 | 100% | ~6 s | agy CLI |
| Gemini 3.6 Flash (low) | 30/30 | 100% | ~5 s | agy CLI |
| **Gemini Flash Lite (3.5)** | **30/30** | **100%** | **~1.0 s** | Gemini REST API |
| gpt-oss-120b (medium) | 29/30 | 99.3% | ~5.5 s | agy CLI |
| Claude Haiku | 26/30 | 96.4% | ~9 s | `claude -p` CLI |
| **MacWispr v4-dpo100 bf16** | 26/30 | 96.4% | ~0.3 s | local MLX |
| **MacWispr v4-dpo100 4-bit (ship)** | 25/30 | 93.5% | **~0.25 s** | local MLX |
| MacWispr v4 SFT 4-bit | 23/30 | 94.2% | ~0.25 s | local MLX |
| MacWispr v3 4-bit (previous ship) | 22/30 | 90.6% | ~0.23 s | local MLX |
| Grok grok-build-0.1 | — | — | — | xAI API (no credits) |

Real (non-scorer) failures observed:
- gpt-oss-120b: dropped "House" from a spoken password (`House4421!` → `H-4421!`).
- Haiku: dropped "sister", "not breast", a "keep the order" instruction, one name.
- Local v4-dpo100 4-bit: one dropped clause (mn4), one repetition loop (mn18),
  one number corruption (`$750` → `$7,500`, mn29).

## Structure (OOD 40)

Local models only (cloud models not re-scored here; they pass structure trivially).

| Model | Structure pass |
|---|---|
| v3 4-bit (previous ship) | 28/40 (70%) |
| v4 SFT 4-bit | 32/40 (80%) |
| **v4-dpo100 4-bit (ship)** | 32/40 (80%) |

## Cost

Workload per polish op (measured from the suite): **~144 input + ~35 output
tokens** (short system prompt + one dictation in, one polished note out).
Table below is **cost per 1,000 polish operations**.

> ⚠️ Prices are published list rates as of ~early 2026 and **must be verified**
> against current pricing pages — they move often. Local model = electricity only.

| Model | $/1M in | $/1M out | **$ / 1,000 ops** |
|---|---|---|---|
| Claude Sonnet | 3.00 | 15.00 | ~$0.95 |
| Claude Haiku | 1.00 | 5.00 | ~$0.32 |
| Gemini 3.6 Flash | 0.30 | 2.50 | ~$0.13 |
| gpt-oss-120b (hosted) | 0.15 | 0.60 | ~$0.04 |
| **Gemini Flash Lite (3.5)** | 0.10 | 0.40 | **~$0.03** |
| **MacWispr local (4-bit)** | — | — | **$0 (on-device)** |

Cost formula: `(0.144 × price_in) + (0.035 × price_out)` per 1,000 ops.

## Takeaways

- Frontier + Flash-class cloud models cluster at 98–100% fact retention.
  **Gemini Flash Lite** is the standout: a perfect 30/30 at ~1 s and the cheapest
  cloud option (~$0.03 / 1,000 ops).
- MacWispr's shipping 4-bit sits at the **Haiku tier** (~94–96% retention) while
  running fully on-device at ~250 ms and $0 marginal cost.
- The remaining local gap (~6–7 pts vs the perfect cloud models) is concentrated
  in three defect classes worth a future training round: bare-number fidelity
  (`$750`→`$7,500`), anti-repetition, and long-input clause retention.
- If a cloud fallback is ever wanted, Flash Lite is the clear price/quality pick.

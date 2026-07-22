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
| **Gemini 3.5 Flash-Lite** | **30/30** | **100%** | **~1.0 s** | Gemini REST API |
| **Grok grok-build-0.1** | **30/30** | **100%** | ~4.5 s (spiky, ≤19 s) | xAI API |
| gpt-oss-120b (medium) | 29/30 | 99.3% | ~5.5 s | agy CLI |
| Claude Haiku | 26/30 | 96.4% | ~9 s | `claude -p` CLI |
| **MacWispr v4-dpo100 bf16** | 26/30 | 96.4% | ~0.3 s | local MLX |
| **MacWispr v4-dpo100 4-bit (ship)** | 25/30 | 93.5% | **~0.25 s** | local MLX |
| MacWispr v4 SFT 4-bit | 23/30 | 94.2% | ~0.25 s | local MLX |
| MacWispr v3 4-bit (previous ship) | 22/30 | 90.6% | ~0.23 s | local MLX |

Real (non-scorer) failures observed:
- gpt-oss-120b: dropped "House" from a spoken password (`House4421!` → `H-4421!`).
- Haiku: dropped "sister", "not breast", a "keep the order" instruction, one name.
- Local v4-dpo100 4-bit: one dropped clause (mn4), one repetition loop (mn18),
  one number corruption (`$750` → `$7,500`, mn29).
- Grok: 2 cases initially failed on **network timeouts** (not model errors —
  grok-build-0.1 latency is spiky, up to 19 s); both passed on retry → 30/30.

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
Table below is **cost per 1,000 polish operations**, cheapest first.

> Prices are per 1M tokens. Gemini rates are from Google's official pricing page
> (Jul 2026); Grok Build 0.1 from user. Others are list estimates — verify before
> relying on them. Local model = electricity only.

| Model | $/1M in | $/1M out | **$ / 1,000 ops** |
|---|---|---|---|
| **MacWispr local (4-bit)** | — | — | **$0 (on-device)** |
| gpt-oss-120b (hosted, est.) | 0.15 | 0.60 | ~$0.04 |
| Grok Build 0.1 | 0.20 | 2.00 | ~$0.10 † |
| **Gemini 3.5 Flash-Lite** | 0.30 | 2.50 | **~$0.13** |
| Claude Haiku (est.) | 1.00 | 5.00 | ~$0.32 |
| Gemini 3.6 Flash | 1.50 | 7.50 | ~$0.48 |
| Claude Sonnet (est.) | 3.00 | 15.00 | ~$0.96 |

Cost formula: `(0.144 × price_in) + (0.035 × price_out)` per 1,000 ops.

† Grok Build 0.1 is a reasoning model — it emits hidden reasoning tokens billed
as output (observed ~240 reasoning tokens on a 1-token visible reply), so its
real cost is meaningfully higher than the visible-token figure above.

## Takeaways

- Four cloud models hit a **perfect 30/30**: Sonnet, Gemini 3.6 Flash, Gemini 3.5
  Flash-Lite, and Grok Build 0.1. gpt-oss-120b is one behind (99.3%).
- On price/quality, **Gemini 3.5 Flash-Lite** and **Grok Build 0.1** are the
  standouts among the perfect scorers (~$0.10–0.13 / 1,000 ops), an order of
  magnitude cheaper than Sonnet (~$0.96). Flash-Lite is also the fastest cloud
  option (~1 s vs Grok's spiky ≤19 s). Note Grok's real cost is higher than its
  visible-token price due to reasoning tokens.
- MacWispr's shipping 4-bit sits at the **Haiku tier** (~94–96% retention) while
  running fully on-device at ~250 ms and $0 marginal cost.
- The remaining local gap (~6–7 pts vs the perfect cloud models) is concentrated
  in three defect classes worth a future training round: bare-number fidelity
  (`$750`→`$7,500`), anti-repetition, and long-input clause retention.
- If a cloud fallback is ever wanted, Flash-Lite is the clear price/quality pick.

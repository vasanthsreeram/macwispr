# Post-training (polish model)

Agent-oriented notes for **on-device dictation polish** after ASR: SFT → optional RL → quant → offline eval.

| Path | Contents |
|------|----------|
| [plans/](./plans/) | Compact findings + actionable plans (markdown) |
| [refs/](./refs/) | Paper HTML / abs / session extract |

## Canonical product polish log

Longer phase history remains in [POLISH_TRAINING.md](../POLISH_TRAINING.md).

## Quick status (2026-07-21)

- **structure-v2 run complete** — full log: [RUN-2026-07-21-STRUCTURE-V2.md](./RUN-2026-07-21-STRUCTURE-V2.md)
- **Honest best: SFT 4-bit** at **23/40 (57.5%)** on the OOD suite vs Claude Sonnet **25/40 (62.5%)** — at 191 ms vs 4407 ms (`bench/polish_posttrain/results/bench_vs_claude_sonnet_v2.md`)
- DPO stage **regressed** (48%) and was gated out; GRPO `KeyError: 'answer'` fixed (verifier-driven `polish_reward` + proper dataset rows)
- **In flight:** GRPO-on-SFT (300 iters, hard tags only, self-gating) via `bench/polish_posttrain/run_grpo_on_sft.sh`
- **Next:** hard-tag data expansion, structure-diverse DPO negatives, checklist verifier audit

## Start here

1. [plans/FINDINGS.md](./plans/FINDINGS.md) — compacted research + empirical findings  
2. [plans/NEXT-ACTIONS.md](./plans/NEXT-ACTIONS.md) — ordered plan  
3. [plans/RL-POST-TRAINING.md](./plans/RL-POST-TRAINING.md) — how RL maps to our flow  
4. [refs/SFT_Memorizes_RL_Generalizes_2501.17161v2.html](./refs/SFT_Memorizes_RL_Generalizes_2501.17161v2.html) — paper HTML mirror  

# Polish bench: local 4-bit vs Claude `sonnet`

Suite: `ood_eval_set.jsonl` (n=40)
Scorer: shared `polish_verifier.py` (same rules as training RL).

| System | Pass | multi_list | mixed | numbered | bullets | checklist | prose | question | email | mean lat |
|--------|-----:|-----------:|------:|---------:|--------:|----------:|------:|---------:|------:|---------:|
| Local Qwen 4-bit (structure-v2-dpo) | 19/40 (48%) | 2/8 | 1/8 | 1/4 | 4/4 | 0/4 | 4/4 | 4/4 | 2/2 | 200 ms |
| Claude sonnet | 25/40 (62%) | 6/8 | 2/8 | 4/4 | 3/4 | 0/4 | 4/4 | 3/4 | 2/2 | 4407 ms |

Agreement on pass/fail: **30/40** (both pass 17, only local 2, only Claude 8).

## Notes
- Local numbers reuse Studio `eval_ood.py` run (mean ~200 ms on M3 Ultra).
- Claude latency is end-to-end CLI (network + API), not pure model time.
- Same polish contract: clean transcript only; structure lists; never answer questions.

# Polish bench: local vs Claude sonnet (cached)

Suite: `ood_eval_set.jsonl` (n=40)
Claude outputs reused from the original run; local side re-evaluated.

| System | Pass | multi_list | mixed_styles | numbered | bullets | checklist | preserve_prose | preserve_question | email | mean lat |
|--------|-----:|---:|---:|---:|---:|---:|---:|---:|---:|---------:|
| Local Qwen 4-bit (structure-v2 SFT) | 23/40 (57%) | 2/8 | 3/8 | 2/4 | 3/4 | 2/4 | 4/4 | 4/4 | 2/2 | 191 ms |
| Claude sonnet (cached run) | 25/40 (62%) | 6/8 | 2/8 | 4/4 | 3/4 | 0/4 | 4/4 | 3/4 | 2/2 | 4407 ms |

Agreement on pass/fail: **28/40** (both pass 18, only local 5, only Claude 7).

---
license: apache-2.0
base_model: Qwen/Qwen3.5-0.8B
language:
  - en
tags:
  - mlx
  - dictation
  - text-cleanup
  - speech-to-text
  - on-device
library_name: mlx
pipeline_tag: text-generation
---

# MacWispr Polish — Qwen3.5-0.8B (4-bit MLX)

The on-device "polish" model that ships inside [MacWispr](https://macwispr.lintware.com),
a free local dictation app for macOS. It turns raw speech-to-text output into clean,
structured writing in ~200 ms on Apple Silicon:

- removes fillers ("um", "uh") and applies self-corrections ("no wait, almond milk")
- structures dictated lists — bullets, numbered steps, `- [ ]` checklists, multiple lists
- formats dictated emails
- **never answers questions** — a dictated question stays a question

## Usage (MLX)

```python
from mlx_lm import load, generate

model, tokenizer = load("REPO_ID_HERE")
raw = "camping list um tent headlamp and snacks as bullets"
out = generate(model, tokenizer, prompt=f"### Input:\n{raw}\n\n### Output:\n", max_tokens=256)
print(out.split("### Input:")[0].strip())
```

Note the model uses a raw completion contract (`### Input:` / `### Output:`),
not the chat template.

## Training

Post-trained from Qwen3.5-0.8B on a Mac Studio M3 Ultra with
[mlx-lm](https://github.com/ml-explore/mlx-lm) / [mlx-lm-lora](https://github.com/Goekdeniz-Guelmez/mlx-lm-lora).
The **entire pipeline is open source** — data generation, training scripts, the
rule-based verifier used as both eval scorer and RL reward, and all results
(including failed stages):
[`bench/polish_posttrain/`](https://github.com/vasanthsreeram/macwispr/tree/main/bench/polish_posttrain)
· [run log](https://github.com/vasanthsreeram/macwispr/tree/main/docs/context/post-training).

1. **SFT** — 2,400 iterations on dictation-polish pairs
2. **DPO** — gated out: it regressed structure diversity (documented in the run log)
3. **GRPO** — RL on hard categories with the open `polish_verifier` as reward
4. **4-bit quantization** (group size 64) for on-device shipping

## Evaluation

40-case out-of-distribution suite ([`ood_eval_set.jsonl`](https://github.com/vasanthsreeram/macwispr/blob/main/bench/polish_posttrain/ood_eval_set.jsonl)),
scored by the shared verifier; identical prompts sent to Claude Sonnet for comparison.

| System | Pass | Latency |
|---|---|---|
| **This model (SFT v3, 4-bit, on-device)** | **25/40 (62.5%)** | **196 ms** |
| Claude Sonnet (cloud API) | 25/40 (62.5%) | 4,407 ms |

Ties Claude Sonnet overall at ~23× lower latency. Strengths: checklists (4/4 —
Sonnet scores 0/4), prose/question preservation, email, mixed styles.
Known weaknesses: multiple lists in one dictation, numbered lists, bullets
regressed slightly vs v2 (2/4). v3 adds 311 synthetic hard-category examples
(Grok-drafted, verifier-validated) — published in the
[macwispr-polish-data](https://huggingface.co/datasets/vasanth009/macwispr-polish-data) dataset.

## Intended use & limitations

Built for one job: cleaning up English dictation transcripts. It is not a chat
model, not an assistant, and will refuse (by design) to answer questions —
it transcribes them. English-focused; short-form dictation (≤ ~150 words) works best.

## License

Weights: Apache 2.0 (inherited from Qwen3.5-0.8B). Training code: MIT
([MacWispr repo](https://github.com/vasanthsreeram/macwispr)).

#!/usr/bin/env python3
"""Generate DPO preference pairs via best-of-N sampling + verifier ranking.

For each prompt: sample N completions at high temperature from the SFT model,
score all with polish_verifier, take (best, worst) as (chosen, rejected) when
the margin is large enough. Output format matches mlx-lm-lora DPO expectations.

Usage:
  python gen_dpo_pairs.py --model <sft-model> --prompts <raws.jsonl> \
      --out dpo_pairs.jsonl [--n 8] [--temp 0.9] [--min-margin 0.5]

Prompts file: {"id": ..., "tags": [...], "raw": ...} per line (same as eval set).
Use training raws + fresh OOD raws; NEVER the eval suite (held out).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from mlx_lm import load
from mlx_lm.generate import generate
from mlx_lm.sample_utils import make_sampler

from polish_verifier import verify

PROMPT = "### Input:\n{raw}\n\n### Output:\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--prompts", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--n", type=int, default=8)
    ap.add_argument("--temp", type=float, default=0.9)
    ap.add_argument("--min-margin", type=float, default=0.5)
    ap.add_argument("--max-tokens", type=int, default=512)
    args = ap.parse_args()

    model, tokenizer = load(args.model)
    sampler = make_sampler(temp=args.temp, top_p=0.95)
    cases = [json.loads(l) for l in Path(args.prompts).read_text().splitlines() if l.strip()]

    kept = 0
    with open(args.out, "w") as f:
        for i, c in enumerate(cases):
            prompt = PROMPT.format(raw=c["raw"])
            scored = []
            for _ in range(args.n):
                out = generate(
                    model, tokenizer, prompt=prompt,
                    max_tokens=args.max_tokens, sampler=sampler,
                )
                out = out.split("### Input:")[0].strip()
                scored.append((verify(c["raw"], out, c["tags"]).score, out))
            scored.sort(key=lambda s: s[0], reverse=True)
            best, worst = scored[0], scored[-1]
            margin = best[0] - worst[0]
            if margin >= args.min_margin and best[1] != worst[1]:
                f.write(json.dumps({
                    "prompt": prompt,
                    "chosen": best[1],
                    "rejected": worst[1],
                    "margin": round(margin, 3),
                    "tags": c["tags"],
                }) + "\n")
                kept += 1
            print(f"{i + 1}/{len(cases)} {c.get('id', '?'):6s} "
                  f"best={best[0]:+.2f} worst={worst[0]:+.2f} kept={kept}")

    print(f"\nwrote {kept}/{len(cases)} pairs -> {args.out}")


if __name__ == "__main__":
    main()

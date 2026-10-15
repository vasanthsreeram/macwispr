#!/usr/bin/env python3
"""DPO v5 candidate mining — tiered cascade, GPU stage (no API key needed).

For each distill prompt (which carries a Flash-Lite reference polish):
sample N completions at high temperature from the current model, score each
with Tier 0 (rules: fact_retention + polish_verifier) and Tier 1
(embedding cosine + ROUGE-L vs the reference), and write ALL candidates
with their scores/bands. Pair assembly + Tier-2 judging happens later in
assemble_pairs_v5.py, so this stage never blocks on the Gemini API.

Usage (on the Studio):
  python gen_dpo_pairs_v5.py --model <fused-model> --distill data/distill.jsonl \
      --out data/candidates_v5.jsonl [--n 8] [--temp 0.9] [--limit 0]
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from mlx_lm import load
from mlx_lm.generate import generate
from mlx_lm.sample_utils import make_sampler

from fact_heuristic import fact_retention
from polish_verifier import verify
from similarity_reward import embed_cosine_batch, rouge_l_f1, HI, LO

PROMPT = "### Input:\n{raw}\n\n### Output:\n"
DISTILL_RE = re.compile(r"### Input:\n(.*?)\n\n### Output:\n(.*)", re.S)


def parse_distill(path: str) -> list[dict]:
    cases = []
    for line in Path(path).read_text().splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        m = DISTILL_RE.match(row["text"])
        if not m:
            continue
        raw, ref = m.group(1).strip(), m.group(2).strip()
        if raw and ref:
            cases.append({"raw": raw, "reference": ref,
                          "tags": row.get("tags", [])})
    return cases


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--distill", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--n", type=int, default=8)
    ap.add_argument("--temp", type=float, default=0.9)
    ap.add_argument("--max-tokens", type=int, default=512)
    ap.add_argument("--limit", type=int, default=0, help="0 = all prompts")
    args = ap.parse_args()

    cases = parse_distill(args.distill)
    if args.limit:
        cases = cases[:args.limit]
    print(f"{len(cases)} prompts with references")

    model, tokenizer = load(args.model)
    sampler = make_sampler(temp=args.temp, top_p=0.95)

    bands = {"accept": 0, "ambiguous": 0, "reject": 0}
    with open(args.out, "w") as f:
        for i, c in enumerate(cases):
            prompt = PROMPT.format(raw=c["raw"])
            outs = []
            for _ in range(args.n):
                out = generate(model, tokenizer, prompt=prompt,
                               max_tokens=args.max_tokens, sampler=sampler)
                outs.append(out.split("### Input:")[0].strip())
            cosines = embed_cosine_batch([(o, c["reference"]) for o in outs])
            cands = []
            for out, cos in zip(outs, cosines):
                fact = fact_retention(c["raw"], out)
                rules = verify(c["raw"], out, c.get("tags", [])).score
                rouge = rouge_l_f1(out, c["reference"])
                combined = 0.6 * cos + 0.4 * rouge
                band = ("accept" if combined >= HI else
                        "reject" if combined <= LO else "ambiguous")
                bands[band] += 1
                cands.append({"out": out, "fact": round(fact, 3),
                              "rules": round(rules, 3),
                              "cosine": round(cos, 4),
                              "rouge_l": round(rouge, 4),
                              "combined": round(combined, 4), "band": band})
            f.write(json.dumps({"raw": c["raw"], "reference": c["reference"],
                                "tags": c.get("tags", []),
                                "candidates": cands}) + "\n")
            if (i + 1) % 25 == 0:
                total = sum(bands.values())
                print(f"{i + 1}/{len(cases)}  bands: "
                      + " ".join(f"{k}={v / total:.0%}" for k, v in bands.items()),
                      flush=True)

    total = sum(bands.values())
    print(f"\ndone: {total} candidates from {len(cases)} prompts -> {args.out}")
    for k, v in bands.items():
        print(f"  {k:10s} {v:6d} ({v / total:.1%})")


if __name__ == "__main__":
    main()

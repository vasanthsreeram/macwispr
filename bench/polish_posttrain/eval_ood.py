#!/usr/bin/env python3
"""Run the OOD polish suite against an MLX model and score with polish_verifier.

Usage:
  python eval_ood.py --model <path> [--suite ood_eval_set.jsonl] [--out results.json]

Prompt format matches the app/training contract:
  ### Input:\n<raw>\n\n### Output:\n
"""
from __future__ import annotations

import argparse
import json
import time
from collections import defaultdict
from pathlib import Path

from mlx_lm import generate, load

from polish_verifier import verify

PROMPT = "### Input:\n{raw}\n\n### Output:\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--suite", default=str(Path(__file__).parent / "ood_eval_set.jsonl"))
    ap.add_argument("--out", default="")
    ap.add_argument("--max-tokens", type=int, default=512)
    args = ap.parse_args()

    model, tokenizer = load(args.model)
    cases = [json.loads(l) for l in Path(args.suite).read_text().splitlines() if l.strip()]

    results, by_tag = [], defaultdict(lambda: [0, 0])
    for c in cases:
        t0 = time.time()
        out = generate(
            model,
            tokenizer,
            prompt=PROMPT.format(raw=c["raw"]),
            max_tokens=args.max_tokens,
        )
        # Cut at a stray next-section marker if the model keeps going.
        out = out.split("### Input:")[0].strip()
        ms = (time.time() - t0) * 1000
        v = verify(c["raw"], out, c["tags"])
        for t in c["tags"]:
            by_tag[t][0] += int(v.passed)
            by_tag[t][1] += 1
        results.append(
            {
                "id": c["id"],
                "tags": c["tags"],
                "passed": v.passed,
                "score": round(v.score, 3),
                "latency_ms": round(ms),
                "feedback": v.feedback,
                "output": out,
            }
        )
        mark = "PASS" if v.passed else "FAIL"
        print(f"[{mark}] {c['id']:5s} {v.score:+.2f} {ms:6.0f}ms  {'; '.join(v.feedback)}")

    n_pass = sum(r["passed"] for r in results)
    lat = sorted(r["latency_ms"] for r in results)
    summary = {
        "model": args.model,
        "pass": f"{n_pass}/{len(results)}",
        "pass_rate": round(n_pass / len(results), 3),
        "mean_latency_ms": round(sum(lat) / len(lat)),
        "by_tag": {t: f"{p}/{n}" for t, (p, n) in sorted(by_tag.items())},
    }
    print("\n" + json.dumps(summary, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps({"summary": summary, "results": results}, indent=2))
        print(f"wrote {args.out}")


if __name__ == "__main__":
    main()

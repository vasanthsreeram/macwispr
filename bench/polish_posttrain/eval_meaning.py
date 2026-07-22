#!/usr/bin/env python3
"""Meaning-preservation bench: does polish keep every critical detail?

Usage:
  python eval_meaning.py --model <path> [--suite meaning_eval_set.jsonl] [--out results.json]
"""
from __future__ import annotations

import argparse
import json
import time
from collections import defaultdict
from pathlib import Path

from mlx_lm import generate, load

from meaning_verifier import verify_meaning

PROMPT = "### Input:\n{raw}\n\n### Output:\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--suite", default=str(Path(__file__).parent / "meaning_eval_set.jsonl"))
    ap.add_argument("--out", default="")
    ap.add_argument("--max-tokens", type=int, default=512)
    args = ap.parse_args()

    model, tokenizer = load(args.model)
    cases = [json.loads(l) for l in Path(args.suite).read_text().splitlines() if l.strip()]

    results, by_cat = [], defaultdict(lambda: [0, 0])
    facts_kept = facts_total = 0
    for c in cases:
        t0 = time.time()
        out = generate(
            model, tokenizer, prompt=PROMPT.format(raw=c["raw"]), max_tokens=args.max_tokens
        )
        out = out.split("### Input:")[0].strip()
        ms = (time.time() - t0) * 1000
        v = verify_meaning(out, c["must"], c.get("forbid"))
        by_cat[c["cat"]][0] += int(v.passed)
        by_cat[c["cat"]][1] += 1
        facts_kept += v.kept
        facts_total += v.total
        results.append(
            {
                "id": c["id"],
                "cat": c["cat"],
                "passed": v.passed,
                "score": round(v.score, 3),
                "kept": f"{v.kept}/{v.total}",
                "missing": v.missing,
                "flips": v.flips,
                "latency_ms": round(ms),
                "output": out,
            }
        )
        mark = "PASS" if v.passed else "FAIL"
        miss = f"  missing: {v.missing}" if v.missing else ""
        print(f"[{mark}] {c['id']:5s} kept {v.kept}/{v.total} {ms:6.0f}ms{miss}")

    n_pass = sum(r["passed"] for r in results)
    summary = {
        "model": args.model,
        "pass": f"{n_pass}/{len(results)}",
        "pass_rate": round(n_pass / len(results), 3),
        "fact_retention": round(facts_kept / facts_total, 3),
        "facts": f"{facts_kept}/{facts_total}",
        "by_cat": {k: f"{p}/{n}" for k, (p, n) in sorted(by_cat.items())},
    }
    print("\n" + json.dumps(summary, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps({"summary": summary, "results": results}, indent=2))
        print(f"wrote {args.out}")


if __name__ == "__main__":
    main()

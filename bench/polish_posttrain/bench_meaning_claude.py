#!/usr/bin/env python3
"""Run the meaning-preservation suite through Claude (via `claude -p`).

Usage:
  python bench_meaning_claude.py --claude-model sonnet --out results/meaning_sonnet.json
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from bench_vs_claude import run_claude
from meaning_verifier import verify_meaning


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", default=str(Path(__file__).parent / "meaning_eval_set.jsonl"))
    ap.add_argument("--claude-model", default="sonnet")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    cases = [json.loads(l) for l in Path(args.suite).read_text().splitlines() if l.strip()]

    def one(c):
        try:
            out, ms = run_claude(c["raw"], args.claude_model)
        except Exception as e:
            out, ms = f"[exception {e}]", 0.0
        v = verify_meaning(out, c["must"], c.get("forbid"))
        mark = "PASS" if v.passed else "FAIL"
        miss = f"  missing: {v.missing}" if v.missing else ""
        print(f"[{mark}] {c['id']:5s} kept {v.kept}/{v.total} {ms:6.0f}ms{miss}", flush=True)
        return {
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

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        results = list(ex.map(one, cases))

    by_cat = defaultdict(lambda: [0, 0])
    facts_kept = facts_total = 0
    for r, c in zip(results, cases):
        by_cat[r["cat"]][0] += int(r["passed"])
        by_cat[r["cat"]][1] += 1
        k, t = map(int, r["kept"].split("/"))
        facts_kept += k
        facts_total += t
    n_pass = sum(r["passed"] for r in results)
    summary = {
        "model": f"claude:{args.claude_model}",
        "pass": f"{n_pass}/{len(results)}",
        "pass_rate": round(n_pass / len(results), 3),
        "fact_retention": round(facts_kept / facts_total, 3),
        "facts": f"{facts_kept}/{facts_total}",
        "by_cat": {k: f"{p}/{n}" for k, (p, n) in sorted(by_cat.items())},
    }
    print("\n" + json.dumps(summary, indent=2))
    out_path = args.out or str(
        Path(__file__).parent / "results" / f"meaning_claude_{args.claude_model}.json"
    )
    Path(out_path).write_text(json.dumps({"summary": summary, "results": results}, indent=2))
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()

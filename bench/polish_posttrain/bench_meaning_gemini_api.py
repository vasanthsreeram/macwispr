#!/usr/bin/env python3
"""Run the meaning-preservation suite through the Gemini REST API.

Reads key from env GEMINI_API_KEY (never hard-coded).
Usage: GEMINI_API_KEY=... python bench_meaning_gemini_api.py --model gemini-flash-lite-latest
"""
from __future__ import annotations

import argparse
import json
import os
import time
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from bench_vs_claude import SYSTEM
from meaning_verifier import verify_meaning

KEY = os.environ["GEMINI_API_KEY"]
URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


NO_THINK = False  # set via --no-think: disable reasoning (thinkingBudget 0)


def run_gemini(raw: str, model: str, timeout: int = 120) -> tuple[str, float]:
    gen_cfg = {"temperature": 0.0}
    if NO_THINK:
        gen_cfg["thinkingConfig"] = {"thinkingBudget": 0}
    body = json.dumps({
        "systemInstruction": {"parts": [{"text": SYSTEM}]},
        "contents": [{"parts": [{"text": f"### Input:\n{raw}\n\n### Output:\n"}]}],
        "generationConfig": gen_cfg,
    }).encode()
    req = urllib.request.Request(
        URL.format(model=model), data=body,
        headers={"x-goog-api-key": KEY, "Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        d = json.loads(r.read())
    ms = (time.time() - t0) * 1000
    try:
        parts = d["candidates"][0]["content"]["parts"]
        out = "".join(p.get("text", "") for p in parts).strip()
    except (KeyError, IndexError):
        out = f"[no_text {json.dumps(d)[:200]}]"
    return out.split("### Input:")[0].strip(), ms


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", default=str(Path(__file__).parent / "meaning_eval_set.jsonl"))
    ap.add_argument("--model", default="gemini-flash-lite-latest")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--no-think", action="store_true", help="disable reasoning (thinkingBudget 0)")
    ap.add_argument("--out", default="")
    args = ap.parse_args()
    global NO_THINK
    NO_THINK = args.no_think

    cases = [json.loads(l) for l in Path(args.suite).read_text().splitlines() if l.strip()]

    def one(c):
        try:
            out, ms = run_gemini(c["raw"], args.model)
        except Exception as e:
            out, ms = f"[exception {e}]", 0.0
        v = verify_meaning(out, c["must"], c.get("forbid"))
        mark = "PASS" if v.passed else "FAIL"
        miss = f"  missing: {v.missing}" if v.missing else ""
        print(f"[{mark}] {c['id']:5s} kept {v.kept}/{v.total} {ms:6.0f}ms{miss}", flush=True)
        return {"id": c["id"], "cat": c["cat"], "passed": v.passed, "score": round(v.score, 3),
                "kept": f"{v.kept}/{v.total}", "missing": v.missing, "flips": v.flips,
                "latency_ms": round(ms), "output": out}

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        results = list(ex.map(one, cases))

    by_cat = defaultdict(lambda: [0, 0])
    fk = ft = 0
    for r in results:
        by_cat[r["cat"]][0] += int(r["passed"])
        by_cat[r["cat"]][1] += 1
        k, t = map(int, r["kept"].split("/"))
        fk += k
        ft += t
    n_pass = sum(r["passed"] for r in results)
    summary = {"model": f"gemini-api:{args.model}", "pass": f"{n_pass}/{len(results)}",
               "pass_rate": round(n_pass / len(results), 3),
               "fact_retention": round(fk / ft, 3), "facts": f"{fk}/{ft}",
               "by_cat": {k: f"{p}/{n}" for k, (p, n) in sorted(by_cat.items())}}
    print("\n" + json.dumps(summary, indent=2))
    out_path = args.out or str(Path(__file__).parent / "results" / f"meaning_gemini_api_{args.model}.json")
    Path(out_path).write_text(json.dumps({"summary": summary, "results": results}, indent=2))
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()

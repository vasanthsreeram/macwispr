#!/usr/bin/env python3
"""DPO v5 pair assembly — cascade Tier 2 (judge) + pair construction.

Reads candidates_v5.jsonl from gen_dpo_pairs_v5.py and builds DPO pairs:

chosen:
  1. best accept-band candidate that passes rules (fact == max fact) — free
  2. else: judge the best ambiguous candidate vs the reference (Flash-Lite);
     if the judge approves, it becomes chosen
  3. else: the REFERENCE itself becomes chosen (teacher-as-chosen — the
     student never produced an acceptable polish, strongest learning signal)
rejected:
  worst real student sample (reject band preferred, lowest combined score,
  lowest fact) — always a real student mistake, never synthetic.

Without GEMINI_API_KEY, step 2 is skipped (falls through to 3) so the
pipeline degrades gracefully instead of blocking.

Usage:
  GEMINI_API_KEY=... python assemble_pairs_v5.py \
      --candidates data/candidates_v5.jsonl --out data/dpo_pairs_v5.jsonl \
      [--max-judge 4000] [--workers 6]
"""
from __future__ import annotations

import argparse
import json
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

PROMPT = "### Input:\n{raw}\n\n### Output:\n"


def pick_rejected(cands: list[dict], chosen_text: str) -> dict | None:
    pool = [c for c in cands if c["out"] != chosen_text and c["out"].strip()]
    if not pool:
        return None
    # real student mistakes first: reject band, then lowest fact, lowest combined
    pool.sort(key=lambda c: (c["band"] != "reject", c["fact"], c["combined"]))
    worst = pool[0]
    # a "rejected" that is itself near-perfect teaches nothing — require a gap
    if worst["band"] == "accept" and worst["fact"] >= 1.0:
        return None
    return worst


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-judge", type=int, default=4000)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--stats-only", action="store_true")
    args = ap.parse_args()

    have_key = bool(os.environ.get("GEMINI_API_KEY"))
    if have_key:
        from judge_gemini import judge_vs_reference

    rows = [json.loads(l) for l in
            Path(args.candidates).read_text().splitlines() if l.strip()]

    pairs, judge_queue = [], []
    stats = {"free_accept": 0, "needs_judge": 0, "teacher_chosen": 0,
             "no_pair": 0}

    for row in rows:
        cands = row["candidates"]
        max_fact = max(c["fact"] for c in cands)
        accepts = [c for c in cands
                   if c["band"] == "accept" and c["fact"] >= max_fact]
        if accepts:
            chosen = max(accepts, key=lambda c: c["combined"])
            rej = pick_rejected(cands, chosen["out"])
            if rej:
                stats["free_accept"] += 1
                pairs.append((row, chosen["out"], rej["out"], "free_accept"))
            else:
                stats["no_pair"] += 1
            continue
        ambigs = [c for c in cands if c["band"] == "ambiguous" and c["fact"] >= max_fact]
        if ambigs and have_key and len(judge_queue) < args.max_judge:
            stats["needs_judge"] += 1
            judge_queue.append((row, max(ambigs, key=lambda c: c["combined"])))
        else:
            # student never acceptable -> teacher-as-chosen
            rej = pick_rejected(cands, row["reference"])
            if rej:
                stats["teacher_chosen"] += 1
                pairs.append((row, row["reference"], rej["out"], "teacher"))
            else:
                stats["no_pair"] += 1

    print(f"stage 1: {stats}")
    if args.stats_only:
        return

    if judge_queue:
        print(f"judging {len(judge_queue)} ambiguous candidates via Flash-Lite...")

        def work(item):
            row, cand = item
            try:
                v = judge_vs_reference(row["raw"], cand["out"], row["reference"])
                return row, cand, v.get("ok", False)
            except Exception as e:
                print(f"judge error: {e}")
                return row, cand, None  # None = API failure, fall to teacher

        with ThreadPoolExecutor(args.workers) as ex:
            for i, (row, cand, ok) in enumerate(ex.map(work, judge_queue), 1):
                if ok:
                    rej = pick_rejected(row["candidates"], cand["out"])
                    if rej:
                        pairs.append((row, cand["out"], rej["out"], "judge_ok"))
                        continue
                # judge said no (or errored): teacher-as-chosen, judged cand
                # becomes a strong rejected if the judge explicitly failed it
                rej = (cand if ok is False else
                       pick_rejected(row["candidates"], row["reference"]))
                if rej:
                    rej_out = rej["out"] if isinstance(rej, dict) else rej
                    pairs.append((row, row["reference"], rej_out, "judge_rejected"))
                if i % 100 == 0:
                    print(f"  {i}/{len(judge_queue)}", flush=True)

    src_counts = {}
    with open(args.out, "w") as f:
        for row, chosen, rejected, src in pairs:
            if chosen.strip() == rejected.strip():
                continue
            src_counts[src] = src_counts.get(src, 0) + 1
            f.write(json.dumps({
                "prompt": PROMPT.format(raw=row["raw"]),
                "chosen": chosen, "rejected": rejected,
                "source": src, "tags": row.get("tags", []),
            }) + "\n")

    total = sum(src_counts.values())
    print(f"\nwrote {total} pairs -> {args.out}")
    for k, v in sorted(src_counts.items()):
        print(f"  {k:15s} {v:6d}")


if __name__ == "__main__":
    main()

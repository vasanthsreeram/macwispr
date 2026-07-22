#!/usr/bin/env python3
"""Re-score saved eval result JSONs with the current polish_verifier.

Usage: python rescore_results.py results/ood_sft_v3.json [...]
Writes <name>_rescored.json next to each input and prints a summary table.
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

from polish_verifier import verify

HERE = Path(__file__).parent
EVAL = {
    json.loads(l)["id"]: json.loads(l)
    for l in (HERE / "ood_eval_set.jsonl").read_text().splitlines()
    if l.strip()
}

for path in map(Path, sys.argv[1:]):
    d = json.loads(path.read_text())
    tag_pass, tag_tot = defaultdict(int), defaultdict(int)
    passed = 0
    for c in d["results"]:
        case = EVAL[c["id"]]
        v = verify(case["raw"], c["output"], case["tags"])
        c["passed"], c["score"], c["feedback"] = v.passed, v.score, v.feedback
        passed += v.passed
        for t in case["tags"]:
            tag_tot[t] += 1
            tag_pass[t] += v.passed
    total = len(d["results"])
    d["summary"]["pass"] = f"{passed}/{total}"
    d["summary"]["pass_rate"] = passed / total
    d["summary"]["by_tag"] = {
        t: f"{tag_pass[t]}/{tag_tot[t]}" for t in sorted(tag_tot)
    }
    out = path.with_name(path.stem + "_rescored.json")
    out.write_text(json.dumps(d, indent=2))
    print(f"{path.name}: {passed}/{total} ({passed/total:.1%})")
    print("  ", d["summary"]["by_tag"])

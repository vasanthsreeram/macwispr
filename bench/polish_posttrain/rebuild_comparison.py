#!/usr/bin/env python3
"""Rebuild the local-vs-Claude comparison from a fresh local OOD run and
cached Claude results (no new Claude API calls).

Usage:
  python rebuild_comparison.py \
    --local results/ood_sft_v2_4bit.json \
    --cached results/bench_vs_claude_sonnet.json \
    --out results/bench_vs_claude_sonnet_v2
"""
import argparse
import json
from pathlib import Path

TAG_ORDER = [
    "multi_list", "mixed_styles", "format_numbered", "format_bullets",
    "format_checklist", "preserve_prose", "preserve_question", "email",
]


def summarize(rows):
    by_tag = {}
    for r in rows:
        for t in r["tags"]:
            p, n = by_tag.get(t, (0, 0))
            by_tag[t] = (p + (1 if r["passed"] else 0), n + 1)
    n_pass = sum(1 for r in rows if r["passed"])
    lat = [r["latency_ms"] for r in rows if r.get("latency_ms")]
    return {
        "pass": f"{n_pass}/{len(rows)}",
        "pass_rate": round(n_pass / len(rows), 3),
        "mean_latency_ms": round(sum(lat) / max(1, len(lat))),
        "by_tag": {t: f"{p}/{n}" for t, (p, n) in sorted(by_tag.items())},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--local", required=True)
    ap.add_argument("--cached", required=True)
    ap.add_argument("--local-name", default="Local Qwen 4-bit (structure-v2 SFT)")
    ap.add_argument("--claude-name", default="Claude sonnet (cached run)")
    ap.add_argument("--out", required=True, help="output path stem (.json/.md added)")
    args = ap.parse_args()

    local = json.loads(Path(args.local).read_text())
    local_rows = local["results"]
    cached = json.loads(Path(args.cached).read_text())
    claude_rows = cached["claude_results"]

    by_id = {r["id"]: r for r in claude_rows}
    pairs = [(a, by_id[a["id"]]) for a in local_rows if a["id"] in by_id]
    if len(pairs) != len(local_rows):
        print(f"warning: only {len(pairs)}/{len(local_rows)} ids matched cached claude rows")

    local_sum = summarize([a for a, _ in pairs])
    claude_sum = summarize([b for _, b in pairs])
    both = sum(1 for a, b in pairs if a["passed"] and b["passed"])
    only_l = sum(1 for a, b in pairs if a["passed"] and not b["passed"])
    only_c = sum(1 for a, b in pairs if b["passed"] and not a["passed"])
    agree = sum(1 for a, b in pairs if a["passed"] == b["passed"])

    out = {
        "suite": cached.get("suite"),
        "n": len(pairs),
        "local": {**local_sum, "model": local["summary"].get("model")},
        "claude": claude_sum,
        "agreement": {
            "agree": agree, "both_pass": both,
            "only_local_pass": only_l, "only_claude_pass": only_c,
        },
        "local_results": [a for a, _ in pairs],
        "claude_results": [b for _, b in pairs],
        "note": "Claude side reused from cached run; only local side re-evaluated.",
    }
    Path(args.out + ".json").write_text(json.dumps(out, indent=2))

    tags = [t for t in TAG_ORDER if t in local_sum["by_tag"]]

    def row(name, s):
        cells = " | ".join(s["by_tag"].get(t, "-") for t in tags)
        return (f"| {name} | {s['pass']} ({round(100 * s['pass_rate'])}%) "
                f"| {cells} | {s['mean_latency_ms']} ms |")

    header_tags = " | ".join(t.replace("format_", "") for t in tags)
    md = [
        f"# Polish bench: local vs Claude sonnet (cached)",
        "",
        f"Suite: `{out['suite']}` (n={out['n']})",
        "Claude outputs reused from the original run; local side re-evaluated.",
        "",
        f"| System | Pass | {header_tags} | mean lat |",
        f"|--------|-----:|{'---:|' * len(tags)}---------:|",
        row(args.local_name, local_sum),
        row(args.claude_name, claude_sum),
        "",
        f"Agreement on pass/fail: **{agree}/{out['n']}** "
        f"(both pass {both}, only local {only_l}, only Claude {only_c}).",
        "",
    ]
    Path(args.out + ".md").write_text("\n".join(md))
    print(json.dumps({"local": local_sum, "claude": claude_sum, "agreement": out["agreement"]}, indent=2))
    print("wrote", args.out + ".json", "and .md")


if __name__ == "__main__":
    main()

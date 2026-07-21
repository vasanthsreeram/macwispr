#!/usr/bin/env python3
"""Compare local polish pack (precomputed OOD JSON) vs Claude on the same suite.

Local model results: pass a prior eval_ood.py JSON (Studio/Mac).
Claude: `claude -p --model sonnet` with the same ### Input / ### Output contract.

Usage:
  python bench_vs_claude.py \\
    --suite ood_eval_set.jsonl \\
    --local-json results/ood_local_4bit.json \\
    --out results/bench_vs_claude_sonnet.json
"""
from __future__ import annotations

import argparse
import json
import subprocess
import time
from collections import defaultdict
from pathlib import Path

from polish_verifier import verify

SYSTEM = """You polish speech-to-text transcripts for a dictation app.
Rules:
- Fix punctuation, capitalization, filler words, and course-corrections.
- Structure lists when the user clearly intended lists (numbered, bullets, checklists, multi-section headings).
- Do NOT answer questions or add facts not in the transcript.
- Output ONLY the polished transcript text — no preamble, no markdown fences, no commentary."""

USER_TMPL = """### Input:
{raw}

### Output:
"""


def run_claude(raw: str, model: str, timeout: int = 120) -> tuple[str, float]:
    user = USER_TMPL.format(raw=raw)
    t0 = time.time()
    proc = subprocess.run(
        # Use --system-prompt so Claude Code acts as polish model, not coding agent.
        # Do not use --bare: that skips OAuth/keychain ("Not logged in").
        ["claude", "-p", "--model", model, "--system-prompt", SYSTEM, user],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    ms = (time.time() - t0) * 1000
    out = (proc.stdout or "").strip()
    if proc.returncode != 0 and not out:
        err = (proc.stderr or "").strip()[:300]
        out = f"[claude_error rc={proc.returncode}] {err}"
    # Strip accidental fences / thinking
    if out.startswith("```"):
        lines = out.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        out = "\n".join(lines).strip()
    out = out.split("### Input:")[0].strip()
    return out, ms


def summarize(rows: list[dict], model_label: str) -> dict:
    by_tag: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for r in rows:
        for t in r["tags"]:
            by_tag[t][0] += int(r["passed"])
            by_tag[t][1] += 1
    n = len(rows)
    n_pass = sum(int(r["passed"]) for r in rows)
    lats = [r["latency_ms"] for r in rows if r.get("latency_ms") is not None]
    return {
        "model": model_label,
        "pass": f"{n_pass}/{n}",
        "pass_rate": round(n_pass / max(1, n), 3),
        "mean_latency_ms": round(sum(lats) / max(1, len(lats))) if lats else None,
        "by_tag": {t: f"{p}/{n}" for t, (p, n) in sorted(by_tag.items())},
        "leak_count": sum(
            1 for r in rows if any("answer_leak" in f for f in r.get("feedback", []))
        ),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", default=str(Path(__file__).parent / "ood_eval_set.jsonl"))
    ap.add_argument("--local-json", required=True, help="eval_ood.py results for local pack")
    ap.add_argument("--claude-model", default="sonnet")
    ap.add_argument("--limit", type=int, default=0, help="0 = all cases")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    cases = [json.loads(l) for l in Path(args.suite).read_text().splitlines() if l.strip()]
    if args.limit:
        cases = cases[: args.limit]

    local_blob = json.loads(Path(args.local_json).read_text())
    local_by_id = {r["id"]: r for r in local_blob["results"]}

    local_rows = []
    claude_rows = []
    for i, c in enumerate(cases):
        cid = c["id"]
        tags = c["tags"]
        raw = c["raw"]

        # Local: reuse prior run if present
        lr = local_by_id.get(cid)
        if lr:
            local_rows.append(
                {
                    "id": cid,
                    "tags": tags,
                    "passed": lr["passed"],
                    "score": lr["score"],
                    "latency_ms": lr.get("latency_ms"),
                    "feedback": lr.get("feedback", []),
                    "output": lr.get("output", ""),
                }
            )
        else:
            local_rows.append(
                {
                    "id": cid,
                    "tags": tags,
                    "passed": False,
                    "score": 0.0,
                    "latency_ms": None,
                    "feedback": ["missing_local_result"],
                    "output": "",
                }
            )

        print(f"[{i+1}/{len(cases)}] claude {cid}…", flush=True)
        try:
            out, ms = run_claude(raw, args.claude_model)
        except subprocess.TimeoutExpired:
            out, ms = "[timeout]", 120000.0
        except Exception as e:
            out, ms = f"[exception {e}]", 0.0
        v = verify(raw, out, tags)
        claude_rows.append(
            {
                "id": cid,
                "tags": tags,
                "passed": v.passed,
                "score": round(v.score, 3),
                "latency_ms": round(ms),
                "feedback": v.feedback,
                "output": out,
            }
        )
        mark = "PASS" if v.passed else "FAIL"
        print(
            f"  claude [{mark}] {v.score:+.2f} {ms:.0f}ms  "
            f"local={'PASS' if local_rows[-1]['passed'] else 'FAIL'}",
            flush=True,
        )

    local_sum = summarize(local_rows, local_blob.get("summary", {}).get("model", "local_4bit"))
    claude_sum = summarize(claude_rows, f"claude:{args.claude_model}")

    # Per-id agreement
    agree = sum(
        1
        for a, b in zip(local_rows, claude_rows)
        if a["passed"] == b["passed"]
    )
    both_pass = sum(1 for a, b in zip(local_rows, claude_rows) if a["passed"] and b["passed"])
    only_local = sum(1 for a, b in zip(local_rows, claude_rows) if a["passed"] and not b["passed"])
    only_claude = sum(1 for a, b in zip(local_rows, claude_rows) if b["passed"] and not a["passed"])

    report = {
        "suite": args.suite,
        "n": len(cases),
        "local": local_sum,
        "claude": claude_sum,
        "agreement": {
            "same_pass_fail": f"{agree}/{len(cases)}",
            "both_pass": both_pass,
            "only_local_pass": only_local,
            "only_claude_pass": only_claude,
        },
        "local_results": local_rows,
        "claude_results": claude_rows,
    }

    print("\n======== SUMMARY ========")
    print("LOCAL ", json.dumps(local_sum, indent=2))
    print("CLAUDE", json.dumps(claude_sum, indent=2))
    print("AGREE ", report["agreement"])

    out_path = args.out or str(
        Path(__file__).parent / "results" / f"bench_vs_claude_{args.claude_model}.json"
    )
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text(json.dumps(report, indent=2))
    print(f"wrote {out_path}")

    # Markdown table
    md_path = Path(out_path).with_suffix(".md")
    lines = [
        f"# Polish bench: local 4-bit vs Claude `{args.claude_model}`",
        "",
        f"Suite: `{args.suite}` (n={len(cases)})",
        "Scorer: shared `polish_verifier.py` (same rules as training RL).",
        "",
        "| System | Pass | multi_list | mixed | numbered | bullets | checklist | prose | question | email | mean lat |",
        "|--------|-----:|-----------:|------:|---------:|--------:|----------:|------:|---------:|------:|---------:|",
    ]

    def row(label: str, s: dict) -> str:
        bt = s.get("by_tag", {})
        return (
            f"| {label} | {s['pass']} ({s['pass_rate']*100:.0f}%) "
            f"| {bt.get('multi_list','—')} | {bt.get('mixed_styles','—')} "
            f"| {bt.get('format_numbered','—')} | {bt.get('format_bullets','—')} "
            f"| {bt.get('format_checklist','—')} | {bt.get('preserve_prose','—')} "
            f"| {bt.get('preserve_question','—')} | {bt.get('email','—')} "
            f"| {s.get('mean_latency_ms')} ms |"
        )

    lines.append(row("Local Qwen 4-bit (structure-v2-dpo)", local_sum))
    lines.append(row(f"Claude {args.claude_model}", claude_sum))
    lines += [
        "",
        f"Agreement on pass/fail: **{report['agreement']['same_pass_fail']}** "
        f"(both pass {both_pass}, only local {only_local}, only Claude {only_claude}).",
        "",
        "## Notes",
        "- Local numbers reuse Studio `eval_ood.py` run (mean ~200 ms on M3 Ultra).",
        "- Claude latency is end-to-end CLI (network + API), not pure model time.",
        "- Same polish contract: clean transcript only; structure lists; never answer questions.",
        "",
    ]
    md_path.write_text("\n".join(lines))
    print(f"wrote {md_path}")


if __name__ == "__main__":
    main()

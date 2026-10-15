"""Tier-2 LLM judge (Gemini Flash-Lite): pairwise, rubric-scored.

Only called on the ambiguous band from similarity_reward — the cases rules
and embeddings can't decide. Pairwise (A vs B for the same raw input) is
where LLM judges are reliable (~80-85% human agreement); absolute yes/no
is not. Candidate order is randomized per call to cancel position bias.

Usage (library):
    from judge_gemini import judge_pair
    verdict = judge_pair(raw, cand_a, cand_b)   # {"winner": "A"|"B"|"tie", ...}

Requires GEMINI_API_KEY in the environment. NEVER hardcode the key.
"""
from __future__ import annotations

import json
import os
import random
import time
import urllib.request

MODEL = "gemini-flash-lite-latest"
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"

RUBRIC = """You judge two polished versions (A and B) of a raw speech-to-text dictation.
The polish should: fix punctuation/casing, remove fillers and self-corrections,
structure lists when clearly intended, and preserve EVERY fact — numbers, names,
dates, negations, spoken forms like "twelfth"->"12th" or "thirty five fifty"->"$35.50"
count as preserved when the meaning is identical.

Score each version 0-2 on each dimension:
- meaning: all facts/details preserved, nothing invented or dropped
- formatting: punctuation, casing, list structure appropriate to intent
- fluency: reads naturally, no repetition or awkwardness

Reply with ONLY this JSON, no other text:
{"a": {"meaning": 0-2, "formatting": 0-2, "fluency": 0-2},
 "b": {"meaning": 0-2, "formatting": 0-2, "fluency": 0-2},
 "winner": "A" | "B" | "tie"}"""


def _call(prompt: str, timeout: int = 60, retries: int = 3) -> str:
    key = os.environ["GEMINI_API_KEY"]
    body = json.dumps({
        "system_instruction": {"parts": [{"text": RUBRIC}]},
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.0, "maxOutputTokens": 256,
                             "responseMimeType": "application/json"},
    }).encode()
    req = urllib.request.Request(
        f"{URL}?key={key}", data=body,
        headers={"Content-Type": "application/json"})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.load(resp)
            return data["candidates"][0]["content"]["parts"][0]["text"]
        except Exception:
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)
    raise RuntimeError("unreachable")


def judge_pair(raw: str, cand_a: str, cand_b: str, rng: random.Random | None = None) -> dict:
    """Judge two candidates for the same raw input. Order-randomized."""
    rng = rng or random
    flipped = rng.random() < 0.5
    first, second = (cand_b, cand_a) if flipped else (cand_a, cand_b)
    prompt = f"Raw dictation:\n{raw}\n\nVersion A:\n{first}\n\nVersion B:\n{second}"
    verdict = json.loads(_call(prompt))
    if flipped:  # un-flip so the caller's A is always A
        verdict["a"], verdict["b"] = verdict["b"], verdict["a"]
        verdict["winner"] = {"A": "B", "B": "A"}.get(verdict["winner"], verdict["winner"])
    # meaning dominates: a fluent-but-lossy version must not win on style
    for k in ("a", "b"):
        v = verdict[k]
        v["total"] = 2 * v["meaning"] + v["formatting"] + v["fluency"]
    return verdict


def judge_vs_reference(raw: str, candidate: str, reference: str) -> dict:
    """Judge a candidate against the trusted reference. Returns verdict plus
    an 'ok' bool: candidate is acceptable iff it ties or beats the reference
    on meaning (>=) and is not clearly worse overall."""
    v = judge_pair(raw, candidate, reference)
    v["ok"] = (v["a"]["meaning"] >= v["b"]["meaning"]
               and v["a"]["meaning"] == 2
               and v["a"]["total"] >= v["b"]["total"] - 1)
    return v


if __name__ == "__main__":
    import argparse
    from pathlib import Path

    ap = argparse.ArgumentParser()
    ap.add_argument("--pairs", required=True,
                    help="jsonl with {raw, candidate, reference} per line")
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=6)
    args = ap.parse_args()

    from concurrent.futures import ThreadPoolExecutor

    rows = [json.loads(l) for l in Path(args.pairs).read_text().splitlines() if l.strip()]

    def work(r):
        try:
            return {**r, "judge": judge_vs_reference(r["raw"], r["candidate"], r["reference"])}
        except Exception as e:
            return {**r, "judge": {"error": str(e)}}

    with ThreadPoolExecutor(args.workers) as ex, open(args.out, "w") as f:
        for i, res in enumerate(ex.map(work, rows), 1):
            f.write(json.dumps(res) + "\n")
            if i % 50 == 0:
                print(f"{i}/{len(rows)}")
    oks = sum(1 for l in Path(args.out).read_text().splitlines()
              if json.loads(l).get("judge", {}).get("ok"))
    print(f"done: {oks}/{len(rows)} ok -> {args.out}")

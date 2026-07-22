#!/usr/bin/env python3
"""Distillation corpus generator: Flash-Lite produces diverse (raw, gold) pairs.

Each API call returns a batch of samples as JSON. Every pair is verified with
fact_heuristic (gold must retain the raw's numbers/negations) and, when tagged,
polish_verifier — lossy or malformed pairs are rejected before writing.

Diversity comes from random (domain, fact-mix, style, length) seeds per call.

Usage: GEMINI_API_KEY=... python gen_distill_flashlite.py --n 20000 --out data/distill_flashlite.jsonl
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from fact_heuristic import fact_retention
from polish_verifier import verify

KEY = os.environ.get("GEMINI_API_KEY", "")
URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

DOMAINS = [
    "home renovation", "a work standup", "travel planning", "a grocery run",
    "medical/vet instructions", "a legal or insurance note", "software bug triage",
    "event planning", "personal finance", "a recipe", "moving house", "car repair",
    "a school/kids logistics note", "gym/training plan", "a client email",
    "meeting action items", "a shopping comparison", "scheduling across timezones",
]
FACT_MIXES = [
    "spelled-out money amounts (e.g. 'twenty two fifty')",
    "a phone number said digit by digit",
    "a spoken password or code with letters and numbers",
    "at least two negations ('do not', 'not the', 'except')",
    "specific dates and times said casually",
    "named people with role assignments",
    "numeric thresholds and percentages",
    "quantities with units (kg, ml, cm)",
    "a conditional ('only if', 'otherwise')",
    "version numbers or model numbers",
]
# Weighted toward the HARD/rare tags we most need (mixed_styles, numbered, questions).
STYLES = [
    "numbered steps plus a separate bullet list of notes (mixed styles)",
    "numbered steps plus a separate bullet list of notes (mixed styles)",
    "an ordered numbered list", "an ordered numbered list",
    "two sections each with a heading and a list (multi-list)",
    "a question that must stay a question (do not answer it)",
    "a checklist", "a bulleted list", "plain corrected prose",
    "a short email with greeting and sign-off",
]
LENGTHS = ["short (1-2 sentences)", "medium (3-5 sentences)", "long (6+ sentences, several facts)"]
# Vary the SHAPE so dictations don't all start "for the X..."
SHAPES = [
    "a reminder to yourself", "an instruction to a named person",
    "a message relaying what someone else said", "a quick multi-topic brain-dump",
    "a question you're asking", "a correction-heavy rambling note",
    "a terse list of items", "a decision with its reasoning",
]

PROMPT_TMPL = """You generate training data for a speech-to-text POLISH model.
ALL text MUST be in ENGLISH (US), including names — never any other language.
Produce {k} samples as a JSON array. They MUST be DISTINCT from each other:
vary the scenario, the people, the numbers, the sentence openings (do NOT start
every one with "for the..."), and the dictation shape. Each raw should read like
{shape}. Each sample is an object:
{{"raw": <messy dictation transcript>, "gold": <polished version>, "tags": [<optional format tags>]}}

The "raw" must read like a real voice dictation: no capitalization or punctuation,
and filler words ("um", "like", "you know"). Self-corrections are ONLY on wording
or filler (e.g. "send it uh I mean email it") — NEVER on a number, name, code, or
key fact. Include 3-6 (NOT more) hard facts, drawn from: {facts}. Every number,
name, and code you state is FINAL and must appear in the gold.
Domain: {domain}. Target length: {length}.

The "gold" is the correctly polished note in this style: {style}. The gold MUST:
- preserve EVERY number, name, code, and negation exactly as stated in the raw
- NEVER invent facts, numbers, times, or details that are not in the raw
- remove filler; keep it a faithful cleanup, not a summary or expansion
- NOT answer questions or add information not in the raw

tags (only if the gold uses that structure): any of multi_list, mixed_styles,
format_numbered, format_bullets, format_checklist, email, preserve_question, preserve_prose.
Return ONLY the JSON array, no markdown fence."""


def _build_prompt(seed_idx: int, k: int) -> str:
    import random
    rng = random.Random(seed_idx * 7919 + 1)
    return PROMPT_TMPL.format(
        k=k,
        facts=", ".join(rng.sample(FACT_MIXES, rng.randint(1, 3))),
        domain=rng.choice(DOMAINS),
        length=rng.choice(LENGTHS),
        style=rng.choice(STYLES),
        shape=rng.choice(SHAPES),
    )


def _extract_json_array(txt: str) -> list[dict]:
    txt = txt.strip()
    if txt.startswith("```"):
        txt = re.sub(r"^```[a-z]*\n?|\n?```$", "", txt).strip()
    i, j = txt.find("["), txt.rfind("]")
    if i >= 0 and j > i:
        txt = txt[i:j + 1]
    try:
        arr = json.loads(txt)
    except json.JSONDecodeError:
        return []
    return arr if isinstance(arr, list) else []


def gen_batch_api(seed_idx: int, k: int, model: str) -> list[dict]:
    body = json.dumps({
        "contents": [{"parts": [{"text": _build_prompt(seed_idx, k)}]}],
        "generationConfig": {"temperature": 1.0, "responseMimeType": "application/json"},
    }).encode()
    req = urllib.request.Request(
        URL.format(model=model), data=body,
        headers={"x-goog-api-key": KEY, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        d = json.loads(r.read())
    txt = "".join(p.get("text", "") for p in d["candidates"][0]["content"]["parts"])
    return _extract_json_array(txt)


def gen_batch_agy(seed_idx: int, k: int, model: str) -> list[dict]:
    prompt = _build_prompt(seed_idx, k) + "\n\nOutput ONLY the raw JSON array."
    p = subprocess.run(
        ["agy", "-p", prompt, "--model", model, "--dangerously-skip-permissions"],
        capture_output=True, text=True, timeout=180,
    )
    return _extract_json_array(p.stdout or "")


def accept(sample: dict) -> tuple[bool, str]:
    raw, gold, tags = sample.get("raw", ""), sample.get("gold", ""), sample.get("tags", [])
    if not raw or not gold or len(gold) < 5:
        return False, "empty/short"
    if not raw.isascii() or not gold.isascii():
        return False, "non-english"
    # Faithfulness is the bar that matters for SFT: every fact preserved, nothing
    # invented. Self-assigned format tags are NOT trusted (the model often
    # mislabels a fine output), so they don't gate — but a gold that just echoes
    # the raw unchanged (no cleanup at all) is useless.
    if fact_retention(raw, gold) < 1.0:
        return False, "fact-drop"
    if gold.strip().lower() == raw.strip().lower():
        return False, "no-cleanup"
    return True, "ok"


def main() -> None:
    from collections import Counter
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=20000)
    ap.add_argument("--per-call", type=int, default=10)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--backend", choices=["api", "agy"], default="agy")
    ap.add_argument("--model", default="gemini-3.6-flash-medium")
    ap.add_argument("--out", default=str(Path(__file__).parent / "data" / "distill.jsonl"))
    ap.add_argument("--append", action="store_true")
    args = ap.parse_args()

    gen = gen_batch_agy if args.backend == "agy" else gen_batch_api
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    seen, kept, calls, rejected = set(), 0, 0, 0
    reasons = Counter()
    if args.append and out.exists():
        for l in out.read_text().splitlines():
            if l.strip():
                seen.add(json.loads(l)["text"].split("### Input:\n")[1][:60].lower())
        kept = len(seen)
    n_calls = (args.n // args.per_call) * 3  # headroom for rejects/dupes

    mode = "a" if args.append else "w"
    with open(out, mode) as f, ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = {ex.submit(gen, i, args.per_call, args.model): i for i in range(n_calls)}
        for fut in as_completed(futures):
            calls += 1
            try:
                batch = fut.result()
            except Exception as e:
                reasons["api-error"] += 1
                continue
            for s in batch:
                raw = s.get("raw", "")
                key = raw[:60].lower()
                if key in seen:
                    reasons["dup"] += 1
                    continue
                ok, why = accept(s)
                if ok:
                    seen.add(key)
                    f.write(json.dumps({"text": f"### Input:\n{raw}\n\n### Output:\n{s['gold']}",
                                        "tags": s.get("tags", [])}) + "\n")
                    f.flush()
                    kept += 1
                else:
                    rejected += 1
                    reasons[why] += 1
            if calls % 10 == 0:
                print(f"calls={calls} kept={kept} rejected={rejected} "
                      f"({kept/max(1,kept+rejected):.0%} accept) {dict(reasons)}", flush=True)
            if kept >= args.n:
                break

    print(f"\nDONE: {kept} accepted, {rejected} rejected across {calls} calls -> {out}")
    print("reject reasons:", dict(reasons))


if __name__ == "__main__":
    main()

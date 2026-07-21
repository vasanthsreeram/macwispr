#!/usr/bin/env python3
"""Generate synthetic hard-tag training data for the polish model via `grok -p`.

Diversity comes from randomized topic/persona/quirk seeds injected per batch
(one grok call yields many examples). Every gold is validated with the shared
polish_verifier; raws are deduped (normalized) against existing pools + itself.

Usage:
  python gen_synth_data.py --n 300 --out data/synth_hard.jsonl [--batch 10]
"""
import argparse
import json
import random
import re
import subprocess
import sys
from pathlib import Path

from polish_verifier import verify

HERE = Path(__file__).parent

TAG_MIX = [
    ("multi_list", 0.35),
    ("format_numbered", 0.25),
    ("mixed_styles", 0.25),
    ("format_checklist", 0.15),
]

TOPICS = [
    "grocery shopping", "camping trip", "moving apartments", "onboarding a new engineer",
    "planning a birthday party", "server migration", "wedding planning", "meal prep for the week",
    "packing for a conference", "garden spring cleanup", "podcast episode prep", "home renovation",
    "puppy adoption checklist", "quarterly review prep", "road trip through Europe", "garage sale",
    "science fair project", "restaurant opening", "band rehearsal logistics", "tax season documents",
    "kids school morning routine", "photo studio setup", "open source release", "bike repair",
    "emergency preparedness kit", "coffee shop inventory", "physical therapy exercises",
    "app store submission", "community fundraiser", "boat maintenance",
]
PERSONAS = [
    "a busy parent", "a software engineer", "a project manager", "a college student",
    "a small business owner", "a nurse", "a teacher", "a freelance designer", "a chef",
    "a researcher",
]
QUIRKS = [
    "includes 'um' and 'uh' fillers",
    "has a self-correction like 'no wait, actually...'",
    "repeats a word by accident",
    "trails off then resumes with 'okay so'",
    "spells out a number in words that should become a digit",
    "mentions the format request at the END of the dictation",
    "mentions the format request in the MIDDLE of the dictation",
    "uses casual speech like 'gonna' or 'kinda'",
]

TAG_SPECS = {
    "multi_list": (
        "TWO separate lists in one dictation (e.g. groceries AND hardware store; "
        "work tasks AND personal errands). The gold output must have two headed/labelled "
        "sections, each with its own list items — never merged into one list."
    ),
    "format_numbered": (
        "sequential steps where the speaker asks for a numbered list "
        "('numbered', 'as steps', 'number one... number two'). Gold uses 1. 2. 3. lines."
    ),
    "mixed_styles": (
        "a dictation needing TWO different structures at once, e.g. a short prose "
        "paragraph followed by a bulleted list, or a numbered list plus a checklist. "
        "Gold reflects both structures."
    ),
    "format_checklist": (
        "a to-do style dictation where the speaker says 'checklist' or 'checkboxes'. "
        "Gold uses '- [ ] item' lines (markdown checkboxes)."
    ),
}

SCHEMA = json.dumps({
    "type": "object",
    "properties": {
        "examples": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "raw": {"type": "string"},
                    "gold": {"type": "string"},
                },
                "required": ["raw", "gold"],
            },
        }
    },
    "required": ["examples"],
})


def batch_prompt(tag: str, k: int, rng: random.Random) -> str:
    topics = rng.sample(TOPICS, k)
    seeds = "\n".join(
        f"{i+1}. topic: {t}; speaker: {rng.choice(PERSONAS)}; quirk: {rng.choice(QUIRKS)}"
        for i, t in enumerate(topics)
    )
    return f"""Generate {k} synthetic training examples for a dictation-cleanup model.

Each example has:
- "raw": a realistic RAW speech-to-text transcript — lowercase-ish, no punctuation or sparse punctuation, disfluencies, exactly as ASR would emit it. The speaker verbally requests a format.
- "gold": the perfectly cleaned + formatted version. Fix fillers/corrections, apply the requested structure, keep ALL content items (never drop one), never add content or answer questions.

Category for ALL {k} examples — {tag}: {TAG_SPECS[tag]}

Use these seeds, one per example, so every example differs in topic, voice, length and phrasing:
{seeds}

Vary list lengths (3-7 items), how the format is requested, and sentence rhythm. No two raws may share phrasing patterns. Return JSON only."""


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).strip()


def load_existing_norms() -> set:
    seen = set()
    for f in [HERE / "dpo_prompts.jsonl", HERE / "ood_eval_set.jsonl"]:
        if f.exists():
            for line in f.read_text().splitlines():
                if line.strip():
                    seen.add(norm(json.loads(line).get("raw", "")))
    return seen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--batch", type=int, default=10)
    ap.add_argument("--out", default="data/synth_hard.jsonl")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--model", default=None, help="optional grok model id")
    ap.add_argument("--max-batches", type=int, default=80)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    out_path = HERE / args.out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    seen = load_existing_norms()
    kept = []
    if out_path.exists():
        for line in out_path.read_text().splitlines():
            if line.strip():
                r = json.loads(line)
                kept.append(r)
                seen.add(norm(r["raw"]))

    stats = {"gen": 0, "dup": 0, "bad_gold": 0, "kept": len(kept)}
    batches = 0
    while len(kept) < args.n and batches < args.max_batches:
        batches += 1
        # weighted tag choice
        r, acc = rng.random(), 0.0
        tag = TAG_MIX[-1][0]
        for t, w in TAG_MIX:
            acc += w
            if r <= acc:
                tag = t
                break
        cmd = ["grok", "-p", batch_prompt(tag, args.batch, rng), "--json-schema", SCHEMA]
        if args.model:
            cmd += ["-m", args.model]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            payload = json.loads(proc.stdout.strip())
            examples = payload.get("examples") or payload.get("result", {}).get("examples", [])
        except Exception as e:
            print(f"batch {batches} ({tag}) failed: {e}", file=sys.stderr)
            continue

        with out_path.open("a") as f:
            for ex in examples:
                raw, gold = (ex.get("raw") or "").strip(), (ex.get("gold") or "").strip()
                if not raw or not gold:
                    continue
                stats["gen"] += 1
                key = norm(raw)
                if not key or key in seen:
                    stats["dup"] += 1
                    continue
                v = verify(raw, gold, [tag])
                if not v.passed:
                    stats["bad_gold"] += 1
                    continue
                seen.add(key)
                row = {"raw": raw, "gold": gold, "tags": [tag], "source": "grok_synth"}
                f.write(json.dumps(row) + "\n")
                kept.append(row)
        stats["kept"] = len(kept)
        print(f"batch {batches} ({tag}): kept={stats['kept']}/{args.n} "
              f"gen={stats['gen']} dup={stats['dup']} bad_gold={stats['bad_gold']}", flush=True)

    by_tag = {}
    for r in kept:
        by_tag[r["tags"][0]] = by_tag.get(r["tags"][0], 0) + 1
    print("DONE", json.dumps({**stats, "by_tag": by_tag}))


if __name__ == "__main__":
    main()

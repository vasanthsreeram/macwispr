#!/usr/bin/env python3
"""Generate OOD eval suite v2 — bigger, balanced, more variants than the 40-case v1.

Design:
- ~15 cases per tag across all 9 tags (~135 total) + v1's 40 kept for continuity
- generated with a STRONGER model (default agy/gemini-3.1-pro-low) than the
  training data (flash) to reduce same-generator bias
- topic pool disjoint from the training generator's TOPICS
- hard-variant coverage: spoken ordinals, items-buried-in-prose, garbled tails,
  course corrections mid-list, format cue at start/middle/end
- strict dedup against ALL training pools (sft/synth/aug/dpo) and v1 suite
- every gold verifier-validated for its tag

Usage: python gen_eval_v2.py [--per-tag 15] [--model gemini-3.1-pro-low]
"""
import argparse
import json
import random
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from polish_verifier import verify

HERE = Path(__file__).parent

# Disjoint from training TOPICS on purpose.
EVAL_TOPICS = [
    "aquarium maintenance", "beekeeping season prep", "vinyl record cleaning",
    "marathon training week", "pottery kiln firing", "food truck permit run",
    "houseplant repotting", "ski trip logistics", "escape room design",
    "farmers market stall", "home lab networking", "book club hosting",
    "car camping conversion", "sourdough baking schedule", "climbing gym day",
    "drone photography shoot", "thrift store flipping", "neighborhood watch meeting",
    "college application season", "amateur radio field day", "koi pond winterizing",
    "tabletop campaign prep", "volunteer shift planning", "backyard observatory",
]
PERSONAS = [
    "a retiree", "a grad student", "a shift nurse", "a startup founder",
    "a middle school teacher", "an electrician", "a barista", "a pilot",
]
VARIANTS = [
    "the speaker uses spoken ordinals woven into speech (one of it was X, number two Y) with some ordinals skipped",
    "the items are buried mid-sentence in prose (it has A, B, C and also D) while the speaker asks to list them out",
    "the tail of the dictation is garbled/repetitive ASR output that should be kept minimal, not embellished",
    "a self-correction happens mid-list (no wait, scratch that, make it X)",
    "the format request comes at the very START",
    "the format request comes in the MIDDLE",
    "the format request comes at the very END",
    "heavy fillers (um, uh, you know) throughout",
]

TAG_SPECS = {
    "multi_list": "TWO separate lists in one dictation; gold has two headed sections, never merged.",
    "mixed_styles": "needs a numbered list AND a bulleted or '- [ ]' checkbox list in one output.",
    "format_numbered": "numbered list requested (explicitly or via spoken ordinals); gold uses 1. 2. 3., never '-'.",
    "format_bullets": "bulleted list requested; gold uses '-' lines, never numbers/checkboxes.",
    "format_checklist": "checklist/checkboxes requested; gold uses '- [ ]' lines.",
    "preserve_prose": "flowing prose dictation with NO list request; gold is cleaned prose, no lists introduced.",
    "preserve_question": "the dictation IS a question (or contains one); gold keeps it a question and NEVER answers it.",
    "email": "a dictated email; gold is a short formatted email (greeting, body, sign-off as dictated).",
    "light": "already fairly clean speech needing only light filler/punctuation cleanup; gold changes very little.",
}


def batch_prompt(tag: str, k: int, rng: random.Random) -> str:
    topics = rng.sample(EVAL_TOPICS, k)
    seeds = "\n".join(
        f"{i+1}. topic: {t}; speaker: {rng.choice(PERSONAS)}; variant: {rng.choice(VARIANTS)}"
        for i, t in enumerate(topics)
    )
    return f"""Generate {k} EVALUATION examples for a dictation-cleanup model. These are held-out test cases, so make them challenging and diverse — not textbook-clean.

Each example: "raw" = realistic raw speech-to-text (disfluencies, weak punctuation, exactly as ASR emits), "gold" = the ideal cleaned+formatted output (keep ALL content items, never add content, never answer questions).

Category for ALL {k} examples — {tag}: {TAG_SPECS[tag]}

Seeds (one per example — follow the variant instruction closely):
{seeds}

Vary lengths and rhythm; no two raws may share phrasing patterns.
Return ONLY a JSON object {{"examples": [{{"raw": ..., "gold": ...}}, ...]}} — no markdown fences, no commentary."""


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).strip()


def load_seen() -> set:
    seen = set()
    for name in ["dpo_prompts.jsonl", "ood_eval_set.jsonl",
                 "data/synth_hard.jsonl", "data/synth_aug.jsonl"]:
        f = HERE / name
        if f.exists():
            for line in f.read_text().splitlines():
                if line.strip():
                    seen.add(norm(json.loads(line).get("raw", "")))
    sft = HERE / "sft_train_pool.jsonl"
    if sft.exists():
        for line in sft.read_text().splitlines():
            if line.strip():
                t = json.loads(line).get("text", "")
                m = re.search(r"### Input:\n(.*?)\n\n### Output:", t, re.S)
                if m:
                    seen.add(norm(m.group(1)))
    return seen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-tag", type=int, default=15)
    ap.add_argument("--model", default="gemini-3.1-pro-low")
    ap.add_argument("--workers", type=int, default=5)
    ap.add_argument("--out", default="ood_eval_set_v2.jsonl")
    ap.add_argument("--seed", type=int, default=31)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    seen = load_seen()
    kept = {t: [] for t in TAG_SPECS}

    def run(tag, batch_idx):
        prompt = batch_prompt(tag, 8, rng)
        proc = subprocess.run(["agy", "-p", prompt, "--model", args.model],
                              capture_output=True, text=True, timeout=420)
        out = proc.stdout.strip()
        payload = json.loads(out[out.index("{"):out.rindex("}") + 1])
        return tag, payload.get("examples", [])

    jobs = [(t, i) for t in TAG_SPECS for i in range(3)]  # 3 batches x 8 per tag
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futs = [pool.submit(run, t, i) for t, i in jobs]
        for fut in as_completed(futs):
            try:
                tag, examples = fut.result()
            except Exception as e:
                print(f"batch failed: {e}", file=sys.stderr)
                continue
            for ex in examples:
                if len(kept[tag]) >= args.per_tag:
                    break
                raw = (ex.get("raw") or "").strip()
                gold = (ex.get("gold") or "").strip()
                key = norm(raw)
                if not raw or not gold or not key or key in seen:
                    continue
                if not verify(raw, gold, [tag]).passed:
                    continue
                seen.add(key)
                kept[tag].append({"raw": raw, "gold": gold})
            done = sum(len(v) for v in kept.values())
            print(f"{tag}: {len(kept[tag])}/{args.per_tag} (total {done})", flush=True)

    # v1 cases carried over for continuity
    v1 = [json.loads(l) for l in (HERE / "ood_eval_set.jsonl").read_text().splitlines() if l.strip()]
    rows = []
    for i, c in enumerate(v1):
        rows.append({"id": c.get("id") or f"v1_{i}", "raw": c["raw"], "tags": c["tags"], "origin": "v1"})
    n = 0
    for tag, cases in kept.items():
        for c in cases:
            n += 1
            rows.append({"id": f"v2_{tag}_{n}", "raw": c["raw"], "gold": c["gold"],
                         "tags": [tag], "origin": "v2"})
    (HERE / args.out).write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    print("EVAL_V2 DONE", json.dumps({t: len(v) for t, v in kept.items()}),
          f"total={len(rows)} (incl. {len(v1)} v1)")


if __name__ == "__main__":
    main()

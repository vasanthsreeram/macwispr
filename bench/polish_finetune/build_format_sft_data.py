#!/usr/bin/env python3
"""Build a formatting-focused SFT mix on top of the existing polish skill.

Continues from the course-correction checkpoint: teach multiline bullets,
numbered lists, checklists, and spoken "as a list" cues — while retaining
some plain cleanup so we don't forget light polish / course-correction.

Sources:
  1. Sotto public cleanup set (list-like rows + small cleanup retention)
  2. Synthetic spoken → structured format pairs (bullets / numbered / checklist)
  3. Existing local sotto_ft rows (course / light) for skill retention

Output layout (mlx_lm.lora ready):
  polish_finetune/data/format_sft/{train,valid,test}.jsonl
  each line: {"text": "### Input:\\n...\\n\\n### Output:\\n..."}
"""
from __future__ import annotations

import argparse
import json
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT_DEFAULT = ROOT / "data" / "format_sft"
LOCAL_SOTTO = ROOT / "data" / "sotto_ft"


def pair_text(raw: str, clean: str) -> str:
    return f"### Input:\n{raw.strip()}\n\n### Output:\n{clean.strip()}"


def is_listlike(out: str) -> bool:
    o = out.strip()
    if re.search(r"(?m)^\s*[-*•]\s+\S", o):
        return True
    if re.search(r"(?m)^\s*\d+[\.\)]\s+\S", o):
        return True
    if "1." in o and "2." in o:
        return True
    return False


def to_multiline_numbered(out: str) -> str:
    """Normalize inline '1. a 2. b' into multiline numbered list when possible."""
    o = out.strip()
    if "\n" in o and re.search(r"(?m)^\s*\d+[\.\)]\s+", o):
        return o
    # "Goals …: 1. A 2. B 3. C"
    m = re.match(r"^(.*?:)\s*(1\.\s*.+)$", o)
    prefix = ""
    body = o
    if m:
        prefix = m.group(1).strip() + "\n"
        body = m.group(2).strip()
    parts = re.split(r"\s*(?=\d+\.\s+)", body)
    parts = [p.strip() for p in parts if re.match(r"^\d+\.\s+\S", p.strip())]
    if len(parts) >= 2:
        return prefix + "\n".join(parts)
    return o


def to_bullets_from_numbered(out: str) -> str:
    lines = []
    for line in to_multiline_numbered(out).splitlines():
        m = re.match(r"^\s*\d+[\.\)]\s+(.+)$", line.strip())
        if m:
            lines.append(f"- {m.group(1).strip()}")
        elif line.strip() and not lines:
            # keep a one-line intro if present
            if line.strip().endswith(":"):
                lines.append(line.strip())
            else:
                lines.append(f"- {line.strip()}")
        elif line.strip().endswith(":") and not any(
            x.startswith("-") for x in lines
        ):
            lines.append(line.strip())
    return "\n".join(lines) if lines else out


# ---------------------------------------------------------------------------
# Synthetic format pairs (spoken dictation → structured layout)
# ---------------------------------------------------------------------------

SHOPPING = [
    (["milk", "eggs", "bread", "butter"], "shopping"),
    (["oat milk", "bananas", "spinach", "greek yogurt"], "groceries"),
    (["paper towels", "dish soap", "trash bags"], "household"),
    (["chicken thighs", "rice", "broccoli", "garlic"], "dinner ingredients"),
    (["toothpaste", "shampoo", "deodorant"], "toiletries"),
    (["black beans", "tortillas", "salsa", "avocado", "lime"], "taco night"),
    (["coffee beans", "filters", "half and half"], "coffee run"),
    (["dog food", "treats", "poop bags"], "pet supplies"),
]

SPRINT = [
    (["ship polish", "fix hotkey on macOS fourteen", "update the docs"], "sprint"),
    (["merge the release branch", "bump the appcast", "notarize the build"], "release"),
    (["write the holdout eval", "train the format adapter", "install the test build"], "ML work"),
    (["review PRs", "fix the paste path", "file the accessibility bug"], "engineering"),
    (["outline the blog post", "record the demo", "schedule the launch tweet"], "marketing"),
]

MEETING = [
    (["decide on the model size", "assign owners for format data", "set a ship date for one point three"], "meeting"),
    (["block thirty minutes for design review", "send notes to the team", "follow up with legal"], "actions"),
    (["confirm the budget", "pick a vendor", "schedule the kickoff"], "next steps"),
]

HOWTO = [
    (["preheat the oven to three fifty", "mix the dry ingredients", "bake for twenty minutes"], "recipe"),
    (["open settings", "click transcription", "pick the local model"], "how to"),
    (["clone the repo", "run install script", "grant mic and accessibility"], "setup"),
    (["hold option space", "speak naturally", "release to insert"], "dictation"),
]

FILLERS = [
    "um ",
    "uh ",
    "okay so ",
    "alright ",
    "like ",
    "basically ",
    "yeah so ",
    "",
]

LIST_CUES = {
    "bullets": [
        "as bullets",
        "as a bullet list",
        "in bullet points",
        "make that a bullet list",
        "format as bullets",
        "as a list",
        "point form",
    ],
    "numbered": [
        "as a numbered list",
        "numbered",
        "number these",
        "as steps",
        "step by step",
        "one two three",
    ],
    "checklist": [
        "as a checklist",
        "as checkboxes",
        "todo list",
        "as todos",
    ],
}


def spoken_join(items: list[str], rng: random.Random) -> str:
    if len(items) == 1:
        return items[0]
    if len(items) == 2:
        return f"{items[0]} and {items[1]}"
    conj = rng.choice([" and ", ", and ", " um and "])
    return ", ".join(items[:-1]) + conj + items[-1]


def make_spoken_list(
    items: list[str],
    kind: str,
    topic: str,
    rng: random.Random,
) -> tuple[str, str]:
    cue = rng.choice(LIST_CUES[kind])
    filler = rng.choice(FILLERS)
    body = spoken_join(items, rng)

    templates = [
        f"{filler}{topic} {body} {cue}",
        f"{filler}for {topic} i need {body} {cue}",
        f"{filler}{cue} {topic}: {body}",
        f"{filler}write down {body} {cue}",
        f"{filler}remind me {body} {cue}",
    ]
    if kind == "numbered":
        templates.append(
            f"{filler}first {items[0]} then {spoken_join(items[1:], rng) if len(items)>1 else ''} {cue}".strip()
        )
        # classic sotto-style ordinal speech
        ordinals = ["one", "two", "three", "four", "five", "six"]
        bits = [f"{ordinals[i]} {it}" for i, it in enumerate(items) if i < len(ordinals)]
        templates.append(f"{filler}{topic} {' '.join(bits)}")

    raw = rng.choice(templates)
    raw = re.sub(r"\s+", " ", raw).strip()

    # light ASR noise
    if rng.random() < 0.25:
        raw = raw.replace(" and ", " and uh ")
    if rng.random() < 0.15:
        raw = raw[0].lower() + raw[1:] if raw else raw

    titled = [it[0].upper() + it[1:] if it else it for it in items]
    if kind == "bullets":
        clean = "\n".join(f"- {t}" for t in titled)
    elif kind == "numbered":
        clean = "\n".join(f"{i+1}. {t}" for i, t in enumerate(titled))
    else:
        clean = "\n".join(f"- [ ] {t}" for t in titled)

    # optional short intro line for variety
    if rng.random() < 0.2 and topic:
        intro = topic[0].upper() + topic[1:] + ":"
        clean = intro + "\n" + clean

    return raw, clean


def build_synthetic(n: int, rng: random.Random) -> list[dict]:
    pools = [
        (SHOPPING, "bullets", 0.45),
        (SPRINT, "bullets", 0.2),
        (MEETING, "numbered", 0.15),
        (HOWTO, "numbered", 0.12),
        (SPRINT, "checklist", 0.08),
    ]
    rows: list[dict] = []
    while len(rows) < n:
        for pool, default_kind, weight in pools:
            if len(rows) >= n:
                break
            if rng.random() > weight * 2 and len(rows) > 10:
                continue
            items, topic = rng.choice(pool)
            # maybe drop/add item noise
            its = list(items)
            if len(its) > 3 and rng.random() < 0.2:
                its = its[:-1]
            kind = default_kind
            if rng.random() < 0.15:
                kind = rng.choice(["bullets", "numbered", "checklist"])
            raw, clean = make_spoken_list(its, kind, topic, rng)
            rows.append(
                {
                    "text": pair_text(raw, clean),
                    "tag": f"format_{kind}",
                    "source": "synthetic",
                }
            )
    return rows[:n]


def load_local_sotto_retention(max_n: int, rng: random.Random) -> list[dict]:
    path = LOCAL_SOTTO / "train.jsonl"
    if not path.exists():
        return []
    rows = []
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        text = o.get("text") or ""
        if "### Input:" not in text or "### Output:" not in text:
            continue
        rows.append({"text": text, "tag": "retain", "source": "local_sotto_ft"})
    rng.shuffle(rows)
    return rows[:max_n]


def load_sotto_public(
    max_list: int,
    max_retain: int,
    rng: random.Random,
) -> tuple[list[dict], list[dict]]:
    try:
        from datasets import load_dataset
    except ImportError as e:
        print(f"datasets not available: {e}")
        return [], []

    print("Streaming juanquivilla/sotto-transcript-cleanup …")
    ds = load_dataset(
        "juanquivilla/sotto-transcript-cleanup", split="train", streaming=True
    )
    lists: list[dict] = []
    retain: list[dict] = []
    scanned = 0
    for row in ds:
        scanned += 1
        raw = (row.get("input") or "").strip()
        out = (row.get("output") or "").strip()
        if not raw or not out or len(raw) < 8:
            continue
        if is_listlike(out):
            if len(lists) < max_list:
                multi = to_multiline_numbered(out)
                lists.append(
                    {
                        "text": pair_text(raw, multi),
                        "tag": "format_numbered",
                        "source": "sotto_public",
                    }
                )
                # half the time also emit a bullet variant of same content
                if rng.random() < 0.45 and len(lists) < max_list:
                    bullets = to_bullets_from_numbered(multi)
                    if bullets != multi:
                        # slightly rephrase cue
                        cue_raw = raw
                        if "bullet" not in cue_raw.lower():
                            cue_raw = raw.rstrip(". ") + " as bullets"
                        lists.append(
                            {
                                "text": pair_text(cue_raw, bullets),
                                "tag": "format_bullets",
                                "source": "sotto_public_bulletized",
                            }
                        )
        elif len(retain) < max_retain and rng.random() < 0.08:
            # light cleanup retention (not lists)
            retain.append(
                {
                    "text": pair_text(raw, out),
                    "tag": "retain_cleanup",
                    "source": "sotto_public",
                }
            )
        if scanned % 20000 == 0:
            print(f"  scanned={scanned} lists={len(lists)} retain={len(retain)}")
        if len(lists) >= max_list and len(retain) >= max_retain:
            break
        if scanned >= 120_000:
            break
    print(f"Sotto public: scanned={scanned} lists={len(lists)} retain={len(retain)}")
    return lists, retain


def try_wikihow(max_n: int, rng: random.Random) -> list[dict]:
    """Optional: WikiHow steps → spoken dictation format pairs."""
    try:
        from datasets import load_dataset
    except ImportError:
        return []

    candidates = [
        ("pseul/wikihow", None),
        ("wikihow", None),
    ]
    for name, config in candidates:
        try:
            print(f"Trying WikiHow source {name} …")
            ds = load_dataset(name, config, split="train", streaming=True)
            rows = []
            for row in ds:
                # flexible field names
                text = (
                    row.get("text")
                    or row.get("headline")
                    or row.get("title")
                    or ""
                )
                steps = row.get("steps") or row.get("method") or row.get("text")
                if isinstance(steps, list) and len(steps) >= 2:
                    items = [re.sub(r"\s+", " ", str(s)).strip() for s in steps[:6]]
                    items = [s for s in items if 3 < len(s) < 120]
                    if len(items) < 2:
                        continue
                    raw, clean = make_spoken_list(
                        [s[0].lower() + s[1:] if s else s for s in items],
                        rng.choice(["numbered", "bullets"]),
                        "steps",
                        rng,
                    )
                    rows.append(
                        {
                            "text": pair_text(raw, clean),
                            "tag": "format_wikihow",
                            "source": name,
                        }
                    )
                if len(rows) >= max_n:
                    break
            if rows:
                print(f"WikiHow-like rows: {len(rows)} from {name}")
                return rows
        except Exception as e:
            print(f"  skip {name}: {e}")
    print("WikiHow: no usable rows (optional)")
    return []


def split_write(rows: list[dict], out_dir: Path, seed: int) -> dict:
    rng = random.Random(seed)
    rng.shuffle(rows)
    n = len(rows)
    n_test = max(40, int(n * 0.05))
    n_val = max(60, int(n * 0.08))
    test = rows[:n_test]
    valid = rows[n_test : n_test + n_val]
    train = rows[n_test + n_val :]

    out_dir.mkdir(parents=True, exist_ok=True)
    meta = {
        "n_total": n,
        "n_train": len(train),
        "n_valid": len(valid),
        "n_test": len(test),
        "by_tag": {},
        "by_source": {},
    }
    for r in rows:
        meta["by_tag"][r["tag"]] = meta["by_tag"].get(r["tag"], 0) + 1
        meta["by_source"][r["source"]] = meta["by_source"].get(r["source"], 0) + 1

    for name, part in ("train", train), ("valid", valid), ("test", test):
        path = out_dir / f"{name}.jsonl"
        with path.open("w") as f:
            for r in part:
                # mlx_lm expects {"text": ...}
                f.write(json.dumps({"text": r["text"]}, ensure_ascii=False) + "\n")
        print(f"Wrote {path} ({len(part)} rows)")

    (out_dir / "meta.json").write_text(json.dumps(meta, indent=2))
    print(json.dumps(meta, indent=2))
    return meta


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=OUT_DEFAULT)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--synth", type=int, default=1200)
    ap.add_argument("--sotto-lists", type=int, default=2500)
    ap.add_argument("--sotto-retain", type=int, default=800)
    ap.add_argument("--local-retain", type=int, default=400)
    ap.add_argument("--wikihow", type=int, default=400)
    ap.add_argument("--skip-public", action="store_true")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    all_rows: list[dict] = []

    all_rows.extend(build_synthetic(args.synth, rng))
    print(f"Synthetic: {args.synth}")

    all_rows.extend(load_local_sotto_retention(args.local_retain, rng))

    if not args.skip_public:
        lists, retain = load_sotto_public(args.sotto_lists, args.sotto_retain, rng)
        all_rows.extend(lists)
        all_rows.extend(retain)
        if args.wikihow > 0:
            all_rows.extend(try_wikihow(args.wikihow, rng))

    # de-dupe by text
    seen = set()
    unique = []
    for r in all_rows:
        t = r["text"]
        if t in seen:
            continue
        seen.add(t)
        unique.append(r)

    print(f"Total unique rows: {len(unique)}")
    split_write(unique, args.out, args.seed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

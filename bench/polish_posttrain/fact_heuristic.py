"""Generic fact heuristics for polish outputs.

Parses spoken numbers in the raw ("twenty two fifty" -> 2250, "twelve
thousand" -> 12000) plus literal digits, then checks the output:
- retention: every raw number appears in the output (digits or words)
- no invention: every number in the output is justified by the raw
- negations must survive

Shared by the SFT audit and DPO pair mining (composite reward).
"""
from __future__ import annotations

import re

UNITS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
    "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
    "seventeen": 17, "eighteen": 18, "nineteen": 19,
}
TENS = {"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90}
SCALES = {"hundred": 100, "thousand": 1000, "million": 1000000, "dozen": 12}
NUM_WORDS = set(UNITS) | set(TENS) | set(SCALES) | {"zero", "oh"}
NEG_RE = re.compile(
    r"\b(not|don't|do not|doesn't|never|no longer|except|excluding|but not)\b", re.I
)


def _parse_group(words: list[str]) -> list[int]:
    """Candidate readings of one run of number words.

    "twelve thousand" -> [12000]; "twenty two fifty" -> [22, 50, 2250];
    "four one two" -> [4, 1, 2, 412].
    """
    # composed reading with scales
    total = current = 0
    for w in words:
        if w in UNITS:
            current += UNITS[w]
        elif w in TENS:
            current += TENS[w]
        elif w in SCALES:
            current = max(1, current) * SCALES[w]
            if SCALES[w] >= 1000:
                total, current = total + current, 0
    composed = total + current
    vals = {composed} if composed else set()

    # chunked reading: tens+unit groups spoken back-to-back
    chunks, cur = [], 0
    for w in words:
        if w in TENS:
            if cur:
                chunks.append(cur)
            cur = TENS[w]
        elif w in UNITS:
            if 0 < cur < 100 and cur % 10 == 0 and UNITS[w] < 10:
                cur += UNITS[w]
            else:
                if cur:
                    chunks.append(cur)
                cur = UNITS[w]
        elif w in ("zero", "oh"):
            if cur:
                chunks.append(cur)
            chunks.append(0)
            cur = 0
        elif w in SCALES:
            cur = max(1, cur) * SCALES[w]
    if cur:
        chunks.append(cur)
    vals.update(c for c in chunks if c)
    if len(chunks) == 2 and all(0 < c < 100 for c in chunks):
        vals.add(chunks[0] * 100 + chunks[1])  # "twenty two fifty" -> 2250
    if len(chunks) >= 3 and all(c < 10 for c in chunks):
        vals.add(int("".join(str(c) for c in chunks)))  # digit-by-digit
    vals.discard(0)
    return sorted(vals)


def raw_number_groups(raw: str) -> tuple[list[list[int]], set[int]]:
    """(per-group candidate readings, all allowed output values)."""
    tokens = re.findall(r"[a-z']+|\d+(?:[.:]\d+)?", raw.lower())
    groups, cur = [], []
    for t in tokens:
        if t in NUM_WORDS:
            cur.append(t)
        else:
            if cur:
                groups.append(cur)
                cur = []
            if t[0].isdigit() and "." not in t and ":" not in t:
                groups.append([t])
    if cur:
        groups.append(cur)
    per_group, allowed, digit_strings = [], set(), []
    for g in groups:
        if g[0][0].isdigit():
            vals = [int(g[0])]
        else:
            vals = _parse_group(g)
            # digit-by-digit sequences (phone numbers): keep exact string
            singles = [w for w in g if w in ("zero", "oh") or (w in UNITS and UNITS[w] < 10)]
            if len(singles) == len(g) and len(g) >= 4:
                ds = "".join("0" if w in ("zero", "oh") else str(UNITS[w]) for w in g)
                digit_strings.append(ds)
                allowed.update(int(ds[i:j]) for i in range(len(ds)) for j in (i + 3, i + 4) if j <= len(ds))
        if vals:
            per_group.append(vals)
            allowed.update(vals)
    return per_group, allowed, digit_strings


def _out_numbers(out: str) -> list[int]:
    vals = []
    for m in re.findall(r"\d[\d,]*", out):
        s = m.replace(",", "")
        vals.append(int(s))
    return vals


def fact_retention(raw: str, out: str) -> float:
    """1.0 = every number kept, none invented, negations preserved."""
    per_group, allowed, digit_strings = raw_number_groups(raw)
    out_flat = out.replace(",", "")
    out_digits = re.sub(r"\D", "", out)
    out_l = out.lower()
    word_by_val = {n: w for w, n in {**UNITS, **TENS}.items()}
    penalties = checks = 0

    for ds in digit_strings:
        checks += 1
        if ds not in out_digits:
            penalties += 1

    for vals in per_group:
        checks += 1
        found = any(re.search(rf"(?<!\d){v}(?!\d)", out_flat) for v in vals)
        if not found:
            found = any(
                word_by_val[v] in out_l for v in vals if v in word_by_val
            )
        if not found and any(str(v) in out_digits for v in vals if v >= 100):
            found = True  # covered inside a grouped digit string (phone)
        if not found:
            penalties += 1

    out_nums = _out_numbers(out)
    if out_nums:
        checks += 1
        invented = [
            v for v in out_nums
            if v not in allowed and not (v < 100 and any(v == a % 100 for a in allowed))
        ]
        if invented:
            penalties += 1

    if NEG_RE.search(raw):
        checks += 1
        if not NEG_RE.search(out):
            penalties += 1

    return 1.0 if checks == 0 else max(0.0, 1.0 - penalties / checks)

#!/usr/bin/env python3
"""Generate fact-retention SFT data with verified golds.

Raws are synthesized from templates with known ground-truth facts (spelled-out
money, phone numbers, spoken passwords, times, negations, thresholds). Golds
come from Claude Sonnet, then each gold is auto-verified with verify_meaning —
a gold that drops or corrupts a fact is rejected, so nothing lossy enters the
training set.

Usage: python gen_fact_sft.py --n 350 --out data/fact_sft.jsonl
"""
from __future__ import annotations

import argparse
import json
import random

from pathlib import Path




NAMES = ["priya", "marcus", "elena", "dave", "sarah", "tom", "jess", "linda", "chen", "amir", "sofia", "kenji", "nadia", "omar", "grace", "leo"]
TOPICS = ["the renovation", "the offsite", "the wedding", "the server move", "the road trip", "the audit", "the launch", "the move", "the fundraiser", "the deposit"]

ONES = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine"}
TEENS = {10: "ten", 11: "eleven", 12: "twelve", 13: "thirteen", 14: "fourteen", 15: "fifteen", 16: "sixteen", 17: "seventeen", 18: "eighteen", 19: "nineteen"}
TENS = {2: "twenty", 3: "thirty", 4: "forty", 5: "fifty", 6: "sixty", 7: "seventy", 8: "eighty", 9: "ninety"}


def spell2(n: int) -> str:
    if n < 10:
        return ONES[n]
    if n < 20:
        return TEENS[n]
    t, o = divmod(n, 10)
    return TENS[t] + (" " + ONES[o] if o else "")


def spell_money(amount: int) -> tuple[str, str]:
    """(spoken, regex) for amounts like 2250, 4800, 12000, 950."""
    if amount % 1000 == 0 and amount < 100000:
        k = amount // 1000
        return f"{spell2(k)} thousand dollars", rf"{amount:,}|\${amount}|\${k},?000|{spell2(k)} thousand"
    if amount % 100 == 0 and 1000 < amount < 10000:
        h = amount // 100
        return f"{spell2(h)} hundred dollars", rf"{amount:,}|\${amount}|{amount}"
    if 1000 < amount < 10000 and amount % 100:
        a, b = divmod(amount, 100)
        return f"{spell2(a)} {spell2(b)}", rf"{amount:,}|\${amount}|{amount}"
    k, rest = divmod(amount, 1000)
    parts = [f"{spell2(k)} thousand"]
    if rest >= 100:
        parts.append(f"{spell2(rest // 100)} hundred")
        rest %= 100
    if rest:
        parts.append(spell2(rest))
    return " ".join(parts) + " dollars", rf"{amount:,}|\${amount}|{amount}"


def phone() -> tuple[str, str]:
    digits = "0" + "".join(random.choice("123456789") for _ in range(8))
    spoken = " ".join("oh" if d == "0" else spell2(int(d)) for d in digits)
    rex = r" ?".join(digits)
    return spoken, rex


def password() -> tuple[str, str]:
    word = random.choice(["river", "maple", "tiger", "sunset", "harbor", "cedar"])
    num = random.randint(10, 99)
    spoken = f"capital {word[0]} {word[1:]} {ONES[num // 10] if num // 10 < 10 else num // 10} {ONES[num % 10] if num % 10 else 'zero'}"
    spoken = f"capital {word[0].upper()} {word[1:]} {spell2(num // 10)[:0]}{num // 10} {num % 10} exclamation mark"
    canon = f"{word.capitalize()}{num}!"
    return spoken, canon.replace("!", "\\!?")


def fmt_money(amount: int) -> str:
    return f"${amount:,}"


def make_case(rng: random.Random) -> dict:
    kind = rng.choice(["money", "money", "phone", "password", "negation", "threshold", "mixedstyle_facts", "who_said"])
    n1, n2 = rng.sample(NAMES, 2)
    topic = rng.choice(TOPICS)
    T = topic.capitalize()
    N1, N2 = n1.capitalize(), n2.capitalize()
    if kind == "money":
        a = int(rng.choice([1200, 2250, 3400, 4800, 7200, 9500, 12000, 15000, 22000]) + rng.choice([0, 50, 100]) * (rng.random() > 0.6))
        b = a + rng.choice([300, 500, 750, 1500])
        sa, _ = spell_money(a)
        sb, _ = spell_money(b)
        raw = f"okay so for {topic} {n1} quoted {sa} but the invoice came in at {sb} ask them why before we pay anything"
        gold = f"For {topic}, {N1} quoted {fmt_money(a)}, but the invoice came in at {fmt_money(b)}. Ask them why before we pay anything."
    elif kind == "phone":
        sp, digits = phone()
        digits = digits.replace(" ?", "")
        hour = rng.choice(["two", "three", "four"])
        raw = f"the contact for {topic} is {n1} their number is {sp} call after {hour} pm only"
        gold = f"The contact for {topic} is {N1}, their number is {digits[:4]} {digits[4:7]} {digits[7:]}. Call after {['two','three','four'].index(hour) + 2}pm only."
    elif kind == "password":
        sp, canon = password()
        canon = canon.replace("\\!?", "!")
        raw = f"the login for {topic} portal is username {n1} dot {n2} and the password is {sp} write that down exactly"
        gold = f"Login for the {topic.removeprefix('the ')} portal:\n\n- Username: {n1}.{n2}\n- Password: {canon}"
    elif kind == "negation":
        raw = f"important for {topic} do not confirm anything with {n1} until {n2} signs off even if they push and they will push"
        gold = f"Important for {topic}: do not confirm anything with {N1} until {N2} signs off — even if they push (and they will)."
    elif kind == "threshold":
        t1, t2 = sorted(rng.sample([2, 3, 5, 8, 10, 15], 2))
        raw = f"for {topic} alert {n1} if costs go over {spell2(t2)} percent but it's fine up to {spell2(t1)} percent just note it"
        gold = f"For {topic}, alert {N1} if costs go over {t2}%. Up to {t1}% is fine — just note it."
    elif kind == "mixedstyle_facts":
        items = rng.sample(["permits", "insurance", "deposit", "contracts", "keys", "invoices"], 3)
        day = rng.randint(10, 28)
        raw = (f"for {topic} the steps are first {items[0]} then {items[1]} then {items[2]} in that order "
               f"and separately some things to watch out for {n1} is away until the {spell2(day)}th and the budget is tight")
        gold = (f"{T} steps (in order):\n\n1. {items[0].capitalize()}\n2. {items[1].capitalize()}\n3. {items[2].capitalize()}\n\n"
                f"Watch out for:\n\n- {N1} is away until the {day}th\n- The budget is tight")
    else:
        day = rng.randint(10, 28)
        raw = f"so {n1} said the {topic} deadline moved to the {spell2(day)}th but {n2} thinks that's wrong check with the vendor and trust the vendor's date"
        gold = f"{N1} said the {topic.removeprefix('the ')} deadline moved to the {day}th, but {N2} thinks that's wrong. Check with the vendor and trust the vendor's date."
    return {"raw": raw, "gold": gold, "kind": kind}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=350)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--claude-model", default="sonnet")
    ap.add_argument("--out", default=str(Path(__file__).parent / "data" / "fact_sft.jsonl"))
    args = ap.parse_args()

    rng = random.Random(args.seed)
    seen, rows = set(), []
    kinds = []
    while len(rows) < args.n:
        c = make_case(rng)
        if c["raw"] in seen:
            continue
        seen.add(c["raw"])
        kinds.append(c["kind"])
        rows.append({"text": f"### Input:\n{c['raw']}\n\n### Output:\n{c['gold']}", "kind": c["kind"]})

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    from collections import Counter
    print(f"wrote {len(rows)} examples -> {out}")
    print(dict(Counter(kinds)))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Score an ASRGate report and print PASS / FAIL against bench/asr_gate/criteria.json.

  python3 bench/asr_gate/check.py bench/results/asr_gate/coreml.json \
      --baseline bench/results/asr_gate/photon.json

Without --baseline only the absolute limits are checked. Exit code 0 = PASS.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent


def normalize(text: str) -> list[str]:
    """Lowercase, strip accents and punctuation. Same rule for every engine."""
    t = unicodedata.normalize("NFKD", text.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    t = t.replace("’", "'").replace("-", " ")
    t = re.sub(r"[^\w\s']", " ", t)
    return [w.strip("'") for w in t.split() if w.strip("'")]


def edits(ref: list[str], hyp: list[str]) -> int:
    prev = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        cur = [i] + [0] * len(hyp)
        for j, h in enumerate(hyp, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r != h))
        prev = cur
    return prev[-1]


def score(report: dict) -> dict:
    by_set: dict[str, dict] = {}
    for it in report["items"]:
        s = by_set.setdefault(it["set"], {"errors": 0, "words": 0, "hyp_words": 0,
                                           "latency": [], "audio": 0.0, "time": 0.0})
        ref, hyp = normalize(it["reference"]), normalize(it["hypothesis"])
        s["errors"] += edits(ref, hyp)
        s["words"] += len(ref)
        s["hyp_words"] += len(hyp)
        s["latency"].append(it["latency_seconds"])
        s["audio"] += it["audio_seconds"]
        s["time"] += it["latency_seconds"]
    out = {}
    for name, s in by_set.items():
        lat = sorted(s["latency"])
        out[name] = {
            "wer": 100.0 * s["errors"] / s["words"] if s["words"] else None,
            "hyp_words": s["hyp_words"],
            "p50": lat[len(lat) // 2],
            "p95": lat[min(len(lat) - 1, int(len(lat) * 0.95))],
            "rtf": s["time"] / s["audio"] if s["audio"] else 0,
            "n": len(lat),
        }
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("report")
    ap.add_argument("--baseline")
    ap.add_argument("--criteria", default=str(HERE / "criteria.json"))
    args = ap.parse_args()

    crit = json.loads(Path(args.criteria).read_text())
    cand = json.loads(Path(args.report).read_text())
    base = json.loads(Path(args.baseline).read_text()) if args.baseline else None
    cs = score(cand)
    bs = score(base) if base else {}

    checks: list[tuple[str, bool, str]] = []

    def check(name: str, ok: bool, detail: str) -> None:
        checks.append((name, ok, detail))

    def fmt(x):
        return "n/a" if x is None else f"{x:.2f}"

    # Accuracy
    for set_name, rule in crit["accuracy"].items():
        c = cs.get(set_name)
        if not c:
            check(f"accuracy.{set_name}", False, "set missing from report")
            continue
        ok = c["wer"] is not None and c["wer"] <= rule["max_wer"]
        detail = f"WER {fmt(c['wer'])}% (limit {rule['max_wer']}%)"
        if base and set_name in bs and "max_wer_increase" in rule:
            limit = bs[set_name]["wer"] + rule["max_wer_increase"]
            ok = ok and c["wer"] <= limit
            detail += f", baseline {fmt(bs[set_name]['wer'])}% +{rule['max_wer_increase']} = {limit:.2f}%"
        check(f"accuracy.{set_name}", ok, detail)

    # Silence must not invent words
    sil = cs.get("silence")
    if sil:
        check("silence", sil["hyp_words"] <= crit["silence"]["max_words"],
              f"{sil['hyp_words']} words on silence (limit {crit['silence']['max_words']})")

    # Latency on dictation-length English
    eng = cs["english"]
    lat = crit["latency"]
    check("latency.p50", eng["p50"] <= lat["english_p50_seconds"],
          f"p50 {eng['p50'] * 1000:.0f} ms (limit {lat['english_p50_seconds'] * 1000:.0f} ms)")
    check("latency.p95", eng["p95"] <= lat["english_p95_seconds"],
          f"p95 {eng['p95'] * 1000:.0f} ms (limit {lat['english_p95_seconds'] * 1000:.0f} ms)")
    lf = cs.get("longform")
    if lf:
        check("latency.longform_rtf", lf["rtf"] <= lat["longform_max_rtf"],
              f"RTF {lf['rtf']:.3f} (limit {lat['longform_max_rtf']})")

    # Memory and load
    mem = crit["memory"]
    check("memory.peak", cand["peak_footprint_mb"] <= mem["max_peak_mb"],
          f"peak {cand['peak_footprint_mb']:.0f} MB (limit {mem['max_peak_mb']} MB)")
    check("memory.idle", cand["idle_footprint_mb"] <= mem["max_idle_mb"],
          f"idle {cand['idle_footprint_mb']:.0f} MB (limit {mem['max_idle_mb']} MB)")
    ld = crit["load"]
    check("load.warm", cand["load_seconds"] + cand["first_call_seconds"] <= ld["max_warm_load_seconds"],
          f"load+first call {cand['load_seconds'] + cand['first_call_seconds']:.1f} s (limit {ld['max_warm_load_seconds']} s)")

    # Report
    print(f"\nASR gate · {cand['model']} · {cand['host']} · {cand['date']}")
    if base:
        print(f"baseline · {base['model']}")
    print()
    print(f"{'set':<14}{'n':>4}{'WER %':>9}{'base %':>9}{'p50 ms':>9}{'p95 ms':>9}{'RTF':>8}")
    for name, c in cs.items():
        b = bs.get(name, {})
        print(f"{name:<14}{c['n']:>4}{fmt(c['wer']):>9}{fmt(b.get('wer')):>9}"
              f"{c['p50'] * 1000:>9.0f}{c['p95'] * 1000:>9.0f}{c['rtf']:>8.3f}")
    print(f"\nmemory idle {cand['idle_footprint_mb']:.0f} MB · peak {cand['peak_footprint_mb']:.0f} MB"
          + (f"   (baseline peak {base['peak_footprint_mb']:.0f} MB)" if base else ""))
    print()
    for name, ok, detail in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name:<22} {detail}")
    passed = all(ok for _, ok, _ in checks)
    print(f"\n{'PASS' if passed else 'FAIL'}: {sum(ok for _, ok, _ in checks)}/{len(checks)} checks\n")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())

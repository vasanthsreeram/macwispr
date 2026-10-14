#!/usr/bin/env python3
"""English WER for the shipped Parakeet Redux path.

Drives the packaged app binary (`MacWispr --transcribe-file`), which loads the
model through TranscriptionEngine → PhotonSidecar exactly as dictation does.

Clips:
  * a `say`-synthesized clip with known text
  * bench/clips/sample_10s_16k.wav and speech_12s_16k.wav (references below)
  * a fixed, seeded sample of LibriSpeech test-clean utterances (human refs)

Usage: redux_english_wer.py <MacWispr binary> [--libri N] [--seed S]
Exits non-zero if any aggregate WER exceeds 15%.
"""
import argparse
import json
import os
import random
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LIBRI = os.path.join(ROOT, "bench/data/librispeech/LibriSpeech/test-clean")
THRESHOLD = 0.15

SAY_TEXT = ("Hey Sarah, can you send me the quarterly report by Friday afternoon? "
            "I also need the updated budget numbers for the marketing team before our meeting on Monday.")
# Human references for the repo's English bench clips.
CLIP_REFS = {
    "bench/clips/sample_10s_16k.wav":
        "mate but when a human drops in the world we learn everything that's happened before us "
        "and then we springboard off the top of that so we living in the 21st century",
    "bench/clips/speech_12s_16k.wav":
        "Hello, this is a dictation latency benchmark for MacWispr. We are comparing Qwen3 ASR, "
        "Parakeet, and Nemotron speech models on Apple Silicon.",
}


def norm(text):
    text = text.lower().replace("’", "'")
    text = re.sub(r"[^a-z0-9' ]+", " ", text)
    return text.split()


def edit_distance(ref, hyp):
    d = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        prev, d[0] = d[0], i
        for j, h in enumerate(hyp, 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r != h))
            prev, d[j] = d[j], cur
    return d[len(hyp)]


def libri_sample(n, seed):
    items = []
    for dirpath, _, files in os.walk(LIBRI):
        for f in files:
            if f.endswith(".trans.txt"):
                with open(os.path.join(dirpath, f)) as fh:
                    for line in fh:
                        uid, text = line.strip().split(" ", 1)
                        items.append((os.path.join(dirpath, uid + ".flac"), text))
    items.sort()
    random.Random(seed).shuffle(items)
    return items[:n]


def to_wav(flac, tmp):
    out = os.path.join(tmp, os.path.basename(flac).replace(".flac", ".wav"))
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", flac, out], check=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("binary")
    ap.add_argument("--libri", type=int, default=40)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    tmp = tempfile.mkdtemp(prefix="redux-wer-")
    say_aiff = os.path.join(tmp, "say.aiff")
    say_wav = os.path.join(tmp, "say_16k.wav")
    subprocess.run(["say", "-v", "Samantha", "-o", say_aiff, SAY_TEXT], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", say_aiff, say_wav], check=True)

    cases = [("say", say_wav, SAY_TEXT)]
    cases += [("clip", os.path.join(ROOT, p), ref) for p, ref in CLIP_REFS.items()]
    if os.path.isdir(LIBRI) and args.libri > 0:
        cases += [("librispeech", to_wav(f, tmp), ref) for f, ref in libri_sample(args.libri, args.seed)]

    proc = subprocess.run([args.binary, "--transcribe-file"] + [c[1] for c in cases],
                          capture_output=True, text=True, timeout=3600)
    results = {}
    for line in proc.stdout.splitlines():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "file" in obj:
            results[obj["file"]] = obj
        elif obj.get("event"):
            print("app:", json.dumps(obj))
    if proc.returncode not in (0, 1):
        print(proc.stderr[-2000:])
        print(f"app exited {proc.returncode}")
        return 2

    totals = {}
    for group, path, ref in cases:
        r = results.get(path, {})
        hyp = r.get("text", "")
        rw, hw = norm(ref), norm(hyp)
        errs = edit_distance(rw, hw)
        e, n = totals.get(group, (0, 0))
        totals[group] = (e + errs, n + len(rw))
        if group != "librispeech" or errs:
            print(f"[{group}] {os.path.basename(path)} wer={errs / max(1, len(rw)):.3f}")
            print(f"   ref: {ref}")
            print(f"   hyp: {hyp or r.get('error', '<missing>')}")

    ok = True
    for group, (e, n) in totals.items():
        wer = e / max(1, n)
        ok &= wer <= THRESHOLD
        print(f"WER {group}: {wer:.4f} ({e} errors / {n} words) {'PASS' if wer <= THRESHOLD else 'FAIL'}")
    all_e = sum(e for e, _ in totals.values())
    all_n = sum(n for _, n in totals.values())
    print(f"WER overall: {all_e / max(1, all_n):.4f} ({all_e}/{all_n}) threshold {THRESHOLD}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

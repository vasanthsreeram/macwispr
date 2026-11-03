"""End-to-end dictation through a real Windows audio endpoint (CI with VB-CABLE).

Runs the *installed* MacWispr.exe exactly as a user would (normal data folder,
normal microphone = the default recording device). Speech is played into
"CABLE Input" and reaches the app through the "CABLE Output" capture endpoint,
so PortAudio/WASAPI/MME capture, the hotkey hook, the model and the paste are
all the shipped code. Scenarios: hold mode, toggle mode, and a 68.8 s hold that
requires several speech segments.

The capture gate compares against the installed app's own transcription of each
clean source WAV. The old non-VAD transcripts remain diagnostics, since changing
the decoder also changes number formatting and proper nouns before capture.

    python tests/e2e_capture.py <MacWispr.exe> <clips dir> <evidence dir> [--denied]

--denied: run while the Windows microphone privacy switch is off and check that
the user gets the clear "Windows is blocking the microphone" error and nothing is pasted.
"""
from __future__ import annotations

import ctypes
import json
import os
import re
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path

import numpy as np
import sounddevice as sd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from macwispr_win import audio  # noqa: E402
from macwispr_win.config import SAMPLE_RATE  # noqa: E402
from macwispr_win.insert import send_keys  # noqa: E402

user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.FindWindowExW.restype = wintypes.HWND
user32.FindWindowExW.argtypes = (wintypes.HWND, wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR)
user32.SendMessageW.argtypes = (wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM)
user32.SendMessageW.restype = ctypes.c_ssize_t
WM_GETTEXT, WM_GETTEXTLENGTH = 0x000D, 0x000E
VK_MENU, VK_SPACE = 0x12, 0x20

# Historical non-VAD output, retained for comparison rather than used as ground truth.
LEGACY_REFERENCE = {
    "sample_10s_16k.wav": "But when a human drops in the world, we learn everything that's happened before us, "
                          "and then we springboard off the top of that. So we living in the 21st century.",
    "speech_12s_16k.wav": "Hello, this is a dictation latency benchmark for MacWisper. We are comparing Quinn III ASR, "
                          "Parakeet, and Nemotron speech models on Apple Silicon.",
}

FIXTURE_PHRASES = {
    "sample_10s_16k.wav": ("springboard", "century"),
    "speech_12s_16k.wav": ("benchmark", "parakeet", "silicon"),
}


def file_references(exe: str, clips: Path, ev: Path) -> dict[str, str]:
    """Establish an independent clean-file baseline with the exact installed build."""
    refs = {}
    for name, phrases in FIXTURE_PHRASES.items():
        report = (ev / f"reference_{Path(name).stem}.json").resolve()
        subprocess.run([exe, "--transcribe-file", str((clips / name).resolve()), "--out", str(report)],
                       check=True, timeout=300)
        result = json.loads(report.read_text(encoding="utf-8"))
        text = result["text"]
        assert all(phrase in text.lower() for phrase in phrases), f"invalid clean-file baseline for {name}: {text!r}"
        refs[name] = text
        print("clean-file reference:", name, json.dumps(result, ensure_ascii=False))
    return refs


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9']+", text.lower())


def wer(ref: str, hyp: str) -> float:
    r, h = words(ref), words(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / max(1, len(r))


def wait_for(pred, timeout, step=0.25):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = pred()
        if value:
            return value
        time.sleep(step)
    return None


def notepad():
    top = user32.FindWindowExW(None, None, "Notepad", None)
    edit = user32.FindWindowExW(top, None, "Edit", None) if top else None
    return (top, edit) if edit else None


def window_text(hwnd) -> str:
    n = user32.SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0)
    buf = ctypes.create_unicode_buffer(n + 1)
    user32.SendMessageW(hwnd, WM_GETTEXT, n + 1, ctypes.cast(buf, ctypes.c_void_p).value)
    return buf.value


def focus(hwnd) -> bool:
    send_keys([(VK_MENU, False), (VK_MENU, True)])  # lets this process hand over the foreground
    user32.ShowWindow(hwnd, 9)
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.5)
    return user32.GetForegroundWindow() == hwnd


def chord(down: bool):
    send_keys([(VK_MENU, False), (VK_SPACE, False)] if down else [(VK_SPACE, True), (VK_MENU, True)])


def play(samples: np.ndarray):
    sd.play(samples, SAMPLE_RATE)  # default output device = CABLE Input
    sd.wait()


def run_scenario(exe: str, log: Path, name: str, mode: str, clip_names: list[str], clips: Path, ev: Path,
                 refs: dict[str, str]) -> dict:
    data = log.parent
    (data / "settings.json").write_text(json.dumps({"mode": mode}), encoding="utf-8")
    log_start = log.stat().st_size if log.exists() else 0

    def new_log() -> str:
        if not log.exists():
            return ""
        with open(log, "rb") as f:
            f.seek(log_start)
            return f.read().decode("utf-8", "replace")

    note = subprocess.Popen(["notepad.exe"])
    app = subprocess.Popen([exe])  # normal start: no flags, normal data folder and default microphone
    try:
        top, edit = wait_for(notepad, 20)
        assert wait_for(lambda: "status: ready" in new_log(), 300, 1), f"{name}: never ready\n{new_log()}"
        assert focus(top), f"{name}: could not focus Notepad"
        speech = np.concatenate([audio.read_wav(clips / c) for c in clip_names])
        ref = " ".join(refs[c] for c in clip_names)
        legacy_ref = " ".join(LEGACY_REFERENCE[c] for c in clip_names)

        started = time.monotonic()
        chord(True)
        if mode == "toggle":
            time.sleep(0.15)
            chord(False)  # tap: start
        time.sleep(0.6)  # past the start chime
        play(speech)
        time.sleep(0.6)
        if mode == "toggle":
            chord(True)
            time.sleep(0.15)
        chord(False)  # hold: release / toggle: second tap -> stop
        held = time.monotonic() - started

        assert wait_for(lambda: "transcribed" in new_log(), 300, 0.5), f"{name}: no transcription\n{new_log()}"
        text = wait_for(lambda: window_text(edit).strip(), 15)
        time.sleep(1.0)
        text = window_text(edit)
        result = {
            "scenario": name, "mode": mode, "clips": clip_names, "speech_seconds": round(len(speech) / SAMPLE_RATE, 2),
            "hotkey_seconds": round(held, 2), "pasted_text": text, "wer_vs_file_transcript": round(wer(ref, text or ""), 4),
            "reference_text": ref, "reference_method": "installed app --transcribe-file (same VAD decoder)",
            "wer_vs_legacy_non_vad_transcript": round(wer(legacy_ref, text or ""), 4),
            "log": [l for l in new_log().splitlines() if "capture" in l or "transcribed" in l or "status:" in l],
        }
        if len(clip_names) > 1:
            result["springboard_count"] = text.lower().count("springboard")
            result["benchmark_count"] = text.lower().count("benchmark")
            result["expected_counts"] = {"springboard": clip_names.count("sample_10s_16k.wav"),
                                         "benchmark": clip_names.count("speech_12s_16k.wav")}
        (ev / f"e2e_{name}.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return result
    finally:
        app.kill()
        note.kill()
        time.sleep(1)


def run_denied(exe: str, log: Path, ev: Path) -> int:
    log_start = log.stat().st_size if log.exists() else 0

    def new_log() -> str:
        with open(log, "rb") as f:
            f.seek(log_start)
            return f.read().decode("utf-8", "replace")

    note = subprocess.Popen(["notepad.exe"])
    app = subprocess.Popen([exe])
    try:
        top, edit = wait_for(notepad, 20)
        assert wait_for(lambda: log.exists() and "status: ready" in new_log(), 300, 1), "never ready"
        focus(top)
        chord(True)
        time.sleep(2)
        chord(False)
        found = wait_for(lambda: "Windows is blocking the microphone" in new_log(), 20, 0.5)
        time.sleep(1)
        result = {"scenario": "microphone_denied", "clear_error_logged": bool(found), "pasted_text": window_text(edit),
                  "log": [l for l in new_log().splitlines() if "status:" in l or "MicrophoneAccessDenied" in l
                          or "dictation failed" in l or "MME error" in l]}
        (ev / "e2e_microphone_denied.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 0 if found and not result["pasted_text"] else 1
    finally:
        app.kill()
        note.kill()
        time.sleep(1)


def main() -> int:
    exe, clips, ev = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    ev.mkdir(parents=True, exist_ok=True)
    log = Path(os.environ["LOCALAPPDATA"]) / "MacWispr" / "macwispr.log"
    if "--denied" in sys.argv:
        return run_denied(exe, log, ev)
    print("default input:", sd.query_devices(kind="input")["name"], "| default output:", sd.query_devices(kind="output")["name"])
    s10, s12 = "sample_10s_16k.wav", "speech_12s_16k.wav"
    refs = file_references(exe, clips, ev)
    results = [
        run_scenario(exe, log, "hold", "hold", [s10], clips, ev, refs),
        run_scenario(exe, log, "toggle", "toggle", [s12], clips, ev, refs),
        run_scenario(exe, log, "long_hold_68s", "hold", [s10, s12, s10, s12, s10, s12, s10], clips, ev, refs),
    ]
    failures = []
    for r in results:
        if not r["pasted_text"].strip():
            failures.append(f"{r['scenario']}: nothing pasted")
        elif r["wer_vs_file_transcript"] > 0.15:
            failures.append(f"{r['scenario']}: WER {r['wer_vs_file_transcript']}")
        if r["pasted_text"].startswith(" "):
            failures.append(f"{r['scenario']}: Space leaked into the app")
        if "expected_counts" in r and (r["springboard_count"], r["benchmark_count"]) != tuple(r["expected_counts"].values()):
            failures.append(f"{r['scenario']}: phrase counts {r['springboard_count']}/{r['benchmark_count']} != {r['expected_counts']}")
    print("FAILURES:", failures or "none")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

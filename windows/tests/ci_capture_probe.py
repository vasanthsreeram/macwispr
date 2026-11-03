"""Probe the Windows capture path on a machine with VB-CABLE.

1. Lists every PortAudio host API / device and tries opening each CABLE Output
   capture endpoint at the app's 16 kHz mono and at the device's native format.
2. Round-trip: plays a known WAV to the default output (CABLE Input) while the
   app's own `Recorder` captures from the default input (CABLE Output), saves the
   captured WAV and measures how closely it matches the source.

    python tests/ci_capture_probe.py <speech.wav> <out dir>
"""
import json
import logging
import sys
import threading
import time
from pathlib import Path

import numpy as np
import sounddevice as sd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from macwispr_win import audio  # noqa: E402
from macwispr_win.config import SAMPLE_RATE  # noqa: E402


def try_open(index, rate, channels):
    try:
        with sd.InputStream(device=index, samplerate=rate, channels=channels, dtype="float32") as s:
            time.sleep(0.2)
            return {"ok": True, "rate": s.samplerate, "channels": s.channels}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def main():
    logging.basicConfig(level=logging.INFO, stream=sys.stdout, format="%(name)s: %(message)s")
    wav, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    report = {"portaudio": sd.get_portaudio_version()[1], "hostapis": [], "default_device": list(sd.default.device)}
    for i, api in enumerate(sd.query_hostapis()):
        report["hostapis"].append({"index": i, "name": api["name"], "default_input": api["default_input_device"],
                                   "default_output": api["default_output_device"]})
    devices = []
    for i, d in enumerate(sd.query_devices()):
        entry = {"index": i, "name": d["name"], "hostapi": sd.query_hostapis(d["hostapi"])["name"],
                 "in": d["max_input_channels"], "out": d["max_output_channels"], "native_rate": d["default_samplerate"]}
        if d["max_input_channels"] > 0:
            entry["open_16k_mono"] = try_open(i, SAMPLE_RATE, 1)
            entry["open_native_rate_mono"] = try_open(i, d["default_samplerate"], 1)
            entry["open_native"] = try_open(i, d["default_samplerate"], d["max_input_channels"])
        devices.append(entry)
    report["devices"] = devices

    src = audio.read_wav(wav)
    out_info = sd.query_devices(kind="output")
    lead = np.zeros(int(0.5 * SAMPLE_RATE), dtype=np.float32)
    rec = audio.Recorder()  # the app's capture class, default input device, as the app uses it
    rec.start()
    play_status = {}

    def player():
        # High output latency so the test's own playback doesn't underrun on a busy runner.
        sd.play(np.concatenate([lead, src]), SAMPLE_RATE, latency="high")
        sd.wait()
        play_status["flags"] = str(sd.get_status())

    t = threading.Thread(target=player)
    t.start()
    t.join()
    time.sleep(0.5)
    captured = rec.stop()
    capture_status = sorted(rec._statuses)
    audio.write_wav(out / "roundtrip_captured.wav", captured)

    # Align by cross-correlation (FFT) and compare against the source.
    n = 1 << int(np.ceil(np.log2(len(captured) + len(src))))
    xc = np.fft.irfft(np.fft.rfft(captured, n) * np.conj(np.fft.rfft(src, n)), n)
    lag = int(np.argmax(xc[: len(captured)]))
    seg = captured[lag: lag + len(src)]
    m = min(len(seg), len(src))
    corr = float(np.corrcoef(seg[:m], src[:m])[0, 1]) if m > SAMPLE_RATE else 0.0
    # Per-second alignment: a single dropped/inserted buffer shifts the lag and drags the
    # global figure down, so also report each second aligned on its own.
    windows = []
    for w in range(int(len(src) / SAMPLE_RATE) - 1):
        ref = src[w * SAMPLE_RATE:(w + 1) * SAMPLE_RATE]
        base = lag + w * SAMPLE_RATE
        best = max(range(max(0, base - 800), base + 800, 4),
                   key=lambda L: abs(float(np.dot(captured[L:L + SAMPLE_RATE], ref))) if L + SAMPLE_RATE <= len(captured) else 0)
        windows.append({"second": w, "lag_seconds": round(best / SAMPLE_RATE - w, 4),
                        "correlation": round(float(np.corrcoef(captured[best:best + SAMPLE_RATE], ref)[0, 1]), 3)})
    report["roundtrip"] = {
        "output_device": out_info["name"], "input_device": sd.query_devices(kind="input")["name"],
        "source_seconds": round(len(src) / SAMPLE_RATE, 2), "captured_seconds": round(len(captured) / SAMPLE_RATE, 2),
        "lag_seconds": round(lag / SAMPLE_RATE, 3), "correlation": round(corr, 4),
        "captured_peak": round(float(np.abs(captured).max()), 4) if len(captured) else 0.0,
        "gain": round(float(np.std(seg[:m]) / (np.std(src[:m]) + 1e-9)), 3) if m else 0.0,
        "playback_status": play_status.get("flags"), "capture_status": capture_status or "ok",
        "per_second": windows,
    }
    (out / "capture_probe.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    lags = {w["lag_seconds"] for w in windows}
    if capture_status:
        raise SystemExit(f"capture reported {capture_status}")
    if corr < 0.9:
        raise SystemExit(f"round-trip correlation {corr} < 0.9 (per-second lags {sorted(lags)}, "
                         f"playback status {play_status.get('flags')!r})")


if __name__ == "__main__":
    main()

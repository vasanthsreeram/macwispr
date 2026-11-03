# MacWispr for Windows (preview, not yet released)

A tray app for Windows 10/11 x64. Hold **Alt+Space**, speak, let go, and the text is
pasted into whatever app has focus. Speech recognition runs on your PC; no account,
no telemetry, no cloud.

> Status: built and tested only in CI (see "Testing"). It has not been tested with a real
> microphone on a Windows PC yet, so the website does not offer it.

## Install

1. Download `MacWispr-<version>-windows-x64-setup.exe` (or the portable `.zip`).
2. Run it. The build is not code-signed yet, so SmartScreen shows "Windows protected your PC":
   click **More info → Run anyway**. It installs per-user (no admin) to
   `%LOCALAPPDATA%\Programs\MacWispr`, with an optional "start when I sign in" shortcut.
3. The first launch downloads the speech model (about 670 MB, one time) to
   `%LOCALAPPDATA%\MacWispr\models`. The tray icon shows a grey dot until it is ready.
4. Allow microphone access if Windows asks (Settings → Privacy → Microphone →
   "Let desktop apps access your microphone").
5. Hold **Alt+Space**, speak, release. The tray menu switches to tap-to-start/tap-to-stop.

Alt+Space normally opens a window's system menu; MacWispr swallows the chord while it runs.

## Model choice

The Mac app (1.3.0) runs Moondream **Parakeet Redux** on the Photon/kestrel runtime. Windows
uses **NVIDIA Parakeet TDT 0.6B v3**, the model Redux is derived from, as an int8 ONNX export
(`istupakov/parakeet-tdt-0.6b-v3-onnx`) on ONNX Runtime CPU via `onnx-asr`:

- Same languages as Redux (English + 25 European languages), and it runs on any x64 CPU
  with no GPU or CUDA.
- Redux on Windows would need torch plus kestrel's native kernels in a Python sidecar; whether
  those run on a plain Windows CPU is untested, and the download is much larger.
- Cost: a bigger model download (about 670 MB vs. about 180 MB for Redux), and about 1.4 s
  to transcribe a 10 s clip on a 4-core laptop CPU (measured on Linux, same ONNX build).

## What's included / not included

Included: hold and toggle modes, paste via clipboard + Ctrl+V (restores your clipboard),
soft beeps, local history (`history.jsonl`), log file, single instance, per-user installer.

Not included yet: live draft text, meetings, the `macwispr` CLI/MCP server, custom vocabulary,
hotkey rebinding, auto-update, code signing. Elevated (admin) windows can't receive the paste
from a non-admin MacWispr (Windows UIPI); the text stays on the clipboard.

## Build

On Windows with Python 3.12 (and optionally Inno Setup 6 for the installer):

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File build.ps1   # unit tests, PyInstaller, zip, installer -> out\
```

## Testing

- `pytest tests` — hotkey state machine, settings, WAV I/O, controller (runs on any OS).
- `MacWispr.exe --self-test --wav <speech.wav> --out report.json` — clipboard round-trip,
  keyboard hook install, 1 s microphone capture, model download + transcription.
- `tests\ci_capture_probe.py` and `tests\e2e_capture.py` — CI only. They install the signed VB-Audio
  Virtual Cable (`tests\ci_install_vbcable.ps1`), play known speech into "CABLE Input", and let the
  installed app capture it from the "CABLE Output" recording device. They check the round-trip
  fidelity, then hold mode, toggle mode and a 68.8 s dictation pasted into Notepad.
- `.github/workflows/windows.yml` runs all of the above on a GitHub `windows-2022` runner.

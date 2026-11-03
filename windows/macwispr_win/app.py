"""MacWispr for Windows: tray app. Hold (or tap) Alt+Space, speak, and the text is pasted where you type."""
from __future__ import annotations

import argparse
import ctypes
import json
import logging
import os
import queue
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

from . import audio as audio_mod
from .config import APP_NAME, MODEL_DOWNLOAD_LABEL, SAMPLE_RATE, VERSION, Settings, data_dir, model_installed
from .hotkey import VK_MASK, ChordTracker

log = logging.getLogger("macwispr")


def setup_logging() -> Path:
    path = data_dir() / "macwispr.log"
    logging.basicConfig(filename=str(path), level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    return path


def chime(kind: str) -> None:
    import winsound

    freq, ms = {"start": (880, 60), "stop": (660, 60), "error": (220, 160)}[kind]
    threading.Thread(target=winsound.Beep, args=(freq, ms), daemon=True).start()


class DictationController:
    """Owns recording -> transcription -> insertion. Hotkey events arrive on a queue."""

    def __init__(self, settings: Settings, transcriber, recorder=None, status_cb=None):
        self.settings = settings
        self.transcriber = transcriber
        self.recorder = recorder or audio_mod.Recorder()
        self.status_cb = status_cb or (lambda s: None)
        self.events: queue.Queue[str] = queue.Queue()
        self.status = "loading"
        self.last_text = ""
        self.last_result = ""
        self.last_error = ""
        self.done = threading.Event()  # set after each finished dictation (tests wait on it)
        self._worker = threading.Thread(target=self._run, name="dictation", daemon=True)

    # Called from the keyboard hook thread: must return immediately.
    def hotkey_pressed(self):
        self.events.put("press")

    def hotkey_released(self):
        self.events.put("release")

    def start(self):
        self._worker.start()
        threading.Thread(target=self._load_model, name="model-load", daemon=True).start()

    def _set_status(self, status: str):
        log.info("status: %s", status)
        self.status = status
        self.status_cb(status)

    def _load_model(self):
        try:
            if not model_installed(self.transcriber.path):
                self._set_status("downloading")
            self.transcriber.load()
            self._set_status("ready")
        except Exception as exc:
            log.exception("model load failed")
            self.last_error = f"Model setup failed: {exc}"
            self._set_status("error")

    def _run(self):
        while True:
            event = self.events.get()
            if event == "quit":
                return
            try:
                self._handle(event)
            except Exception as exc:
                log.exception("dictation failed")
                self.last_error = str(exc)
                if self.recorder.recording:
                    self.recorder.stop()
                self._set_status("error" if not self.transcriber.loaded else "ready")
                if self.settings.sounds:
                    chime("error")
                self.done.set()

    def _handle(self, event: str):
        recording = self.recorder.recording
        if event == "press":
            if recording and self.settings.mode == "toggle":
                self._finish()
            elif not recording:
                self.recorder.start()
                self._set_status("recording")
                if self.settings.sounds:
                    chime("start")
        elif event == "release" and recording and self.settings.mode == "hold":
            self._finish()

    def _finish(self):
        samples = self.recorder.stop()
        if self.settings.sounds:
            chime("stop")
        self._set_status("transcribing")
        started = time.monotonic()
        text = self.transcriber.transcribe(samples)
        took = time.monotonic() - started
        log.info("transcribed %.1fs of audio in %.2fs (%d chars)", len(samples) / SAMPLE_RATE, took, len(text))
        if text:
            from .insert import insert_text

            self.last_result = insert_text(text, paste=self.settings.auto_paste,
                                           restore_clipboard=self.settings.restore_clipboard)
            self.last_text = text
            if self.settings.save_history:
                self._append_history(text, len(samples) / SAMPLE_RATE, took)
        else:
            self.last_result = "empty"
        self._set_status("ready")
        self.done.set()

    def _append_history(self, text: str, seconds: float, took: float):
        entry = {"time": datetime.now(timezone.utc).isoformat(timespec="seconds"), "text": text,
                 "audio_seconds": round(seconds, 1), "stt_seconds": round(took, 2)}
        with open(data_dir() / "history.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def stop(self):
        self.events.put("quit")


# ---------------------------------------------------------------- tray UI

STATUS_TEXT = {
    "loading": "Loading speech model…",
    "downloading": f"Downloading speech model ({MODEL_DOWNLOAD_LABEL}, one time)…",
    "ready": "Ready: hold Alt+Space to dictate",
    "recording": "Listening…",
    "transcribing": "Transcribing…",
    "error": "Error (see log)",
}
STATUS_COLOR = {"loading": (150, 150, 150), "downloading": (150, 150, 150),
                "recording": (230, 40, 40), "transcribing": (240, 170, 0), "error": (120, 0, 0)}


def _asset(name: str) -> Path:
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))
    return base / "assets" / name


def tray_icon_image(status: str):
    """Brand icon with a status dot (red = listening, amber = transcribing, grey = loading)."""
    from PIL import Image, ImageDraw

    try:
        img = Image.open(_asset("MacWispr.ico")).convert("RGBA").resize((64, 64))
    except OSError:
        img = Image.new("RGBA", (64, 64), (91, 76, 230, 255))
    if status != "ready":
        d = ImageDraw.Draw(img)
        d.ellipse((34, 34, 63, 63), fill=STATUS_COLOR.get(status, (30, 30, 30)), outline="white", width=3)
    return img


def run_tray(controller: DictationController, settings: Settings, log_path: Path) -> None:
    import pystray

    def ready_text(_):
        s = controller.status
        if s == "ready" and settings.mode == "toggle":
            return "Ready: tap Alt+Space to start/stop"
        if s == "error" and controller.last_error:
            return f"Error: {controller.last_error[:80]}"
        return STATUS_TEXT.get(s, s)

    def set_mode(mode):
        def _set(icon, item):
            settings.mode = mode
            settings.save()
        return _set

    def toggle(attr):
        def _toggle(icon, item):
            setattr(settings, attr, not getattr(settings, attr))
            settings.save()
        return _toggle

    def open_folder(icon, item):
        os.startfile(str(data_dir()))

    def quit_app(icon, item):
        controller.stop()
        icon.stop()

    menu = pystray.Menu(
        pystray.MenuItem(ready_text, None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Hold Alt+Space to talk", set_mode("hold"), checked=lambda _: settings.mode == "hold", radio=True),
        pystray.MenuItem("Tap Alt+Space to start/stop", set_mode("toggle"), checked=lambda _: settings.mode == "toggle", radio=True),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Paste into the focused app", toggle("auto_paste"), checked=lambda _: settings.auto_paste),
        pystray.MenuItem("Restore clipboard after paste", toggle("restore_clipboard"), checked=lambda _: settings.restore_clipboard),
        pystray.MenuItem("Sounds", toggle("sounds"), checked=lambda _: settings.sounds),
        pystray.MenuItem("Save history on this PC", toggle("save_history"), checked=lambda _: settings.save_history),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Open data folder (history, log)", open_folder),
        pystray.MenuItem(f"{APP_NAME} for Windows {VERSION}", None, enabled=False),
        pystray.MenuItem("Quit", quit_app),
    )
    icon = pystray.Icon(APP_NAME, tray_icon_image("loading"), f"{APP_NAME}", menu)

    def on_status(status):
        icon.icon = tray_icon_image(status)
        icon.title = f"{APP_NAME}: {STATUS_TEXT.get(status, status)}"
        icon.update_menu()

    controller.status_cb = on_status
    icon.run()


# ---------------------------------------------------------------- entry points

def single_instance() -> bool:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateMutexW(None, False, "Local\\MacWisprWindowsSingleInstance")
    return ctypes.get_last_error() != 183  # ERROR_ALREADY_EXISTS


def install_hotkey(controller: DictationController):
    from .hotkey import KeyboardHook
    from .insert import tap

    tracker = ChordTracker(controller.hotkey_pressed, controller.hotkey_released)
    hook = KeyboardHook(tracker, lambda: tap(VK_MASK))
    hook.start()
    return hook


def write_out(path: str | None, payload: dict) -> None:
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    if path:
        Path(path).write_text(text, encoding="utf-8")
    if sys.stdout is not None:
        print(text)


def cmd_transcribe(args) -> int:
    from .asr import Transcriber

    t = Transcriber()
    started = time.monotonic()
    t.load()
    loaded = time.monotonic()
    samples = audio_mod.read_wav(args.transcribe_file)
    text = t.transcribe(samples)
    write_out(args.out, {"text": text, "audio_seconds": round(len(samples) / SAMPLE_RATE, 2),
                         "load_seconds": round(loaded - started, 2),
                         "stt_seconds": round(time.monotonic() - loaded, 2)})
    return 0


def cmd_self_test(args) -> int:
    """End-to-end check of each subsystem on this machine. Writes a JSON report."""
    from .asr import Transcriber
    from .insert import get_clipboard_text, set_clipboard_text

    report: dict = {"version": VERSION, "checks": {}}
    checks = report["checks"]

    def check(name, fn):
        try:
            checks[name] = {"ok": True, "detail": fn()}
        except Exception as exc:
            checks[name] = {"ok": False, "detail": f"{type(exc).__name__}: {exc}"}

    def clip():
        old = get_clipboard_text()
        probe = "MacWispr clipboard probe ✓"
        assert set_clipboard_text(probe) and get_clipboard_text() == probe
        if old is not None:
            set_clipboard_text(old)
        return "round-trip ok"

    def hook():
        controller = DictationController(Settings(), transcriber=None)
        h = install_hotkey(controller)
        h.stop()
        return "WH_KEYBOARD_LL installed"

    def mic():
        devices = audio_mod.input_devices()
        r = audio_mod.Recorder()
        r.start()
        time.sleep(1.0)
        samples = r.stop()
        return {"devices": devices, "captured_seconds": round(len(samples) / SAMPLE_RATE, 2),
                "peak": round(float(abs(samples).max()) if len(samples) else 0.0, 4)}

    def model():
        t = Transcriber()
        s = time.monotonic()
        t.load()
        out = {"load_seconds": round(time.monotonic() - s, 2)}
        if args.wav:
            samples = audio_mod.read_wav(args.wav)
            s = time.monotonic()
            out["text"] = t.transcribe(samples)
            out["stt_seconds"] = round(time.monotonic() - s, 2)
        return out

    check("clipboard", clip)
    check("hotkey_hook", hook)
    check("microphone", mic)
    check("model", model)
    report["ok"] = all(c["ok"] for c in checks.values())
    write_out(args.out, report)
    return 0 if report["ok"] else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog=APP_NAME)
    parser.add_argument("--version", action="store_true")
    parser.add_argument("--transcribe-file", metavar="WAV")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--wav", help="speech sample for --self-test")
    parser.add_argument("--out", help="write JSON result to this file (the GUI build has no console)")
    parser.add_argument("--fake-mic", metavar="WAV", help=argparse.SUPPRESS)  # testing in VMs without a mic
    args = parser.parse_args(argv)

    log_path = setup_logging()
    if args.version:
        write_out(args.out, {"version": VERSION})
        return 0
    if args.transcribe_file:
        return cmd_transcribe(args)
    if args.self_test:
        return cmd_self_test(args)

    if not single_instance():
        ctypes.windll.user32.MessageBoxW(None, f"{APP_NAME} is already running (see the tray).", APP_NAME, 0x40)
        return 0
    from .asr import Transcriber

    settings = Settings.load()
    recorder = FileRecorder(args.fake_mic) if args.fake_mic else None
    controller = DictationController(settings, Transcriber(), recorder=recorder)
    log.info("%s for Windows %s starting (mode=%s)", APP_NAME, VERSION, settings.mode)
    controller.start()
    hook = install_hotkey(controller)
    try:
        run_tray(controller, settings, log_path)
    finally:
        hook.stop()
    return 0


class FileRecorder:
    """Stands in for the microphone with a WAV file, trimmed to how long the hotkey was held."""

    def __init__(self, path: str):
        self.samples = audio_mod.read_wav(path)
        self._started: float | None = None

    @property
    def recording(self) -> bool:
        return self._started is not None

    def start(self):
        self._started = time.monotonic()

    def stop(self):
        held = time.monotonic() - (self._started or time.monotonic())
        self._started = None
        return self.samples[: int(held * SAMPLE_RATE)]

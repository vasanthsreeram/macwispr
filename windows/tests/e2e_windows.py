"""End-to-end check on a real Windows desktop (CI runner or test PC).

Starts Notepad and the built MacWispr.exe with --fake-mic (a WAV stands in for
the microphone), holds Alt+Space through SendInput, and waits for the
transcript to be pasted into Notepad.  Everything else is the shipped path:
low-level keyboard hook, controller, Parakeet model, clipboard + Ctrl+V.

    python tests/e2e_windows.py dist\\MacWispr\\MacWispr.exe ..\\bench\\clips\\sample_10s_16k.wav springboard
"""
from __future__ import annotations

import ctypes
import os
import subprocess
import sys
import tempfile
import time
from ctypes import wintypes
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from macwispr_win.insert import send_keys  # noqa: E402

user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.FindWindowExW.restype = wintypes.HWND
user32.FindWindowExW.argtypes = (wintypes.HWND, wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR)
user32.SendMessageW.argtypes = (wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM)
user32.SendMessageW.restype = ctypes.c_ssize_t
WM_GETTEXT, WM_GETTEXTLENGTH = 0x000D, 0x000E
VK_MENU, VK_SPACE = 0x12, 0x20


def wait_for(pred, timeout, step=0.5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = pred()
        if value:
            return value
        time.sleep(step)
    return None


def notepad_edit():
    top = user32.FindWindowExW(None, None, "Notepad", None)
    if not top:
        return None
    for cls in ("Edit", "RichEditD2DPT"):
        child = user32.FindWindowExW(top, None, cls, None)
        if child:
            return top, child
    return None


def window_text(hwnd) -> str:
    n = user32.SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0)
    buf = ctypes.create_unicode_buffer(n + 1)
    user32.SendMessageW(hwnd, WM_GETTEXT, n + 1, ctypes.cast(buf, ctypes.c_void_p).value)
    return buf.value


def focus(hwnd):
    # Windows only lets the foreground process hand focus over; an Alt tap unlocks it.
    send_keys([(VK_MENU, False), (VK_MENU, True)])
    user32.ShowWindow(hwnd, 9)
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.5)
    return user32.GetForegroundWindow() == hwnd


def main() -> int:
    exe, wav, expected = sys.argv[1], sys.argv[2], sys.argv[3].lower()
    data = Path(tempfile.mkdtemp(prefix="macwispr-e2e-"))
    env = dict(os.environ, MACWISPR_DATA_DIR=str(data))
    if os.environ.get("MACWISPR_MODEL_SOURCE"):  # reuse an already-downloaded model
        target = data / "MacWispr" / "models"
        target.mkdir(parents=True)
        subprocess.run(["cmd", "/c", "mklink", "/J", str(target / "parakeet-tdt-0.6b-v3-int8"),
                        os.environ["MACWISPR_MODEL_SOURCE"]], check=True)
    log = data / "MacWispr" / "macwispr.log"

    note = subprocess.Popen(["notepad.exe"])
    app = subprocess.Popen([exe, "--fake-mic", wav], env=env)
    try:
        found = wait_for(notepad_edit, 20)
        assert found, "Notepad window not found"
        top, edit = found
        ready = wait_for(lambda: log.exists() and "status: ready" in log.read_text(encoding="utf-8"), 900, 2)
        assert ready, f"MacWispr never became ready; log:\n{log.read_text(encoding='utf-8') if log.exists() else '(none)'}"
        print("focused notepad:", focus(top))

        send_keys([(VK_MENU, False), (VK_SPACE, False)])
        time.sleep(10.5)  # hold the chord for the length of the clip
        send_keys([(VK_SPACE, True), (VK_MENU, True)])

        text = wait_for(lambda: expected in window_text(edit).lower() and window_text(edit), 120)
        print("notepad text:", repr(window_text(edit)))
        print("log:\n" + log.read_text(encoding="utf-8"))
        assert text, "transcript was not pasted into Notepad"
        assert not text.startswith(" "), "Space leaked through to the focused app"
        # History is appended after the clipboard is restored, so give it a moment.
        assert wait_for((data / "MacWispr" / "history.jsonl").exists, 10), "history not written"
        print("E2E OK")
        return 0
    finally:
        app.kill()
        note.kill()


if __name__ == "__main__":
    sys.exit(main())

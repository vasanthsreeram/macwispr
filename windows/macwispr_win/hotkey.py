"""Global Alt+Space hotkey.

`ChordTracker` is the platform-independent state machine; `KeyboardHook` feeds
it from a Win32 low-level keyboard hook (WH_KEYBOARD_LL) so the chord works in
every app and Space is swallowed while the chord is active (Windows would
otherwise open the window's system menu).
"""
from __future__ import annotations

import ctypes
import logging
import sys
import threading
from typing import Callable

log = logging.getLogger(__name__)

VK_SPACE = 0x20
ALT_KEYS = {0x12, 0xA4, 0xA5}  # VK_MENU, VK_LMENU, VK_RMENU
# Unassigned virtual key; tapping it while Alt is held stops Windows from
# treating the later Alt release as "activate the menu bar".
VK_MASK = 0xE8


class ChordTracker:
    """Turns raw key events into press/release of the Alt+Space chord.

    `on_key` returns True when the event must be swallowed.
    """

    def __init__(self, on_press: Callable[[], None], on_release: Callable[[], None]):
        self.on_press = on_press
        self.on_release = on_release
        self.alt_down = False
        self.active = False

    def on_key(self, vk: int, is_down: bool) -> bool:
        if vk in ALT_KEYS:
            self.alt_down = is_down
            return False
        if vk != VK_SPACE:
            return False
        if is_down:
            if self.active:
                return True  # auto-repeat while held
            if self.alt_down:
                self.active = True
                self.on_press()
                return True
            return False
        if self.active:
            self.active = False
            self.on_release()
            return True
        return False


if sys.platform == "win32":
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    WH_KEYBOARD_LL = 13
    WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x0100, 0x0101, 0x0104, 0x0105
    WM_QUIT = 0x0012

    class KBDLLHOOKSTRUCT(ctypes.Structure):
        _fields_ = [
            ("vkCode", wintypes.DWORD),
            ("scanCode", wintypes.DWORD),
            ("flags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.c_size_t),
        ]

    LRESULT = ctypes.c_ssize_t
    HOOKPROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)
    user32.SetWindowsHookExW.argtypes = (ctypes.c_int, HOOKPROC, wintypes.HINSTANCE, wintypes.DWORD)
    user32.SetWindowsHookExW.restype = wintypes.HHOOK
    user32.CallNextHookEx.argtypes = (wintypes.HHOOK, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)
    user32.CallNextHookEx.restype = LRESULT
    user32.UnhookWindowsHookEx.argtypes = (wintypes.HHOOK,)
    user32.GetMessageW.argtypes = (ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT)
    user32.PostThreadMessageW.argtypes = (wintypes.DWORD, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM)
    kernel32.GetModuleHandleW.restype = wintypes.HMODULE
    kernel32.GetModuleHandleW.argtypes = (wintypes.LPCWSTR,)

    class KeyboardHook:
        """Runs the hook on its own thread with a message loop (required by WH_KEYBOARD_LL)."""

        def __init__(self, tracker: ChordTracker, send_mask_key: Callable[[], None]):
            self.tracker = tracker
            self.send_mask_key = send_mask_key
            self._thread: threading.Thread | None = None
            self._thread_id = 0
            self._hook = None
            self._ready = threading.Event()
            self.error: str | None = None
            self._proc = HOOKPROC(self._callback)  # keep a reference for the hook's lifetime

        def _callback(self, n_code, w_param, l_param):
            if n_code == 0:
                info = ctypes.cast(l_param, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
                is_down = w_param in (WM_KEYDOWN, WM_SYSKEYDOWN)
                try:
                    was_active = self.tracker.active
                    swallow = self.tracker.on_key(info.vkCode, is_down)
                    if swallow and is_down and not was_active:
                        self.send_mask_key()
                except Exception:  # never let an exception escape into the hook chain
                    log.exception("hotkey callback failed")
                    swallow = False
                if swallow:
                    return 1
            return user32.CallNextHookEx(self._hook, n_code, w_param, l_param)

        def _run(self):
            self._thread_id = kernel32.GetCurrentThreadId()
            self._hook = user32.SetWindowsHookExW(WH_KEYBOARD_LL, self._proc, kernel32.GetModuleHandleW(None), 0)
            if not self._hook:
                self.error = f"SetWindowsHookExW failed ({ctypes.get_last_error()})"
                self._ready.set()
                return
            self._ready.set()
            msg = wintypes.MSG()
            while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
                pass
            user32.UnhookWindowsHookEx(self._hook)

        def start(self) -> None:
            self._thread = threading.Thread(target=self._run, name="hotkey-hook", daemon=True)
            self._thread.start()
            self._ready.wait(5)
            if self.error:
                raise RuntimeError(self.error)

        def stop(self) -> None:
            if self._thread_id:
                user32.PostThreadMessageW(self._thread_id, WM_QUIT, 0, 0)

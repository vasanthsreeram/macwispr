"""Clipboard and keystroke injection (Win32)."""
from __future__ import annotations

import ctypes
import logging
import time
from ctypes import wintypes

log = logging.getLogger(__name__)

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

CF_UNICODETEXT = 13
GMEM_MOVEABLE = 0x0002
INPUT_KEYBOARD = 1
KEYEVENTF_KEYUP = 0x0002
VK_CONTROL, VK_V, VK_MENU = 0x11, 0x56, 0x12
VK_LWIN, VK_RWIN, VK_SHIFT = 0x5B, 0x5C, 0x10

kernel32.GlobalAlloc.argtypes = (wintypes.UINT, ctypes.c_size_t)
kernel32.GlobalAlloc.restype = wintypes.HGLOBAL
kernel32.GlobalLock.argtypes = (wintypes.HGLOBAL,)
kernel32.GlobalLock.restype = wintypes.LPVOID
kernel32.GlobalUnlock.argtypes = (wintypes.HGLOBAL,)
kernel32.GlobalFree.argtypes = (wintypes.HGLOBAL,)
user32.OpenClipboard.argtypes = (wintypes.HWND,)
user32.GetClipboardData.argtypes = (wintypes.UINT,)
user32.GetClipboardData.restype = wintypes.HANDLE
user32.SetClipboardData.argtypes = (wintypes.UINT, wintypes.HANDLE)
user32.SetClipboardData.restype = wintypes.HANDLE
user32.GetAsyncKeyState.argtypes = (ctypes.c_int,)
user32.GetAsyncKeyState.restype = ctypes.c_short


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]


class _INPUTUNION(ctypes.Union):
    _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("u", _INPUTUNION)]


user32.SendInput.argtypes = (wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int)
user32.SendInput.restype = wintypes.UINT


def _key(vk: int, up: bool = False) -> INPUT:
    return INPUT(type=INPUT_KEYBOARD, u=_INPUTUNION(ki=KEYBDINPUT(wVk=vk, dwFlags=KEYEVENTF_KEYUP if up else 0)))


def send_keys(events: list[tuple[int, bool]]) -> int:
    arr = (INPUT * len(events))(*[_key(vk, up) for vk, up in events])
    return user32.SendInput(len(events), arr, ctypes.sizeof(INPUT))


def tap(vk: int) -> None:
    send_keys([(vk, False), (vk, True)])


def _open_clipboard() -> bool:
    for _ in range(20):
        if user32.OpenClipboard(None):
            return True
        time.sleep(0.025)
    return False


def get_clipboard_text() -> str | None:
    if not _open_clipboard():
        return None
    try:
        handle = user32.GetClipboardData(CF_UNICODETEXT)
        if not handle:
            return None
        ptr = kernel32.GlobalLock(handle)
        try:
            return ctypes.wstring_at(ptr) if ptr else None
        finally:
            kernel32.GlobalUnlock(handle)
    finally:
        user32.CloseClipboard()


def set_clipboard_text(text: str) -> bool:
    data = ctypes.create_unicode_buffer(text)
    size = ctypes.sizeof(data)
    if not _open_clipboard():
        return False
    try:
        user32.EmptyClipboard()
        handle = kernel32.GlobalAlloc(GMEM_MOVEABLE, size)
        if not handle:
            return False
        ptr = kernel32.GlobalLock(handle)
        ctypes.memmove(ptr, data, size)
        kernel32.GlobalUnlock(handle)
        if not user32.SetClipboardData(CF_UNICODETEXT, handle):
            kernel32.GlobalFree(handle)
            return False
        return True  # the clipboard owns the memory now
    finally:
        user32.CloseClipboard()


def wait_for_modifiers_released(timeout: float = 2.0) -> None:
    """Pasting while Alt/Win/Shift is still physically held would send Ctrl+Alt+V etc."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not any(user32.GetAsyncKeyState(vk) & 0x8000 for vk in (VK_MENU, VK_LWIN, VK_RWIN, VK_SHIFT)):
            return
        time.sleep(0.02)


def insert_text(text: str, paste: bool = True, restore_clipboard: bool = True) -> str:
    """Put `text` on the clipboard and, when `paste`, send Ctrl+V to the focused window.

    Returns "pasted", "copied" or "failed".
    """
    previous = get_clipboard_text() if (paste and restore_clipboard) else None
    if not set_clipboard_text(text):
        return "failed"
    if not paste:
        return "copied"
    wait_for_modifiers_released()
    sent = send_keys([(VK_CONTROL, False), (VK_V, False), (VK_V, True), (VK_CONTROL, True)])
    if sent != 4:
        log.warning("SendInput sent %s/4 events (blocked by a higher-integrity window?)", sent)
        return "copied"
    if previous is not None:
        time.sleep(0.35)  # let the target app read the clipboard first
        set_clipboard_text(previous)
    return "pasted"

import sys
import types

import numpy as np

from macwispr_win import audio
from macwispr_win.config import SAMPLE_RATE, Settings
from macwispr_win.hotkey import VK_SPACE, ChordTracker

ALT = 0xA4


def make_tracker():
    events = []
    return ChordTracker(lambda: events.append("press"), lambda: events.append("release")), events


def test_alt_space_press_release_swallows_space():
    t, ev = make_tracker()
    assert t.on_key(ALT, True) is False
    assert t.on_key(VK_SPACE, True) is True
    assert t.on_key(VK_SPACE, True) is True  # auto-repeat swallowed, no second press
    assert t.on_key(VK_SPACE, False) is True
    assert t.on_key(ALT, False) is False
    assert ev == ["press", "release"]


def test_plain_space_passes_through():
    t, ev = make_tracker()
    assert t.on_key(VK_SPACE, True) is False
    assert t.on_key(VK_SPACE, False) is False
    assert ev == []


def test_alt_released_before_space_still_releases():
    t, ev = make_tracker()
    t.on_key(ALT, True)
    t.on_key(VK_SPACE, True)
    t.on_key(ALT, False)
    assert t.on_key(VK_SPACE, False) is True
    assert ev == ["press", "release"]


def test_settings_roundtrip_and_bad_values(tmp_path):
    p = tmp_path / "s.json"
    Settings(mode="toggle", sounds=False).save(p)
    s = Settings.load(p)
    assert s.mode == "toggle" and s.sounds is False
    p.write_text('{"mode": "nope", "unknown": 1}')
    assert Settings.load(p).mode == "hold"
    p.write_text("not json")
    assert Settings.load(p) == Settings()


def test_wav_roundtrip_and_resample(tmp_path):
    tone = (0.5 * np.sin(np.linspace(0, 200 * np.pi, SAMPLE_RATE))).astype(np.float32)
    audio.write_wav(tmp_path / "a.wav", tone)
    back = audio.read_wav(tmp_path / "a.wav")
    assert len(back) == SAMPLE_RATE and np.abs(back - tone).max() < 1e-3
    import wave
    with wave.open(str(tmp_path / "b.wav"), "wb") as w:  # 48 kHz stereo
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
        w.writeframes(np.zeros(48000 * 2, dtype="<i2").tobytes())
    assert len(audio.read_wav(tmp_path / "b.wav")) == SAMPLE_RATE


class FakeRecorder:
    def __init__(self):
        self.recording = False

    def start(self):
        self.recording = True

    def stop(self):
        self.recording = False
        return np.ones(SAMPLE_RATE, dtype=np.float32)


class FakeTranscriber:
    path = None
    loaded = True

    def transcribe(self, samples):
        return "hello world"


def run_controller(mode, events, monkeypatch, tmp_path):
    from macwispr_win import app

    monkeypatch.setenv("MACWISPR_DATA_DIR", str(tmp_path))
    inserted = []
    fake_insert = types.ModuleType("macwispr_win.insert")
    fake_insert.insert_text = lambda text, paste, restore_clipboard: inserted.append(text) or "pasted"
    monkeypatch.setitem(sys.modules, "macwispr_win.insert", fake_insert)
    c = app.DictationController(Settings(mode=mode, sounds=False), FakeTranscriber(), recorder=FakeRecorder())
    for e in events:
        c._handle(e)
    return c, inserted


def test_hold_mode_transcribes_on_release(monkeypatch, tmp_path):
    c, inserted = run_controller("hold", ["press", "release"], monkeypatch, tmp_path)
    assert inserted == ["hello world"] and c.last_result == "pasted"
    assert "hello world" in (tmp_path / "MacWispr" / "history.jsonl").read_text()


def test_toggle_mode_ignores_release(monkeypatch, tmp_path):
    c, inserted = run_controller("toggle", ["press", "release"], monkeypatch, tmp_path)
    assert inserted == [] and c.recorder.recording
    c._handle("press")
    assert inserted == ["hello world"]


def test_recording_error_is_reported_to_the_user(monkeypatch, tmp_path):
    from macwispr_win import app

    class BlockedRecorder(FakeRecorder):
        def start(self):
            raise RuntimeError("Windows is blocking the microphone.")

    monkeypatch.setenv("MACWISPR_DATA_DIR", str(tmp_path))
    c = app.DictationController(Settings(sounds=False), FakeTranscriber(), recorder=BlockedRecorder())
    shown = []
    c.error_cb = shown.append
    c.events.put("press")
    c.events.put("quit")
    c._run()
    assert shown == ["Windows is blocking the microphone."] and c.status == "ready"

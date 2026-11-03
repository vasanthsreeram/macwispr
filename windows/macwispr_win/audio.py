"""Microphone capture (PortAudio via sounddevice) and WAV helpers."""
from __future__ import annotations

import threading
import wave
from pathlib import Path

import numpy as np

from .config import SAMPLE_RATE

MAX_SECONDS = 10 * 60  # bound memory for a forgotten toggle-mode recording


class Recorder:
    def __init__(self, device: int | str | None = None):
        self.device = device
        self._chunks: list[np.ndarray] = []
        self._frames = 0
        self._lock = threading.Lock()
        self._stream = None

    @property
    def recording(self) -> bool:
        return self._stream is not None

    def _callback(self, indata, frames, time_info, status):
        with self._lock:
            if self._frames < MAX_SECONDS * SAMPLE_RATE:
                self._chunks.append(indata[:, 0].copy())
                self._frames += frames

    def start(self) -> None:
        import sounddevice as sd

        if self._stream is not None:
            return
        with self._lock:
            self._chunks, self._frames = [], 0
        self._stream = sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32",
                                      device=self.device, callback=self._callback)
        self._stream.start()

    def stop(self) -> np.ndarray:
        stream, self._stream = self._stream, None
        if stream is not None:
            stream.stop()
            stream.close()
        with self._lock:
            audio = np.concatenate(self._chunks) if self._chunks else np.zeros(0, dtype=np.float32)
            self._chunks = []
        return audio


def input_devices() -> list[str]:
    import sounddevice as sd

    return [d["name"] for d in sd.query_devices() if d["max_input_channels"] > 0]


def read_wav(path: str | Path) -> np.ndarray:
    """Read a PCM WAV as mono float32 at SAMPLE_RATE."""
    with wave.open(str(path), "rb") as w:
        rate, channels, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    if width == 2:
        audio = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif width == 4:
        audio = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    elif width == 1:
        audio = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    else:
        raise ValueError(f"unsupported WAV sample width {width}")
    if channels > 1:
        audio = audio.reshape(-1, channels).mean(axis=1)
    if rate != SAMPLE_RATE and len(audio):
        n = int(round(len(audio) * SAMPLE_RATE / rate))
        audio = np.interp(np.linspace(0, len(audio) - 1, n), np.arange(len(audio)), audio).astype(np.float32)
    return audio


def write_wav(path: str | Path, audio: np.ndarray) -> None:
    pcm = (np.clip(audio, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())

"""On-device speech recognition: Parakeet TDT 0.6B v3 (int8 ONNX) on ONNX Runtime CPU, behind Silero VAD."""
from __future__ import annotations

import logging
import threading
from pathlib import Path

import numpy as np

from .config import (MODEL_FILES, MODEL_NAME, MODEL_QUANTIZATION, MODEL_REPO, SAMPLE_RATE, VAD_FILES, VAD_NAME,
                     VAD_REPO, model_dir, vad_dir)

log = logging.getLogger(__name__)

MIN_SECONDS = 0.3
MAX_SEGMENT_SECONDS = 30  # VAD splits longer speech; Parakeet is trained on short utterances


def _fetch(repo: str, names, path: Path) -> None:
    from huggingface_hub import hf_hub_download

    path.mkdir(parents=True, exist_ok=True)
    for name in names:
        if not ((path / name).is_file() and (path / name).stat().st_size > 0):
            log.info("downloading %s/%s", repo, name)
            hf_hub_download(repo, name, local_dir=str(path))


def download_model(path: Path | None = None) -> Path:
    """Fetch the model files from Hugging Face once; later runs are offline."""
    path = path or model_dir()
    _fetch(MODEL_REPO, MODEL_FILES, path)
    _fetch(VAD_REPO, VAD_FILES, vad_dir())
    return path


class Transcriber:
    def __init__(self, path: Path | None = None):
        self.path = path or model_dir()
        self._model = None
        self._lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self._model is not None

    def load(self) -> None:
        with self._lock:
            if self._model is not None:
                return
            import onnx_asr

            download_model(self.path)
            providers = ["CPUExecutionProvider"]
            asr = onnx_asr.load_model(MODEL_NAME, str(self.path), quantization=MODEL_QUANTIZATION, providers=providers)
            vad = onnx_asr.load_vad(VAD_NAME, str(vad_dir()), providers=providers)
            self._model = asr.with_vad(vad, max_speech_duration_s=MAX_SEGMENT_SECONDS)

    def transcribe(self, audio: np.ndarray) -> str:
        if len(audio) < MIN_SECONDS * SAMPLE_RATE:
            return ""
        self.load()
        with self._lock:
            segments = self._model.recognize(audio.astype(np.float32), sample_rate=SAMPLE_RATE)
            return " ".join(seg.text.strip() for seg in segments if seg.text.strip())

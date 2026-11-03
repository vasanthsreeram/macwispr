"""On-device speech recognition: Parakeet TDT 0.6B v3 (int8 ONNX) on ONNX Runtime CPU."""
from __future__ import annotations

import logging
import threading
from pathlib import Path

import numpy as np

from .config import MODEL_FILES, MODEL_NAME, MODEL_QUANTIZATION, MODEL_REPO, SAMPLE_RATE, model_dir, model_installed

log = logging.getLogger(__name__)

CHUNK_SECONDS = 60  # Parakeet is trained on short utterances; split long dictations
MIN_SECONDS = 0.3


def download_model(path: Path | None = None) -> Path:
    """Fetch the model files from Hugging Face once; later runs are offline."""
    from huggingface_hub import hf_hub_download

    path = path or model_dir()
    if model_installed(path):
        return path
    path.mkdir(parents=True, exist_ok=True)
    for name in MODEL_FILES:
        log.info("downloading %s/%s", MODEL_REPO, name)
        hf_hub_download(MODEL_REPO, name, local_dir=str(path))
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
            self._model = onnx_asr.load_model(MODEL_NAME, str(self.path), quantization=MODEL_QUANTIZATION,
                                              providers=["CPUExecutionProvider"])

    def transcribe(self, audio: np.ndarray) -> str:
        if len(audio) < MIN_SECONDS * SAMPLE_RATE:
            return ""
        self.load()
        step = CHUNK_SECONDS * SAMPLE_RATE
        parts = []
        with self._lock:
            for start in range(0, len(audio), step):
                chunk = audio[start:start + step]
                if len(chunk) >= MIN_SECONDS * SAMPLE_RATE:
                    parts.append(self._model.recognize(chunk.astype(np.float32), sample_rate=SAMPLE_RATE).strip())
        return " ".join(p for p in parts if p)

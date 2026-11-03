"""Settings and data locations for MacWispr for Windows."""
from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, fields
from pathlib import Path

APP_NAME = "MacWispr"
VERSION = "0.1.0"

# Parakeet TDT 0.6B v3 (the same base model Parakeet Redux is distilled from),
# exported to ONNX and int8-quantized so it runs on any x64 CPU via ONNX Runtime.
MODEL_NAME = "nemo-parakeet-tdt-0.6b-v3"
MODEL_REPO = "istupakov/parakeet-tdt-0.6b-v3-onnx"
MODEL_QUANTIZATION = "int8"
MODEL_FILES = ("encoder-model.int8.onnx", "decoder_joint-model.int8.onnx", "vocab.txt", "config.json")
MODEL_DOWNLOAD_LABEL = "about 670 MB"

# Silero voice-activity detector: Parakeet int8 returns an empty transcript for some
# recordings that start with digital silence, so only the detected speech is decoded.
VAD_NAME = "silero"
VAD_REPO = "istupakov/silero-vad-onnx"
VAD_FILES = ("silero_vad.onnx", "config.json")

SAMPLE_RATE = 16_000


def data_dir() -> Path:
    base = os.environ.get("MACWISPR_DATA_DIR") or os.environ.get("LOCALAPPDATA") or str(Path.home() / ".local" / "share")
    path = Path(base) / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def model_dir() -> Path:
    return data_dir() / "models" / "parakeet-tdt-0.6b-v3-int8"


def vad_dir() -> Path:
    return data_dir() / "models" / "silero-vad"


def _complete(path: Path, names) -> bool:
    return all((path / name).is_file() and (path / name).stat().st_size > 0 for name in names)


def model_installed(path: Path | None = None) -> bool:
    return _complete(path or model_dir(), MODEL_FILES) and _complete(vad_dir(), VAD_FILES)


@dataclass
class Settings:
    mode: str = "hold"  # "hold": hold Alt+Space to talk. "toggle": tap to start, tap to stop.
    auto_paste: bool = True  # Paste into the focused app. Off: copy to clipboard only.
    restore_clipboard: bool = True
    sounds: bool = True
    save_history: bool = True

    @classmethod
    def load(cls, path: Path | None = None) -> "Settings":
        path = path or data_dir() / "settings.json"
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return cls()
        known = {f.name for f in fields(cls)}
        settings = cls(**{k: v for k, v in raw.items() if k in known})
        if settings.mode not in ("hold", "toggle"):
            settings.mode = "hold"
        return settings

    def save(self, path: Path | None = None) -> None:
        path = path or data_dir() / "settings.json"
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(asdict(self), indent=2), encoding="utf-8")
        tmp.replace(path)

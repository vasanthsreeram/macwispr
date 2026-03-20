# OpenWhispr

On-device voice dictation for macOS, powered by [Qwen3-ASR-0.6B](https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit) via Apple Metal (MLX). A free, open-source alternative to Wispr Flow that runs entirely on your Mac with no cloud dependency.

## Features

- **Hold-to-dictate**: Hold `Option+Space` to record, release to transcribe and auto-insert text
- **System-wide text insertion**: Transcribed text is pasted into whatever app is focused (Slack, VS Code, email, terminal, etc.)
- **On-device inference**: Qwen3-ASR 0.6B runs locally via MLX on Apple Silicon GPU. No internet required after model download
- **Menu bar app**: Lives in your menu bar, always ready. Click to record or use the global hotkey
- **Filler word removal**: Automatically strips "uh", "um", "like", "you know", etc.
- **Auto-capitalize**: First letter of transcription is capitalized
- **52-language support**: Auto-detects language or pin one for faster results
- **Transcription history**: Browse and copy past transcriptions
- **Multiple insertion modes**: Clipboard paste, simulated typing, or both
- **Settings UI**: Configure language, insertion mode, post-processing, and view permissions status

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon (M1/M2/M3/M4)
- ~300 MB disk space for the model (downloaded on first use)
- Accessibility permission (for global hotkey and text insertion)
- Microphone permission

## Installation

### Build from source

```bash
git clone https://github.com/lintware/openwhispr.git
cd openwhispr
swift build -c release
```

> **Note**: On first `swift package resolve`, SPM downloads the `SpeechCore.xcframework` binary (~480 KB). If this hangs, you can manually download it:
> ```bash
> curl -L -o /tmp/SpeechCore.xcframework.zip \
>   "https://github.com/soniqo/speech-core/releases/download/v0.0.3/SpeechCore.xcframework.zip"
> ```
> Then extract and place it in `.build/checkouts/speech-swift/SpeechCore.xcframework/`.

### Run

```bash
.build/release/OpenWhispr
```

The app will appear in your menu bar with a waveform icon.

## Usage

1. **Load the model**: Click the menu bar icon and press "Load Model". This downloads ~300 MB on first run (cached in `~/Library/Caches/qwen3-speech/`)
2. **Grant permissions**: The app will prompt for Accessibility and Microphone access
3. **Dictate**: Hold `Option+Space`, speak, release. Text appears in the active text field
4. **Or click**: Use the record button in the menu bar or main window

## Architecture

```
Sources/
  OpenWhisprApp.swift       SwiftUI app entry point (menu bar + window)
  AppDelegate.swift         Accessibility permission request
  AppState.swift            Central state management
  TranscriptionEngine.swift Qwen3ASR model loading and inference
  AudioRecorder.swift       AVAudioEngine mic capture + resampling to 16kHz
  HotkeyManager.swift       Global Option+Space hotkey via NSEvent monitors
  TextInserter.swift        CGEvent-based text insertion (clipboard paste or typing)
  MenuBarView.swift         Menu bar dropdown UI
  MainWindowView.swift      Main window with history and controls
  SettingsView.swift        Settings tabs (general, transcription, hotkeys, about)
```

## Dependencies

- [soniqo/speech-swift](https://github.com/soniqo/speech-swift) - Qwen3-ASR, SpeechVAD, AudioCommon (MLX-accelerated on-device speech toolkit)

## Performance

- **Inference speed**: ~0.06x real-time factor (10s of audio processed in ~0.6s on Apple Silicon)
- **Model size**: ~300 MB (4-bit quantized)
- **Memory**: ~400 MB RAM during inference

## License

MIT

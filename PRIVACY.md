# MacWispr Privacy

MacWispr is designed for **on-device privacy**. Dictation can run fully locally (Qwen3-ASR on Apple Silicon). Cloud speech-to-text is optional and **bring-your-own-key (BYOK)** — API keys stay in the macOS Keychain and are sent only to the provider you chose (OpenAI or ElevenLabs), never to MacWispr servers (there are none for STT).

## Anonymous usage telemetry (opt-in)

MacWispr may offer an optional **“Share anonymous usage data”** setting (default **off**). When enabled, the app can send a small set of **anonymous, content-free** reliability signals to a self-hosted or project analytics backend (PostHog HTTPS `/batch`). This exists so we can measure real-world issues — especially a silently dead ⌥Space hotkey after updates — without seeing what you said.

Telemetry is gated by a single kill-switch in the app. If the toggle is off, **no telemetry events are sent**.

### What we collect (only when you opt in)

| Category | Details |
|----------|---------|
| Device / build | App version, macOS version, CPU architecture (`arm64` / `x86_64`) |
| Latency | Transcription latency **bucketed** only (`<1s`, `1-3s`, `3-10s`, `>10s`) |
| Dictation counts | Completed / failed event counts |
| Hotkey health | Booleans: tap installed, Carbon installed, Accessibility trusted, armed |
| Coarse config | Provider (`local` / `cloud`), model size token, mode (`hold` / `toggle`), insertion mode |
| Failure category | Enum only: `no_audio`, `mic_denied`, `paste_no_ax`, `stt_error` |
| Install ID | A random UUID generated once and stored locally (not a hardware serial) |

### What we never collect

- Transcription **text** — ever
- **Audio** samples or recordings
- **Custom vocabulary** words
- **Clipboard** contents
- API keys / secrets
- Hardware serials, MAC address, username, email, IP-derived identity, precise location
- Raw timestamps or durations that could fingerprint (durations are **bucketed**)

There is **no autocapture**, **no session recording**, and **no SDK product analytics** beyond the explicit whitelisted events the app constructs.

### Events

| Event | Purpose |
|-------|---------|
| `hotkey_health` | Measure armed vs. dead global hotkey (priority reliability signal) |
| `dictation_completed` | Counts + bucketed latency + coarse config + insertion outcome |
| `dictation_failed` | Failure category enum only |
| `opt_in` / `opt_out` | Preference changes (final `opt_out` is sent before muting) |

### Turning it off

**Settings → General → Privacy → Share anonymous usage data** (off). Turning the toggle off stops all further sends immediately and attempts one final `opt_out` event.

## Local data on your Mac

- Transcription history and usage stats live under Application Support (local only).
- Custom vocabulary is stored in `UserDefaults` on this Mac.
- API keys use the Keychain.

## Questions

Open an issue at [github.com/vasanthsreeram/macwispr](https://github.com/vasanthsreeram/macwispr) or review the telemetry implementation in `Sources/Telemetry.swift`.

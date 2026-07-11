# Privacy

MacWispr is built to keep your voice and text on your Mac whenever possible.

By default, **local** transcription (Qwen3-ASR via MLX) runs entirely on-device. Optional cloud STT (OpenAI / ElevenLabs) only runs if you choose a cloud provider and supply your own API key (BYOK). Keys stay in the macOS Keychain.

## Optional product telemetry

MacWispr can send **anonymous, content-free** product telemetry so we can measure real-world reliability — for example whether the global hotkey is actually armed after updates, or how often dictation fails by category.

### Opt-in (off by default)

Telemetry is **off until you turn it on**. Nothing leaves your Mac for product analytics unless you enable it.

| | |
|---|---|
| **Default** | Off |
| **Enable** | Settings → Privacy → **Share anonymous usage data** |
| **Disable** | Settings → Privacy → turn the same toggle **off** |

Turning it off stops all further telemetry sends immediately. Already-sent events are not pulled back from the server (see [Retention](#retention)).

### Guiding principle

Telemetry is **opt-in**, **anonymous**, and **content-free**. If in doubt, it does not leave the device.

We send only explicit, whitelisted events. Autocapture, session recording, and similar PostHog features are not used.

---

## What we collect

When telemetry is enabled, MacWispr may send:

| Category | What |
|----------|------|
| **App / device** | App version, macOS version, CPU architecture (`arm64` / `x86_64`) |
| **Latency** | Transcription latency in **buckets** only (e.g. `<1s`, `1–3s`, `3–10s`, `>10s`) — not raw millisecond timings that could fingerprint |
| **Dictation outcomes** | How many dictations **completed** or **failed** |
| **Hotkey / Accessibility health** | Boolean flags only: tap installed, Carbon hotkey installed, Accessibility trusted, hotkey armed |
| **Coarse config** | Provider (`local` / `cloud`), model size class, dictation mode (`hold` / `toggle`), insertion mode |
| **Failure category** | Enum only: `no_audio`, `mic_denied`, `paste_no_ax`, `stt_error` (and similar non-content labels) |
| **Install ID** | A **random UUID** generated once on first enable and stored locally — never a hardware serial, MAC address, or other device identifier |

These fields exist so we can answer questions like “how often is ⌥Space silently dead after an update?” without ever seeing what you said.

---

## What we never collect

The following **never** leave your device as telemetry (and local history/settings stay on your Mac unless you explicitly use a cloud STT/polish provider you configured):

- Transcription **text** — ever  
- **Audio** samples or recordings  
- **Custom vocabulary** words  
- **Clipboard** contents  
- API keys / secrets  
- Hardware serials, MAC address, username, email  
- IP-derived identity or other attempts to re-identify you  
- Precise location  
- Raw timestamps or durations that could fingerprint (we bucket)

---

## Where data goes

| | |
|---|---|
| **Service** | [PostHog](https://posthog.com) |
| **Region** | United States (PostHog US cloud) |
| **Transport** | HTTPS only (explicit `/capture`-style events; no browser session, no screen recording) |
| **Who can see it** | Maintainers of this project, for product reliability metrics |

Telemetry is fail-silent: network or client errors never block dictation. Failed batches are dropped, not retried in a way that interferes with the app.

### Retention

Events are retained on PostHog under the project’s configured data retention (typically on the order of months for product analytics; exact window may change with plan and settings). When you disable telemetry, MacWispr stops sending new events; historical aggregates already stored on PostHog are not automatically deleted.

If you need data removed for a specific install ID, open a GitHub issue or contact the maintainers and include that anonymous ID (shown in Settings when telemetry is enabled, when available).

---

## On-device vs cloud transcription (separate from telemetry)

| Mode | Audio / text leave your Mac? |
|------|------------------------------|
| **Local** (default) | No — ASR runs on Apple Silicon via MLX |
| **Cloud BYOK** (OpenAI / ElevenLabs) | Yes — audio (and polish text, if enabled) go to the provider you chose, under **your** API key and their privacy policy |
| **Transcript history / dashboard** | Stored locally under Application Support on your Mac |

Turning telemetry on does **not** change where transcription runs. Local stays local.

---

## Summary

1. **Local by default** for speech-to-text.  
2. **Telemetry is opt-in** and off until you enable it in Settings.  
3. We only send **anonymous, non-content** reliability signals.  
4. We **never** send what you said, your audio, keys, or personal identifiers.

See the epic and related issues on GitHub for implementation details. This document is the public contract: if something is not listed under [What we collect](#what-we-collect), it is not telemetry.

### Implementation note (maintainers)

Events are sent only from builds that embed a real PostHog **project** write key in `Sources/Telemetry.swift`. Placeholder keys send nothing. Agent-oriented release/privacy notes: [AGENTS.md](AGENTS.md).

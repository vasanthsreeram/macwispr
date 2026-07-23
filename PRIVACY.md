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
| **Polish (content-free)** | Polish on/off class (`off` / `local` / `openai`), polish model class, polish latency **bucket**, raw/polished **word-count buckets**, `text_changed_by_polish` bool, coarse shape flags (`has_newlines`, `looks_like_list`) — **never** raw or polished transcript text |
| **UI surface (coarse)** | Enum-only opens: `dashboard` / `settings` / `history` / `onboarding` / `about` — no paths, no free text |
| **Failure category** | Enum only: `no_audio`, `mic_denied`, `paste_no_ax`, `stt_error` (and similar non-content labels) |
| **Install ID** | A **random UUID** generated once on first enable and stored locally — never a hardware serial, MAC address, or other device identifier |

These fields exist so we can answer questions like “how often is ⌥Space silently dead after an update?” without ever seeing what you said.

---

## What we never collect

The following **never** leave your device as telemetry (and local history/settings stay on your Mac unless you explicitly use a cloud STT/polish provider you configured):

- Transcription **text** — ever (including pre-polish / post-polish strings)  
- **Audio** samples or recordings  
- **Keystrokes** or global input logging  
- **Custom vocabulary** words  
- **Clipboard** contents  
- API keys / secrets  
- Hardware serials, MAC address, username, email  
- IP-derived identity or other attempts to re-identify you  
- Precise location  
- Raw timestamps or durations that could fingerprint (we bucket)

### Optional local developer capture (not telemetry)

Settings → General → **Developer → Save audio + text locally** (off by default) writes **WAV audio** and **text stages** (raw STT, light post-process, polished) to  
`~/Library/Application Support/MacWispr/dev-captures/` on this Mac only.

- Used for debugging dictation / polish quality.
- **Never uploaded** by MacWispr telemetry (still subject to whatever *you* do with the folder).
- Caps at the last 100 captures; you can clear from Settings.
- Can also be forced for a process with env `MACWISPR_DEV_CAPTURE=1`.

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

## Optional public leaderboard (separate opt-in)

MacWispr can show **opt-in** speakers on a public website leaderboard
([fuckwisprflow.com/leaderboard](https://fuckwisprflow.com/leaderboard)).
This is **not** product telemetry and is **off by default**.

| | |
|---|---|
| **Default** | Off |
| **Enable** | Settings → Configuration → Privacy → **Appear on public leaderboard** |
| **Disable** | Turn the same toggle **off** (removes your row from the board) |

### What the board stores

When you opt in, the app posts **aggregate counts only**:

| Field | Notes |
|-------|--------|
| Dictation count | How many completed dictations (on-device history) |
| Word count | Total words dictated (counts only — not the words) |
| Time saved | Derived minutes vs your typing WPM baseline |
| Streak | Consecutive active days |
| Display name | Default: server-derived **`Anonymous <Animal> · <tag>`**. Optional: a **public name you choose** (2–24 characters) so you can compete by name |

### Identity modes

| Mode | What the board shows | Who can link it to you |
|------|----------------------|------------------------|
| **Anonymous (default)** | Random animal label | Nobody — maintainers only see a hash of a device-only secret |
| **Public name (optional)** | The name you type | Anyone who sees the board (you chose that label) |

- The app generates a **random secret token** stored only in your Mac’s Keychain.
- The server stores **`SHA-256(token)`**, never the token itself and never the telemetry install UUID.
- Choosing a public name is **extra opt-in on top of board opt-in** — leave the field blank to stay anonymous.
- Still never: transcript text, audio, clipboard, vocabulary, API keys, hardware IDs, email, GitHub.

Turning on reliability telemetry does **not** put you on the board. Leaving the board (toggle off) deletes your non-seed row and destroys the local token so a future opt-in starts a fresh identity.

The board may include a few **seeded demo speakers** so the page is not empty; they are labeled as seed speakers and are not real people.

### Where leaderboard data goes

| | |
|---|---|
| **Service** | Cloudflare Worker + D1 (`macwispr-leaderboard`) |
| **Transport** | HTTPS only |
| **Public read** | Ranked aggregates + anonymous display names |

---

## Summary

1. **Local by default** for speech-to-text.  
2. **Telemetry is opt-in** and off until you enable it in Settings.  
3. We only send **anonymous, non-content** reliability signals.  
4. **Leaderboard is a separate opt-in** with anonymous animal names only.  
5. We **never** send what you said, your audio, keys, or personal identifiers.

See the epic and related issues on GitHub for implementation details. This document is the public contract: if something is not listed under [What we collect](#what-we-collect), it is not telemetry (and leaderboard fields are listed under [Optional public leaderboard](#optional-public-leaderboard-separate-opt-in)).

### Implementation note (maintainers)

Events are sent only from builds that embed a real PostHog **project** write key in `Sources/Telemetry.swift`. Placeholder keys send nothing. Agent-oriented release/privacy notes: [AGENTS.md](AGENTS.md).

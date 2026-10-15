# Meetings and agent access

Two features, one data folder (`~/Library/Application Support/MacWispr`, override with `MACWISPR_DATA_DIR`):

1. **Meeting recording.** Records the microphone (the room) and audio from other apps (calls), transcribes on-device after you stop, and saves audio + transcript.
2. **Agent access.** The `macwispr` command and its MCP server give AI agents read-only access to dictation history and meetings.

## Meeting recording

| Piece | File |
|-------|------|
| Capture (mic engine, Core Audio process tap, 16 kHz PCM sinks) | `Sources/MeetingCapture.swift` |
| Start / stop, processing queue, audio export, CLI install | `Sources/MeetingController.swift` |
| Meetings pane + agent panel | `Sources/MeetingsView.swift` |
| Headless check: `MacWispr --record-meeting <seconds>` | `Sources/HeadlessMeeting.swift` |
| Layout, metadata, formatter, read API | `Sources/MacWisprCore/AgentData.swift` |
| Speech regions + mic-echo removal | `Sources/MacWisprCore/MeetingSegmenter.swift` |

Flow:

1. **Record.** Each source writes raw 16 kHz mono PCM16 (`mic.pcm`, `system.pcm`) straight to the meeting folder, so memory stays flat for long meetings and a crash keeps the audio. Gaps of more than 0.5 s are padded with silence so both tracks share one timeline.
   - The mic uses its own `AVAudioEngine`, separate from dictation, so ⌥Space still works during a meeting.
   - Other apps' audio uses `CATapDescription` + `AudioHardwareCreateProcessTap` (macOS 14.2+) in a private aggregate device. MacWispr's own process is excluded so chimes are not recorded. Permission: `NSAudioCaptureUsageDescription` (Screen & System Audio Recording). When permission is missing, the tap delivers silence. MacWispr detects an all-zero track and adds a warning to `meeting.json`.
2. **Transcribe** (after stop). `MeetingSegmenter` finds speech regions in each track (noise floor + 9 dB, 0.5 s padding, cut at quiet points below 24 s), and each region goes through `TranscriptionEngine.transcribe`. That gives real timestamps and skips silence. `AppState.beginMeetingTranscription()` loads the model and holds off idle unload.
3. **Merge.** `MeetingMerge` labels mic segments "Me" and system segments "Others". It drops mic segments whose words mostly repeat overlapping system audio, which happens when speakers leak into the mic without headphones.
4. **Save.** Writes `transcript.json` + `transcript.md`, encodes `mic.m4a`, `system.m4a`, and a mixed `audio.m4a` (AAC, 32 kbps), then deletes the PCM.

If the app quits mid-meeting, the meeting is marked `interrupted` on the next launch and **Transcribe Recording** processes the PCM that was saved.

There is no speaker diarisation beyond Me/Others, and no live transcript during a meeting.

## Agent access

`Sources/MacWisprCLI/` builds the `MacWisprCLI` product. `scripts/build-app.sh` copies it to `MacWispr.app/Contents/Helpers/macwispr`, and `sign-and-notarize.sh` signs everything in `Helpers`. (The target can't be named `macwispr`: on a case-insensitive disk it collides with `MacWispr` in `.build`.)

```
macwispr history [--limit N] [--since 7d|24h|2026-10-01] [--search TEXT] [--json]
macwispr meetings [--limit N] [--json]
macwispr meeting <id|latest> [--json] [--files]
macwispr search <TEXT> [--limit N] [--json]
macwispr paths
macwispr mcp
```

MCP (JSON-RPC over stdio, newline-delimited) tools: `list_dictations`, `list_meetings`, `get_meeting`, `search_transcripts`. All are read-only.

```json
{ "mcpServers": { "macwispr": { "command": "/Applications/MacWispr.app/Contents/Helpers/macwispr", "args": ["mcp"] } } }
```

Claude Code: `claude mcp add macwispr -- /Applications/MacWispr.app/Contents/Helpers/macwispr mcp`

Meetings → **Agents** shows this config, can link the command into `~/.local/bin`, and the app writes `AGENTS.md` into the data folder for agents that browse files.

## Testing

- Unit: `swift test` (`MeetingTests.swift`: segmenter, echo merge, store, `--since`).
- End to end, no UI: `MACWISPR_DATA_DIR=/tmp/mw MacWispr --record-meeting 12` while playing speech (`afplay`). Prints `meeting.json` + transcript and exits 0 on success.
- UI: `MACWISPR_DATA_DIR=/tmp/mw MacWispr --render-ui /tmp/ui` renders `ui-meetings.png`. Set `MACWISPR_RENDER_AGENT_PANEL=1` to render the agent panel.

import SwiftUI
import AppKit
import AVFoundation

import MacWisprCore

/// Meetings pane: record button, past meetings, transcript + audio, agent access.
struct MeetingsView: View {
    @Environment(AppState.self) var appState
    @State private var selectedID: String?

    private var controller: MeetingController { appState.meetings }

    var body: some View {
        VStack(spacing: 0) {
            recordBar
            Divider()
            HStack(spacing: 0) {
                list
                    .frame(width: 220)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            controller.reload()
            if selectedID == nil, ProcessInfo.processInfo.environment["MACWISPR_RENDER_AGENT_PANEL"] != "1" {
                selectedID = controller.meetings.first?.id
            }
        }
        .onChange(of: controller.meetings.first?.id) { _, newest in
            if controller.isRecording || selectedID == nil { selectedID = newest }
        }
    }

    // MARK: Record bar

    private var recordBar: some View {
        @Bindable var c = controller
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.m) {
                Button {
                    controller.toggle()
                } label: {
                    Label(
                        controller.isRecording ? "Stop Recording" : "Record Meeting",
                        systemImage: controller.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                    .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isRecording ? .red : .accentColor)
                .controlSize(.large)

                if controller.isRecording {
                    Text(controller.elapsedLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                    LevelMeter(label: "Mic", level: controller.micLevel, active: c.recordMicrophone)
                    LevelMeter(label: "Apps", level: controller.systemLevel, active: c.recordSystemAudio)
                } else {
                    Toggle("Microphone", isOn: $c.recordMicrophone)
                        .fixedSize()
                        .help("The room: you and anyone near this Mac.")
                    Toggle("Other apps", isOn: $c.recordSystemAudio)
                        .fixedSize()
                        .disabled(!MeetingController.systemAudioSupported)
                        .help(MeetingController.systemAudioSupported
                              ? "Zoom, Meet, Teams, browsers — anything playing on this Mac."
                              : "Needs macOS 14.2 or later.")
                }
                Spacer()
                if case .processing(let status) = controller.phase {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    selectedID = nil
                } label: {
                    Label("Agents", systemImage: "sparkles")
                }
                .fixedSize()
                .help("Let Claude Code, Cursor, Grok and other agents read your meetings and dictation history")
            }
            if let err = controller.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.m)
    }

    // MARK: List

    private var list: some View {
        Group {
            if controller.meetings.isEmpty {
                ContentUnavailableView(
                    "No meetings yet",
                    systemImage: "person.2.wave.2",
                    description: Text("Record a call or an in-person meeting. Audio and transcript stay on this Mac.")
                )
            } else {
                List(selection: $selectedID) {
                    ForEach(controller.meetings, id: \.id) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(UsageClock.format(seconds: m.durationSeconds))
                                    .monospacedDigit()
                                statusBadge(m.status)
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(m.id)
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([controller.folderURL(id: m.id)])
                            }
                            if controller.canReprocess(m) {
                                Button("Transcribe Again") { controller.reprocess(id: m.id) }
                            }
                            Divider()
                            Button("Move to Trash", role: .destructive) {
                                if selectedID == m.id { selectedID = nil }
                                controller.delete(id: m.id)
                            }
                            .disabled(m.status == .recording || m.status == .processing)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ s: MeetingStatus) -> some View {
        switch s {
        case .recording: Text("● Recording").foregroundStyle(.red)
        case .processing: Text("Transcribing…").foregroundStyle(.orange)
        case .done: EmptyView()
        case .failed: Text("Failed").foregroundStyle(.orange)
        case .interrupted: Text("Interrupted").foregroundStyle(.orange)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, let meta = controller.meetings.first(where: { $0.id == id }) {
            MeetingDetail(meta: meta)
                .id(meta.id + meta.status.rawValue)
        } else {
            AgentAccessPanel()
        }
    }
}

private struct LevelMeter: View {
    let label: String
    let level: Float
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(active ? .secondary : .tertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(min(1, sqrt(Double(level)) * 2.5)))
                }
            }
            .frame(width: 50, height: 5)
            .opacity(active ? 1 : 0.3)
        }
    }
}

private struct MeetingDetail: View {
    @Environment(AppState.self) var appState
    let meta: MeetingMetadata
    @State private var title = ""
    @State private var isRenaming = false
    @State private var transcript = ""
    @State private var audio = MeetingAudioPlayer()

    private var controller: MeetingController { appState.meetings }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack {
                if isRenaming {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            controller.rename(id: meta.id, to: title)
                            isRenaming = false
                        }
                        .onExitCommand { title = meta.title; isRenaming = false }
                } else {
                    Text(meta.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        isRenaming = true
                    } label: { Image(systemName: "pencil") }
                        .help("Rename")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy transcript")
                    .disabled(transcript.isEmpty)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([controller.folderURL(id: meta.id)])
                } label: { Image(systemName: "folder") }
                    .help("Show in Finder")
            }
            Text("\(meta.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(UsageClock.format(seconds: meta.durationSeconds)) · \(meta.wordCount) words")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let warnings = meta.warnings, !warnings.isEmpty {
                ForEach(warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let err = meta.error {
                Label(err, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if meta.status == .interrupted || meta.status == .failed, controller.canReprocess(meta) {
                Button("Transcribe Recording") { controller.reprocess(id: meta.id) }
            }

            if audio.isLoaded {
                HStack(spacing: DS.Space.s) {
                    Button {
                        audio.toggle()
                    } label: {
                        Label(audio.isPlaying ? "Pause" : "Play Recording",
                              systemImage: audio.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Text("\(UsageClock.format(seconds: audio.position)) / \(UsageClock.format(seconds: audio.duration))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            ScrollView {
                Text(transcriptBody)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Space.l)
        .onAppear(perform: load)
        .onDisappear { audio.stop() }
    }

    private var transcriptBody: String {
        switch meta.status {
        case .recording: return "Recording… the transcript appears after you stop."
        case .processing: return "Transcribing on this Mac…"
        default: return transcript.isEmpty ? "No transcript." : transcript
        }
    }

    private func load() {
        title = meta.title
        let store = AgentDataStore(paths: controller.paths)
        if let t = store.transcript(id: meta.id) {
            let both = meta.recordMicrophone && meta.recordSystemAudio
            transcript = t.segments.map { seg in
                let label = MeetingTranscriptFormatter.speakerLabel(seg.source, bothSources: both).map { "\($0): " } ?? ""
                return "[\(MeetingTranscriptFormatter.timestamp(seg.start))] \(label)\(seg.text)"
            }.joined(separator: "\n\n")
        }
        if let url = controller.file(MeetingFiles.mixedAudio, id: meta.id) {
            audio.load(url)
        }
    }
}

/// Play / pause for a meeting's mixed audio, with a position readout.
@MainActor
@Observable
final class MeetingAudioPlayer {
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    var isLoaded: Bool { player != nil }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    func load(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.play()
            startTimer()
        }
        isPlaying = player.isPlaying
    }

    func stop() {
        player?.stop()
        stopTimer()
        isPlaying = false
    }

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.position = p.currentTime
                if !p.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

/// How AI agents read meetings and dictation history.
struct AgentAccessPanel: View {
    @Environment(AppState.self) var appState
    @State private var installMessage: String?

    private var controller: MeetingController { appState.meetings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Label("AI agent access", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                Text("Claude Code, Cursor, Grok, Codex, and other agents can read your dictation history and meetings (transcripts and audio) through the bundled `macwispr` tool. Access is read-only and local; nothing leaves this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("MCP server config").font(.headline)
                codeBox(controller.mcpConfigJSON)

                Text("Command line").font(.headline)
                codeBox("macwispr meetings\nmacwispr meeting latest\nmacwispr history --since 24h\nmacwispr search \"budget\"")
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Button(controller.isCLIInstalled ? "Reinstall Command" : "Install Command") {
                        do {
                            try controller.installCLI()
                            installMessage = "Linked \(MeetingController.cliLinkURL.path)"
                        } catch {
                            installMessage = error.localizedDescription
                        }
                    }
                    .disabled(controller.cliURL == nil)
                    .help("Links `macwispr` into ~/.local/bin")
                    Button("Open Data Folder") {
                        NSWorkspace.shared.open(controller.paths.root)
                    }
                }
                if let installMessage {
                    Text(installMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("Files: \(controller.paths.root.path) — see AGENTS.md there.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func codeBox(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy")
        }
        .padding(DS.Space.s)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: DS.Radius.s))
    }
}

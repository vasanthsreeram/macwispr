import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSidebar: SidebarItem = .dashboard
    @State private var editingTranscription: String = ""
    @State private var isEditingTranscription = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detailView
        }
        .navigationTitle("MacWispr")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if appState.isRecording {
                        Task { await appState.stopRecordingAndTranscribe() }
                    } else if appState.isReadyToDictate {
                        appState.startRecording()
                    }
                } label: {
                    Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(appState.isRecording ? .red : .accentColor)
                }
                .disabled((!appState.isReadyToDictate && !appState.isRecording)
                          || appState.dictationPhase == .transcribing)
                .help(appState.isRecording ? "Stop recording" : "Start recording")
            }
        }
        .sheet(isPresented: $appState.showTelemetryDisclosure) {
            TelemetryDisclosureSheet(isRevisit: Telemetry.shared.hasSeenDisclosure)
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSidebar) {
            Section("MacWispr") {
                Label("Dashboard", systemImage: "chart.bar.fill")
                    .tag(SidebarItem.dashboard)
                Label("Dictate", systemImage: "mic.fill")
                    .tag(SidebarItem.dictate)
                Label("History", systemImage: "clock")
                    .tag(SidebarItem.history)
                Label("Settings", systemImage: "gear")
                    .tag(SidebarItem.settings)
            }
            // History lives only in the detail pane (GitHub #14 — avoid duplicating
            // the same list in the sidebar "menu" and the main content area).
        }
        .listStyle(.sidebar)
    }

    private var detailView: some View {
        Group {
            switch selectedSidebar {
            case .dashboard:
                DashboardView()
            case .dictate:
                dictateDetail
            case .history:
                historyDetail
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .macWisprShowSettings)) { _ in
            selectedSidebar = .settings
        }
    }

    private var dictateDetail: some View {
        VStack(spacing: 24) {
            if !appState.isReadyToDictate {
                modelLoadingView
            } else {
                activeView
            }
        }
        .padding()
    }

    private var historyDetail: some View {
        Group {
            if appState.transcriptionHistory.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "text.bubble",
                    description: Text("Your dictations will appear here and feed the weekly dashboard.")
                )
            } else {
                List {
                    ForEach(appState.transcriptionHistory) { entry in
                        EditableHistoryRow(entry: entry)
                    }
                }
            }
        }
    }

    private var modelLoadingView: some View {
        VStack(spacing: 16) {
            if appState.transcriptionProvider == .local && appState.isModelLoading {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Loading \(appState.asrModelSize.displayName)")
                    .font(.title3)

                ProgressView(value: appState.modelLoadProgress) {
                    Text(appState.modelLoadStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 300)
            } else {
                Image(systemName: appState.transcriptionProvider == .local ? "arrow.down.circle" : "key.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text(appState.readinessLabel)
                    .font(.title3)
                    .multilineTextAlignment(.center)

                Text(appState.transcriptionProvider.help)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                if appState.transcriptionProvider != .local {
                    Button("Open Settings") {
                        NotificationCenter.default.post(name: .macWisprShowSettings, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var activeView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: dictateSymbol)
                    .font(.system(size: 48))
                    .foregroundStyle(dictateColor)
                    .symbolEffect(
                        .variableColor.iterative,
                        isActive: appState.dictationPhase == .listening
                            || appState.dictationPhase == .transcribing
                    )

                Text(dictateTitle)
                    .font(.title3)
                    .foregroundStyle(appState.dictationPhase == .ready ? .secondary : .primary)

                if appState.dictationPhase == .listening {
                    Text(appState.recordingElapsedLabel)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(appState.dictationMode.help)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            // Mode switch lives in Settings; show current mode only.
            Text("Mode: \(appState.dictationMode.rawValue) · change in Settings → Hotkeys")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            switch appState.dictationMode {
            case .hold:
                HoldToSpeakButton()
                    .frame(maxWidth: 360)
            case .toggle:
                Button {
                    appState.toggleRecording()
                } label: {
                    Label(
                        appState.isRecording ? "Stop & Transcribe" : "Start Listening",
                        systemImage: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .frame(maxWidth: 360)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(appState.isRecording ? .red : .accentColor)
            }

            if let failure = appState.lastFailureMessage {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 400)
            }

            if !appState.currentTranscription.isEmpty || isEditingTranscription {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Transcription")
                                .font(.headline)
                            Spacer()
                            if isEditingTranscription {
                                Button("Save") {
                                    appState.commitCurrentTranscriptionEdit(editingTranscription)
                                    isEditingTranscription = false
                                }
                                .keyboardShortcut(.return, modifiers: .command)
                                Button("Cancel") {
                                    editingTranscription = appState.currentTranscription
                                    isEditingTranscription = false
                                }
                                .keyboardShortcut(.escape, modifiers: [])
                            } else {
                                Button("Edit") {
                                    editingTranscription = appState.currentTranscription
                                    isEditingTranscription = true
                                }
                            }
                        }

                        if isEditingTranscription {
                            TextEditor(text: $editingTranscription)
                                .font(.body)
                                .frame(minHeight: 100, maxHeight: 200)
                                .scrollContentBackground(.hidden)
                            Text("Save to apply edits. Corrected words are added to your custom vocabulary.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                Text(appState.currentTranscription)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                }
                .onChange(of: appState.currentTranscription) { _, newValue in
                    // Fresh dictation replaces any in-progress edit.
                    if !isEditingTranscription {
                        editingTranscription = newValue
                    }
                }
            }

            GroupBox("Quick Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Insert Mode", selection: Binding(
                        get: { appState.insertionMode },
                        set: { appState.setInsertionMode($0) }
                    )) {
                        ForEach(InsertionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Remove filler words", isOn: $appState.removeFillerWords)
                    Toggle("Auto-capitalize", isOn: $appState.autoCapitalize)
                }
                .padding(4)
            }
        }
    }

    private var dictateTitle: String {
        switch appState.dictationPhase {
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .success: return appState.phaseDetail.isEmpty ? "Done" : appState.phaseDetail
        case .failed: return "Couldn't finish"
        case .setup: return appState.readinessLabel
        case .ready: return "Ready to dictate"
        }
    }

    private var dictateSymbol: String {
        switch appState.dictationPhase {
        case .listening: return "waveform"
        case .transcribing: return "ellipsis.circle"
        case .success: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .setup, .ready: return "mic.fill"
        }
    }

    private var dictateColor: Color {
        switch appState.dictationPhase {
        case .listening: return .red
        case .transcribing: return .blue
        case .success: return .green
        case .failed: return .orange
        case .setup: return .secondary
        case .ready: return .accentColor
        }
    }
}

/// History row with inline edit; saving learns new words into custom vocabulary.
private struct EditableHistoryRow: View {
    @EnvironmentObject var appState: AppState
    let entry: TranscriptionEntry
    @State private var isEditing = false
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 140)
                    .scrollContentBackground(.hidden)
                HStack {
                    Text("Corrected words join your custom vocabulary.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        isEditing = false
                    }
                    Button("Save") {
                        appState.commitHistoryEdit(id: entry.id, newText: draft)
                        isEditing = false
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            } else {
                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(entry.timestamp, style: .date)
                    Text(entry.timestamp, style: .time)
                    Text("•")
                    Text(String(format: "%.1fs", entry.duration))
                    Text("•")
                    Text("\(entry.wordCount) words")
                    Spacer()
                    Button("Edit") {
                        draft = entry.text
                        isEditing = true
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit") {
                draft = entry.text
                isEditing = true
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            }
        }
    }
}

private enum SidebarItem: Hashable {
    case dashboard
    case dictate
    case history
    case settings
}

extension Notification.Name {
    static let macWisprShowSettings = Notification.Name("macWisprShowSettings")
}

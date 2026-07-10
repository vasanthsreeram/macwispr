import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSidebar: SidebarItem = .dashboard

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
                    } else if appState.isModelLoaded {
                        appState.startRecording()
                    }
                } label: {
                    Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(appState.isRecording ? .red : .accentColor)
                }
                .disabled(!appState.isModelLoaded)
                .help(appState.isRecording ? "Stop recording" : "Start recording")
            }
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
            }

            if selectedSidebar == .history {
                Section("Recent") {
                    if appState.transcriptionHistory.isEmpty {
                        Text("No transcriptions yet")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(appState.transcriptionHistory.prefix(50)) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dictateDetail: some View {
        VStack(spacing: 24) {
            if !appState.isModelLoaded {
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
                        VStack(alignment: .leading, spacing: 6) {
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
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.text, forType: .string)
                            }
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: TranscriptionEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .lineLimit(2)
                .font(.callout)
            HStack {
                Text(entry.timestamp, style: .time)
                Text("•")
                Text("\(entry.wordCount)w")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            }
        }
    }

    private var modelLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading Qwen3-ASR 0.6B")
                .font(.title3)

            ProgressView(value: appState.modelLoadProgress) {
                Text(appState.modelLoadStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 300)
        }
    }

    private var activeView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: appState.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(appState.isRecording ? .red : .accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: appState.isRecording)

                Text(appState.isRecording ? "Listening..." : "Ready to dictate")
                    .font(.title3)
                    .foregroundStyle(appState.isRecording ? .primary : .secondary)

                Text(appState.dictationMode.help)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Picker("Mode", selection: Binding(
                get: { appState.dictationMode },
                set: { appState.setDictationMode($0) }
            )) {
                ForEach(DictationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            HoldToSpeakButton()
                .frame(maxWidth: 360)

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

            if !appState.currentTranscription.isEmpty {
                GroupBox("Transcription") {
                    ScrollView {
                        Text(appState.currentTranscription)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }

            GroupBox("Quick Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Insert Mode", selection: $appState.insertionMode) {
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
}

private enum SidebarItem: Hashable {
    case dashboard
    case dictate
    case history
}

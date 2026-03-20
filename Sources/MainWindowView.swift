import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("OpenWhispr")
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
        List {
            Section("Transcription History") {
                if appState.transcriptionHistory.isEmpty {
                    Text("No transcriptions yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(appState.transcriptionHistory) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.text)
                                .lineLimit(2)
                                .font(.callout)
                            HStack {
                                Text(entry.timestamp, style: .time)
                                Text("•")
                                Text(String(format: "%.1fs", entry.duration))
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
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private var detailView: some View {
        VStack(spacing: 24) {
            if !appState.isModelLoaded {
                modelLoadingView
            } else {
                activeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
            // Status
            VStack(spacing: 8) {
                Image(systemName: appState.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(appState.isRecording ? .red : .accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: appState.isRecording)

                Text(appState.isRecording ? "Listening..." : "Hold ⌥Space to dictate")
                    .font(.title3)
                    .foregroundStyle(appState.isRecording ? .primary : .secondary)

                Text("Or click the mic button in the toolbar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Current transcription display
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

            // Quick settings
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

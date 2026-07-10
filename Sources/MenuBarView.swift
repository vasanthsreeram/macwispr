import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    private var week: UsageStats.Snapshot {
        UsageStats(typingWPM: appState.typingWPM).weeklySnapshot(entries: appState.transcriptionHistory)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Status Header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            Divider()

            if !appState.isModelLoaded {
                modelLoadSection
            } else {
                recordingSection
            }

            // Weekly stats strip
            if week.words > 0 || week.dictations > 0 {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(week.words.formatted()) words")
                            .font(.callout.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Time saved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(week.formattedTimeSaved)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            // Recent transcription
            if !appState.currentTranscription.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last transcription:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.currentTranscription)
                        .font(.body)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
            }

            // Quick actions
            VStack(spacing: 4) {
                Button {
                    openMainWindow()
                } label: {
                    Label("Open Dashboard", systemImage: "chart.bar.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Settings...", systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit MacWispr", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .frame(width: 300)
    }

    private func openMainWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "MacWispr" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Fallback: activate app so Window scene can present
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private var modelLoadSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: appState.modelLoadProgress) {
                Text(appState.modelLoadStatus)
                    .font(.caption)
            }
            .padding(.horizontal)
        }
        .padding(.horizontal)
    }

    private var recordingSection: some View {
        VStack(spacing: 8) {
            if appState.isRecording {
                HStack(spacing: 8) {
                    RecordingIndicator()
                    Text("Recording... release ⌥Space to stop")
                        .font(.callout)
                }
            } else {
                Text("Hold ⌥Space to dictate")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                if appState.isRecording {
                    Task { await appState.stopRecordingAndTranscribe() }
                } else {
                    appState.startRecording()
                }
            } label: {
                Label(
                    appState.isRecording ? "Stop & Transcribe" : "Start Recording",
                    systemImage: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isRecording ? .red : .accentColor)
        }
        .padding(.horizontal)
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isModelLoaded { return .green }
        return .orange
    }

    private var statusText: String {
        if appState.isRecording { return "Recording" }
        if appState.isModelLoaded { return "Ready" }
        if appState.isModelLoading { return "Loading..." }
        return "Model Not Loaded"
    }
}

struct RecordingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 12, height: 12)
            .scaleEffect(isAnimating ? 1.3 : 1.0)
            .opacity(isAnimating ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

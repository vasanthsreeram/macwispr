import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

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
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Settings...", systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    if let window = NSApp.windows.first(where: { $0.title == "OpenWhispr" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Window", systemImage: "macwindow")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit OpenWhispr", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .frame(width: 300)
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

            // Manual record button
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

import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    private var week: UsageStats.Snapshot {
        UsageStats(typingWPM: appState.typingWPM).weeklySnapshot(entries: appState.transcriptionHistory)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Status
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
                dictationControls
            }

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

            if !appState.currentTranscription.isEmpty {
                Divider()
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
            }

            Divider()

            VStack(spacing: 2) {
                menuRow(title: "Open Dashboard", systemImage: "chart.bar.fill") {
                    StatusBarController.shared.closePopover()
                    openMainWindow()
                }
                menuRow(title: "Settings...", systemImage: "gear") {
                    StatusBarController.shared.closePopover()
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider().padding(.vertical, 4)
                menuRow(title: "Quit MacWispr", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .frame(width: 300)
        .onAppear {
            AppDelegate.shared?.appState = appState
        }
    }

    // MARK: - Dictation controls

    private var dictationControls: some View {
        VStack(spacing: 10) {
            // Mode picker
            Picker("Mode", selection: Binding(
                get: { appState.dictationMode },
                set: { appState.setDictationMode($0) }
            )) {
                ForEach(DictationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Text(appState.dictationMode.help)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if appState.isRecording {
                HStack(spacing: 8) {
                    RecordingIndicator()
                    Text(appState.dictationMode == .hold
                          ? "Listening… release to stop"
                          : "Listening… tap Stop when done")
                        .font(.callout)
                }
            }

            // Hold-to-speak (press and hold on this button)
            HoldToSpeakButton()
                .padding(.horizontal)

            // Toggle start/stop
            Button {
                appState.toggleRecording()
            } label: {
                Label(
                    appState.isRecording ? "Stop & Transcribe" : "Start Listening",
                    systemImage: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(appState.isRecording ? .red : .accentColor)
            .padding(.horizontal)

            Text("Hotkey: ⌥Space  ·  \(appState.dictationMode == .hold ? "hold" : "toggle")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
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

    private func menuRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private func openMainWindow() {
        AppDelegate.shared?.appState = appState
        AppDelegate.shared?.showDashboard()
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

// MARK: - Hold-to-speak button

/// Press and hold this control to dictate (works even if the hotkey is flaky).
struct HoldToSpeakButton: View {
    @EnvironmentObject var appState: AppState
    @State private var pressing = false

    var body: some View {
        let active = pressing || (appState.isRecording && appState.dictationMode == .hold)

        Text(active ? "Listening… release" : "Hold to Speak")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(active ? Color.red : Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        // Temporarily force hold semantics for this button.
                        appState.startRecording()
                    }
                    .onEnded { _ in
                        pressing = false
                        Task { await appState.stopRecordingAndTranscribe() }
                    }
            )
            .disabled(!appState.isModelLoaded)
            .opacity(appState.isModelLoaded ? 1 : 0.5)
            .help("Press and hold while you speak, then release to transcribe")
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

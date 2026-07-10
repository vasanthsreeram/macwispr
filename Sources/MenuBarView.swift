import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

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
            VStack(spacing: 2) {
                menuRow(title: "Open Dashboard", systemImage: "chart.bar.fill") {
                    openMainWindow()
                }
                menuRow(title: "Settings...", systemImage: "gear") {
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
            // Wire the shared AppState into AppDelegate for reliable window opens.
            AppDelegate.shared?.appState = appState
        }
        .onReceive(NotificationCenter.default.publisher(for: .macWisprOpenMainWindow)) { _ in
            openMainWindow()
        }
    }

    /// Large hit target — plain SwiftUI Buttons inside MenuBarExtra(.window)
    /// often drop the action when the panel dismisses.
    private func menuRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
    }

    /// Prefer AppKit-hosted window (reliable from MenuBarExtra).
    private func openMainWindow() {
        AppDelegate.shared?.appState = appState
        // Close the menu-bar panel first, then open — avoids the click being
        // eaten when the popover tears down.
        if let panel = NSApp.windows.first(where: {
            $0.className.contains("MenuBar") || $0.className.contains("StatusBar")
        }) {
            panel.orderOut(nil)
        }
        if let delegate = AppDelegate.shared {
            delegate.showDashboard()
            return
        }
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
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

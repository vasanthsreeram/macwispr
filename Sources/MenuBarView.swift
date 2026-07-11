import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    private var week: UsageStats.Snapshot {
        UsageStats(typingWPM: appState.typingWPM).weeklySnapshot(entries: appState.transcriptionHistory)
    }

    private var displayTranscript: String {
        if !appState.lastCleanTranscription.isEmpty {
            return appState.lastCleanTranscription
        }
        return appState.currentTranscription
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
                if appState.dictationPhase == .listening {
                    Text(appState.recordingElapsedLabel)
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            if !appState.phaseDetail.isEmpty,
               appState.dictationPhase == .transcribing
                || appState.dictationPhase == .failed
                || appState.dictationPhase == .success
            {
                Text(appState.phaseDetail)
                    .font(.caption)
                    .foregroundStyle(appState.dictationPhase == .failed ? .orange : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            // Hotkey health
            HStack(spacing: 6) {
                Image(systemName: appState.hotkeyArmed ? "keyboard" : "keyboard.badge.ellipsis")
                    .foregroundStyle(appState.hotkeyArmed ? .green : .orange)
                Text(hotkeyStatusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !appState.hotkeyArmed {
                    Button("Fix") {
                        appState.repairHotkey()
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal)

            if appState.soundFeedbackEnabled && appState.outputMuted {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.slash.fill")
                        .foregroundStyle(.orange)
                    Text("Sound muted — unmute Mac to hear chimes")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal)
            }

            if let failure = appState.lastFailureMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
            }

            Divider()

            if !appState.isReadyToDictate {
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

            if !displayTranscript.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last result")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(displayTranscript)
                        .font(.body)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Button("Copy") {
                            appState.copyLastTranscription()
                        }
                        .controlSize(.small)
                        Button("Paste again") {
                            appState.repasteLastTranscription()
                        }
                        .controlSize(.small)
                        Spacer()
                    }
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
                menuRow(title: "Settings…", systemImage: "gear") {
                    StatusBarController.shared.closePopover()
                    openMainWindow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NotificationCenter.default.post(name: .macWisprShowSettings, object: nil)
                    }
                }
                if appState.needsSetup || appState.showOnboarding {
                    menuRow(title: "Setup Checklist…", systemImage: "checklist") {
                        StatusBarController.shared.closePopover()
                        appState.reopenOnboarding()
                        openMainWindow()
                    }
                }
                menuRow(title: "Check for Updates…", systemImage: "arrow.triangle.2.circlepath") {
                    StatusBarController.shared.closePopover()
                    SparkleUpdater.shared.checkForUpdates()
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
        // Avoid extra material layers inside NSPopover (double glass on Tahoe).
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            AppDelegate.shared?.appState = appState
            appState.refreshOutputMuteState()
        }
    }

    // MARK: - Dictation controls (one path per mode)

    private var dictationControls: some View {
        VStack(spacing: 10) {
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
                    Spacer()
                    Text(appState.recordingElapsedLabel)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            } else if appState.dictationPhase == .transcribing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing…")
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal)
            }

            switch appState.dictationMode {
            case .hold:
                HoldToSpeakButton()
                    .padding(.horizontal)
            case .toggle:
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
                .disabled(!appState.isReadyToDictate && !appState.isRecording)
            }

            Text("Hotkey: ⌥Space  ·  \(appState.dictationMode == .hold ? "hold" : "toggle") · change in Settings")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var modelLoadSection: some View {
        VStack(spacing: 8) {
            if appState.transcriptionProvider == .local && appState.isModelLoading {
                ProgressView(value: appState.modelLoadProgress) {
                    Text(appState.modelLoadStatus.isEmpty
                          ? "Downloading model… \(Int(appState.modelLoadProgress * 100))%"
                          : appState.modelLoadStatus)
                        .font(.caption)
                }
                Text("~500 MB–1.5 GB first run · stays on this Mac")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(appState.readinessLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if appState.transcriptionProvider != .local {
                    Text("Add your API key in Settings")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button("Open Setup") {
                    StatusBarController.shared.closePopover()
                    appState.reopenOnboarding()
                    openMainWindow()
                }
                .controlSize(.small)
            }
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
        switch appState.dictationPhase {
        case .listening: return .red
        case .transcribing: return .blue
        case .success: return .green
        case .failed, .setup: return .orange
        case .ready: return .green
        }
    }

    private var statusText: String {
        switch appState.dictationPhase {
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .success: return "Done"
        case .failed: return "Needs attention"
        case .setup:
            if appState.isModelLoading { return "Loading…" }
            return "Setup needed"
        case .ready:
            switch appState.transcriptionProvider {
            case .local: return "Ready · Local"
            case .openAI: return "Ready · OpenAI"
            case .elevenLabs: return "Ready · ElevenLabs"
            }
        }
    }

    private var hotkeyStatusLabel: String {
        if appState.hotkeyArmed {
            return "⌥Space armed (\(appState.dictationMode.rawValue.lowercased()))"
        }
        if appState.accessibilityTrusted {
            return "⌥Space not registered — click Fix"
        }
        return "⌥Space needs Accessibility"
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
                        appState.startRecording()
                    }
                    .onEnded { _ in
                        pressing = false
                        Task { await appState.stopRecordingAndTranscribe() }
                    }
            )
            .disabled(!appState.isReadyToDictate && !appState.isRecording)
            .opacity(appState.isReadyToDictate || appState.isRecording ? 1 : 0.5)
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

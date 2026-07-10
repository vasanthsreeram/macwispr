import SwiftUI
import AppKit

/// Compact pill that sits at the top of the screen (Superwhisper-style).
/// Idle → small logo chip. Listening → red pulse + “Listening”.
/// Click → open dashboard. Right-click → quick menu.
struct FloatingIndicatorView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulse = false

    var body: some View {
        Button(action: openDashboard) {
            HStack(spacing: 8) {
                statusGlyph
                    .frame(width: 26, height: 26)

                if showsStreamingText {
                    Text(appState.currentTranscription)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: 280, alignment: .leading)
                        .transition(.opacity)
                } else if showsLabel {
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, (showsLabel || showsStreamingText) ? 12 : 6)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(statusColor.opacity(appState.isRecording ? 0.7 : 0.25), lineWidth: 1.2)
            }
            .scaleEffect(appState.isRecording && pulse ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showsLabel)
            .animation(.easeOut(duration: 0.12), value: appState.currentTranscription)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .contextMenu {
            Button("Open Dashboard") { openDashboard() }
            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                if appState.isRecording {
                    Task { await appState.stopRecordingAndTranscribe() }
                } else if appState.isModelLoaded {
                    appState.startRecording()
                }
            }
            .disabled(!appState.isModelLoaded && !appState.isRecording)

            Divider()

            Button("Hide Floating Indicator") {
                appState.setFloatingIndicatorEnabled(false)
            }
        }
        .onAppear { pulse = true }
        .onChange(of: appState.isRecording) { _, recording in
            pulse = recording
            if recording { pulse = true }
        }
    }

    private var showsStreamingText: Bool {
        appState.isTranscribing && !appState.currentTranscription.isEmpty
    }

    private var showsLabel: Bool {
        if showsStreamingText { return false }
        return appState.isRecording || appState.isTranscribing || appState.isModelLoading
    }

    private var statusLabel: String {
        if appState.isRecording { return "Listening" }
        if appState.isTranscribing { return "Transcribing…" }
        if appState.isModelLoading { return "Loading…" }
        return "MacWispr"
    }

    private var helpText: String {
        if appState.isRecording { return "Listening — release ⌥Space to stop. Click for dashboard." }
        if showsStreamingText { return appState.currentTranscription }
        if appState.isTranscribing { return "Transcribing… Click for dashboard." }
        if !appState.isModelLoaded { return "Loading model… Click for dashboard." }
        return "MacWispr ready — hold ⌥Space to dictate. Click for dashboard."
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing { return .purple }
        if appState.isModelLoaded { return Color(red: 0.15, green: 0.55, blue: 1.0) }
        if appState.isModelLoading { return .orange }
        return .secondary
    }

    @ViewBuilder
    private var statusGlyph: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(appState.isRecording ? 0.28 : 0.14))

            if appState.isRecording {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            } else if appState.isTranscribing {
                ProgressView()
                    .controlSize(.small)
            } else if let logo = NSImage.appLogo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private func openDashboard() {
        AppDelegate.shared?.appState = appState
        AppDelegate.shared?.showDashboard()
    }
}

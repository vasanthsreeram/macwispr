import SwiftUI

/// First-run checklist: mic, Accessibility, hotkey, model, sound.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to MacWispr")
                        .font(.title2.weight(.semibold))
                    Text("A 30-second setup so ⌥Space just works.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                checklistRow(
                    done: appState.microphoneAuthorized,
                    title: "Microphone",
                    detail: appState.microphoneAuthorized
                        ? "Granted"
                        : "Allow when prompted so dictation can hear you"
                )
                checklistRow(
                    done: appState.accessibilityTrusted,
                    title: "Accessibility",
                    detail: appState.accessibilityTrusted
                        ? "Granted — paste into other apps works"
                        : "Required for ⌥Space and auto-paste"
                ) {
                    Button("Grant") { appState.repairHotkey() }
                        .controlSize(.small)
                }
                checklistRow(
                    done: appState.hotkeyArmed,
                    title: "⌥Space hotkey",
                    detail: appState.hotkeyArmed
                        ? "Armed (\(appState.dictationMode.rawValue.lowercased()) mode)"
                        : "Click Fix if this stays red after Accessibility"
                ) {
                    if !appState.hotkeyArmed {
                        Button("Fix") { appState.repairHotkey() }
                            .controlSize(.small)
                    }
                }
                checklistRow(
                    done: appState.isReadyToDictate,
                    title: "Speech engine",
                    detail: appState.readinessLabel
                )
                checklistRow(
                    done: appState.soundFeedbackEnabled && !appState.outputMuted,
                    title: "Sound feedback",
                    detail: !appState.soundFeedbackEnabled
                        ? "Off in Settings"
                        : (appState.outputMuted
                           ? "Mac output is muted — unmute to hear chimes"
                           : "Tink on start · Pop on release")
                ) {
                    if appState.soundFeedbackEnabled {
                        Button("Preview") {
                            appState.refreshOutputMuteState()
                            FeedbackSounds.playListeningStarted()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Toggle("Show listening banner under the menu bar", isOn: Binding(
                get: { appState.listeningHUDEnabled },
                set: { appState.setListeningHUDEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            Text("Also: menu bar mic turns red with a timer while you speak.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Skip for now") {
                    appState.completeOnboarding()
                }
                .keyboardShortcut(.cancelAction)
                Button(appState.needsSetup ? "I'll finish later" : "Done") {
                    appState.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { appState.refreshOutputMuteState() }
    }

    @ViewBuilder
    private func checklistRow(
        done: Bool,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

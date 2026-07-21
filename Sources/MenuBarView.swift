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

    private var hasLastRaw: Bool {
        !appState.lastRawTranscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasDistinctLastRaw: Bool {
        guard hasLastRaw else { return false }
        let raw = appState.lastRawTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        let polished = displayTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw != polished
    }

    var body: some View {
        VStack(spacing: 10) {
            // Compact alerts only — status + Hold to Speak live on the menu-bar
            // icon / ⌥Space, not duplicated in this popover.
            if !appState.hotkeyArmed {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .foregroundStyle(.orange)
                    Text(hotkeyStatusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Fix") {
                        appState.repairHotkey()
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
            }

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

            if !appState.isReadyToDictate {
                modelLoadSection
                Divider()
            }

            if week.words > 0 || week.dictations > 0 {
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

                Divider()
            }

            if !displayTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last result")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if hasDistinctLastRaw {
                        // Polished (what was inserted)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Polished")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(displayTranscript)
                                .font(.body)
                                .lineLimit(6)
                                .textSelection(.enabled)
                            HStack(spacing: 8) {
                                Button("Copy polished") {
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

                        // Raw STT before polish
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Raw (before polish)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(appState.lastRawTranscription)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                                .textSelection(.enabled)
                            HStack(spacing: 8) {
                                Button("Copy raw") {
                                    appState.copyLastRawTranscription()
                                }
                                .controlSize(.small)
                                Button("Paste raw") {
                                    appState.repasteLastRawTranscription()
                                }
                                .controlSize(.small)
                                Spacer()
                            }
                        }
                    } else {
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
                            if hasLastRaw {
                                Button("Copy raw") {
                                    appState.copyLastRawTranscription()
                                }
                                .controlSize(.small)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
            }

            VStack(spacing: 2) {
                micPickerRow
                Divider().padding(.vertical, 4)
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
            appState.refreshInputDevices()
        }
    }

    private var modelLoadSection: some View {
        VStack(spacing: 8) {
            if appState.transcriptionProvider == .local && appState.isModelLoading {
                ProgressView(value: appState.modelLoadProgress) {
                    Text(appState.modelLoadStatus.isEmpty
                          ? "Loading model… \(Int(appState.modelLoadProgress * 100))%"
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

    private var currentInputDeviceLabel: String {
        if appState.selectedInputDeviceUID.isEmpty {
            return "System Default (\(AudioInputDevices.defaultInputDeviceName()))"
        }
        return appState.availableInputDevices
            .first(where: { $0.uid == appState.selectedInputDeviceUID })?
            .name ?? "System Default"
    }

    private var micPickerRow: some View {
        Menu {
            Button {
                appState.setInputDeviceUID("")
            } label: {
                let title = "System Default (\(AudioInputDevices.defaultInputDeviceName()))"
                if appState.selectedInputDeviceUID.isEmpty {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }
            if !appState.availableInputDevices.isEmpty {
                Divider()
                ForEach(appState.availableInputDevices) { device in
                    Button {
                        appState.setInputDeviceUID(device.uid)
                    } label: {
                        let label = AudioInputDevices.isSystemDefault(uid: device.uid)
                            ? "\(device.name) — macOS default"
                            : device.name
                        if appState.selectedInputDeviceUID == device.uid {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }
            Divider()
            Button("Refresh device list") {
                appState.refreshInputDevices()
            }
        } label: {
            HStack(spacing: 6) {
                Label(currentInputDeviceLabel, systemImage: "mic.fill")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
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

    private var hotkeyStatusLabel: String {
        let chord = appState.dictationHotkey.displayString
        if appState.hotkeyArmed {
            return "\(chord) armed (\(appState.dictationMode.rawValue.lowercased()))"
        }
        if appState.accessibilityTrusted {
            return "\(chord) not registered — click Fix"
        }
        return "Hotkey needs Accessibility"
    }
}



import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(AppState.self) var appState

    private var week: UsageStats.Snapshot { appState.usageSummary.week }

    private var displayTranscript: String {
        if !appState.lastCleanTranscription.isEmpty {
            return appState.lastCleanTranscription
        }
        return appState.currentTranscription
    }

    var body: some View {
        VStack(spacing: 10) {
            header

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
                HStack(spacing: 0) {
                    weekStat(week.formattedTimeSaved, "saved this week")
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 26)
                    weekStat(week.words.formatted(), "words")
                }
                .padding(.vertical, DS.Space.m)
                .brandSurface(radius: DS.Radius.m)
                .padding(.horizontal, DS.Space.m)
            }

            if !displayTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last dictation")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(displayTranscript)
                        .font(.system(size: 13))
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

            VStack(spacing: 0) {
                Divider().padding(.bottom, 4)
                micPickerRow
                Divider().padding(.vertical, 4)
                menuRow(
                    title: appState.meetings.isRecording
                        ? "Stop Meeting Recording (\(appState.meetings.elapsedLabel))"
                        : "Record Meeting",
                    systemImage: appState.meetings.isRecording ? "stop.circle.fill" : "record.circle"
                ) {
                    appState.meetings.toggle()
                }
                Divider().padding(.vertical, 4)
                menuRow(title: "Open Dashboard", systemImage: "chart.bar.fill") {
                    StatusBarController.shared.closePopover()
                    openMainWindow()
                }
                menuRow(title: "Settings…", systemImage: "gearshape") {
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
        .padding(.top, DS.Space.m)
        .padding(.bottom, DS.Space.s)
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
            if appState.isModelLoading {
                ProgressView(value: appState.modelLoadProgress) {
                    Text(appState.modelLoadStatus.isEmpty
                          ? "Setting up… \(Int(appState.modelLoadProgress * 100))%"
                          : appState.modelLoadStatus)
                        .font(.caption)
                }
                Text("One-time setup · stays on this Mac")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(appState.readinessLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await appState.loadModel() }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
    }

    private var currentInputDeviceLabel: String {
        if appState.selectedInputDeviceUID.isEmpty {
            return "System Default"
        }
        return appState.availableInputDevices
            .first(where: { $0.uid == appState.selectedInputDeviceUID })?
            .name ?? "System Default"
    }

    private var micPickerRow: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "mic")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(currentInputDeviceLabel)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .allowsHitTesting(false)
        .overlay {
            GeometryReader { _ in
                AppKitPullDownMenu(
                    items: micMenuItems,
                    accessibilityLabel: "Microphone \(currentInputDeviceLabel)",
                    toolTip: "Microphone used for dictation"
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var micMenuItems: [AppKitSafeMenuItem] {
        var items: [AppKitSafeMenuItem] = [
            .action(
                title: "System Default",
                checked: appState.selectedInputDeviceUID.isEmpty
            ) {
                appState.setInputDeviceUID("")
            }
        ]
        if !appState.availableInputDevices.isEmpty {
            items.append(.separator)
            for device in appState.availableInputDevices {
                let uid = device.uid
                items.append(.action(
                    title: device.name.isEmpty ? "Microphone" : device.name,
                    checked: appState.selectedInputDeviceUID == uid
                ) {
                    appState.setInputDeviceUID(uid)
                })
            }
        }
        items.append(.separator)
        items.append(.action(title: "Refresh device list") {
            appState.refreshInputDevices()
        })
        return items
    }

    private var header: some View {
        let status = appState.readiness
        return HStack(spacing: DS.Space.s) {
            Text("MacWispr")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            StatusDot(tone: status.tone, text: status.text)
            if status.tone == .ready {
                Keycaps(keys: appState.dictationHotkey.badgeLabels, size: 10)
            }
        }
        .padding(.horizontal)
    }

    private func weekStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func menuRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        MenuRow(title: title, systemImage: systemImage, action: action)
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



/// Full-width popover row with a hover fill, like a native menu item.
private struct MenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.07) : .clear)
        )
        .onHover { isHovering = $0 }
        .appKitTap(title, action: action)
    }
}

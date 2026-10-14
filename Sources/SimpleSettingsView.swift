import SwiftUI
import AppKit
import MacWisprCore

/// The whole settings surface: one page, plain words, nothing to configure
/// for the speech model. Rarely used options sit under "Advanced".
struct SimpleSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section {
                speechModelRow
            } header: {
                Text("Speech")
            }

            Section {
                accessibilityRow
                microphoneAccessRow
            } header: {
                Text("Permissions")
            } footer: {
                Text("Accessibility lets MacWispr hear the shortcut from any app and type your words where the cursor is.")
            }

            Section("Dictation") {
                LabeledContent("Shortcut") {
                    ShortcutRecorderControl(
                        chord: appState.dictationHotkey,
                        requireSafeGlobal: true,
                        onRecorded: { appState.setDictationHotkey($0) }
                    )
                }
                Picker("Mode", selection: Binding(
                    get: { appState.dictationMode },
                    set: { appState.setDictationMode($0) }
                )) {
                    Text("Hold to talk").tag(DictationMode.hold)
                    Text("Press to start / stop").tag(DictationMode.toggle)
                }
                Picker("Microphone", selection: Binding(
                    get: { appState.selectedInputDeviceUID },
                    set: { appState.setInputDeviceUID($0) }
                )) {
                    Text("System default").tag("")
                    ForEach(appState.availableInputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                Toggle("Play sounds", isOn: Binding(
                    get: { appState.soundFeedbackEnabled },
                    set: { appState.setSoundFeedbackEnabled($0) }
                ))
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    advancedContent
                }
            }

            Section {
                HStack {
                    Text("MacWispr \(AppVersion.display)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates…") {
                        SparkleUpdater.shared.checkForUpdates()
                    }
                    .disabled(!SparkleUpdater.shared.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshInputDevices()
            appState.refreshHotkeyHealth()
        }
    }

    // MARK: - Rows

    private var speechModelRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(ModelCatalog.shippedDisplayName)
                    .font(.headline)
                Text(speechStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if appState.isModelLoading {
                    ProgressView(value: appState.modelLoadProgress)
                        .controlSize(.small)
                        .accessibilityLabel("Setting up speech model")
                }
            }
            Spacer()
            if appState.isModelLoaded || appState.isReadyToDictate, !appState.isModelLoading {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else if !appState.isModelLoading {
                Button(appState.modelLoadStatus.hasPrefix("Error") ? "Try Again" : "Set Up") {
                    Task { await appState.loadModel() }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var speechStatusText: String {
        if appState.isModelLoading {
            return appState.modelLoadStatus.isEmpty ? "Setting up…" : appState.modelLoadStatus
        }
        if appState.modelLoadStatus.hasPrefix("Error") {
            return appState.modelLoadStatus
        }
        return "Runs on this Mac. Your voice never leaves it."
    }

    private var accessibilityRow: some View {
        HStack {
            Label("Accessibility", systemImage: "hand.raised.fill")
            Spacer()
            if appState.accessibilityTrusted {
                Label("On", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Turn On…") { appState.repairHotkey() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var microphoneAccessRow: some View {
        HStack {
            Label("Microphone", systemImage: "mic.fill")
            Spacer()
            if appState.microphoneAuthorized {
                Label("On", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Turn On…") {
                    AudioRecorder.requestPermissionIfNeeded()
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var advancedContent: some View {
        Picker("Put text into apps by", selection: Binding(
            get: { appState.insertionMode },
            set: { appState.setInsertionMode($0) }
        )) {
            Text("Pasting (fastest)").tag(InsertionMode.both)
            Text("Typing it out").tag(InsertionMode.typeOut)
            Text("Copy only").tag(InsertionMode.clipboard)
        }
        Picker("Recording window", selection: Binding(
            get: { appState.recordingWindowStyle },
            set: { appState.setRecordingWindowStyle($0) }
        )) {
            ForEach(RecordingWindowStyle.allCases) { style in
                Text(style.displayName).tag(style)
            }
        }
        LabeledContent("Cancel shortcut") {
            ShortcutRecorderControl(
                chord: appState.cancelHotkey,
                requireSafeGlobal: false,
                onRecorded: { appState.setCancelHotkey($0) }
            )
        }
        Toggle("Share anonymous usage data", isOn: Binding(
            get: { appState.telemetryOptIn },
            set: { appState.setTelemetryOptIn($0) }
        ))
        HStack {
            Button("Show setup again") { appState.reopenOnboarding() }
            Button("Clear history", role: .destructive) { appState.clearHistory() }
            Spacer()
            Button("Re-download model", role: .destructive) {
                Task {
                    await appState.deleteDownloadedASRModel(appState.asrModelSize)
                    await appState.loadModel()
                }
            }
            .disabled(appState.isModelLoading || appState.isRecording)
        }
    }
}

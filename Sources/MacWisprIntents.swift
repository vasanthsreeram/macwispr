import AppIntents
import AppKit

/// Shortcuts / Spotlight / Siri entry points for dictation.
struct StartDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Start MacWispr Dictation"
    static var description = IntentDescription("Begin listening for voice dictation.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            guard let state = AppState.shared else { return }
            if state.dictationMode == .toggle || !state.isRecording {
                state.startRecording()
            }
        }
        return .result(dialog: "Listening.")
    }
}

struct StopDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop MacWispr Dictation"
    static var description = IntentDescription("Stop listening and insert the transcript.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            guard let state = AppState.shared, state.isRecording else { return }
            Task { await state.stopRecordingAndTranscribe() }
        }
        return .result(dialog: "Transcribing.")
    }
}

struct ToggleDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle MacWispr Dictation"
    static var description = IntentDescription("Start or stop MacWispr dictation.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            AppState.shared?.toggleRecording()
        }
        return .result(dialog: "Toggled dictation.")
    }
}

struct OpenMacWisprDashboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Open MacWispr Dashboard"
    static var description = IntentDescription("Open the MacWispr dashboard window.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppDelegate.shared?.showDashboard()
        }
        return .result()
    }
}

struct MacWisprShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: [
                "Toggle \(.applicationName) dictation",
                "Dictate with \(.applicationName)",
            ],
            shortTitle: "Toggle Dictation",
            systemImageName: "mic.circle"
        )
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Start \(.applicationName) dictation",
            ],
            shortTitle: "Start Dictation",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopDictationIntent(),
            phrases: [
                "Stop \(.applicationName) dictation",
            ],
            shortTitle: "Stop Dictation",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: OpenMacWisprDashboardIntent(),
            phrases: [
                "Open \(.applicationName) dashboard",
            ],
            shortTitle: "Open Dashboard",
            systemImageName: "chart.bar.fill"
        )
    }
}

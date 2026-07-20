import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newVocabTerm: String = ""
    @State private var openAIKeyDraft: String = ""
    @State private var elevenLabsKeyDraft: String = ""
    @State private var keySaveMessage: String?
    @State private var keySaveIsError = false

    private let languages: [(String?, String)] = [
        (nil, "Auto-detect"),
        ("en", "English"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("pt", "Portuguese"),
        ("ru", "Russian"),
        ("ar", "Arabic"),
        ("it", "Italian"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("sv", "Swedish"),
        ("tr", "Turkish"),
        ("uk", "Ukrainian"),
        ("vi", "Vietnamese"),
        ("th", "Thai"),
        ("hi", "Hindi"),
    ]

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gear") }

            transcriptionSettings
                .tabItem { Label("Transcription", systemImage: "text.bubble") }

            hotkeySettings
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }

            aboutView
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(.top, 8)
    }

    private var generalSettings: some View {
        Form {
            Section("Text Insertion") {
                Picker("Mode", selection: Binding(
                    get: { appState.insertionMode },
                    set: { appState.setInsertionMode($0) }
                )) {
                    ForEach(InsertionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }

            Section("Time Saved") {
                HStack {
                    Text("Typing speed baseline")
                    Spacer()
                    Text("\(Int(appState.typingWPM)) WPM")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { appState.typingWPM },
                        set: { appState.setTypingWPM($0) }
                    ),
                    in: 20...200,
                    step: 5
                )
                Text("How fast you type — used only for “time saved” estimates (up to 200 WPM).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Button("Clear transcription history", role: .destructive) {
                    appState.clearHistory()
                }
            }

            Section("Privacy") {
                Toggle("Share anonymous usage data", isOn: Binding(
                    get: { appState.telemetryOptIn },
                    set: { appState.setTelemetryOptIn($0) }
                ))
                Button("What we collect…") {
                    appState.showTelemetryDisclosure = true
                }
            }

            Section("Developer") {
                Toggle("Save audio + text locally", isOn: Binding(
                    get: { appState.devCaptureEnabled },
                    set: { appState.setDevCaptureEnabled($0) }
                ))
                Text(
                    "Dev mode: each dictation writes a WAV plus raw STT / post-process / polished text under Application Support → MacWispr → dev-captures. Stays on this Mac only — never uploaded. Keeps the last \(DevCaptureStore.maxCaptures) captures."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if ProcessInfo.processInfo.environment["MACWISPR_DEV_CAPTURE"] == "1" {
                    Text("Forced on by MACWISPR_DEV_CAPTURE=1 for this process.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Open captures folder") {
                        DevCaptureStore.openInFinder()
                    }
                    Button("Clear captures", role: .destructive) {
                        DevCaptureStore.clearAll()
                    }
                }
                Text("\(DevCaptureStore.captureCount()) capture(s) on disk")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Polish is opt-in (Off by default). Raw STT inserts unless the user enables it.
            Section("Post-Processing") {
                Toggle("Auto-capitalize first letter", isOn: $appState.autoCapitalize)
                Text("By default MacWispr inserts the transcript as spoken. Polish is optional and off until you turn it on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Polish transcript", selection: Binding(
                    get: { appState.polishProvider },
                    set: { appState.setPolishProvider($0) }
                )) {
                    ForEach(PolishProvider.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(appState.polishProvider.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.polishProvider == .local {
                    // Model pack switcher — default Qwen polish; Liquid only if selectable.
                    let available = PolishLocalModel.availableCases
                    if available.count > 1 {
                        Picker("Local polish model", selection: Binding(
                            get: { appState.polishLocalModel },
                            set: { appState.setPolishLocalModel($0) }
                        )) {
                            ForEach(available) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                    } else {
                        Text(appState.polishLocalModel.displayName)
                            .font(.subheadline)
                    }
                    Text(appState.polishLocalModel.help)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if appState.isLLMLoading {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: appState.llmLoadProgress)
                            Text(appState.llmLoadStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } else if appState.isLLMLoaded {
                        HStack {
                            Label("Active: \(appState.polishLocalModel.shortName)", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Spacer()
                        }
                    } else if !appState.isPolishModelOnDisk {
                        // Production path: weights not in the Sparkle zip.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Polish model not installed. One-time download \(appState.polishLocalModel.downloadSizeLabel) from Hugging Face (saved under Application Support).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Download polish model (\(appState.polishLocalModel.downloadSizeLabel))") {
                                Task { await appState.downloadPolishModel() }
                            }
                            .buttonStyle(.borderedProminent)
                            if !appState.llmLoadStatus.isEmpty {
                                Text(appState.llmLoadStatus)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .lineLimit(3)
                            }
                        }
                    } else {
                        HStack {
                            Text("On disk · not loaded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Load \(appState.polishLocalModel.shortName)") {
                                Task { await appState.loadLLM(force: true) }
                            }
                        }
                    }

                    // Only offer delete for Application Support installs (not bundle/dev).
                    if appState.isPolishModelOnDisk,
                       PolishLocalModel.applicationSupportDirectory(for: appState.polishLocalModel)
                        .map({ FileManager.default.fileExists(atPath: $0.path)
                            && PolishLocalModel.looksLikeCompletePack(at: $0) }) == true
                    {
                        Button("Remove downloaded polish model", role: .destructive) {
                            Task { await appState.deleteDownloadedPolishModel() }
                        }
                        .font(.caption)
                    }
                } else if appState.polishProvider == .openAI {
                    if appState.hasOpenAIKey {
                        Label("Using saved OpenAI key", systemImage: "key.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Add an OpenAI key under Transcription → API keys", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var transcriptionSettings: some View {
        Form {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    if appState.isReadyToDictate {
                        Label(appState.readinessLabel, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if appState.isModelLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.modelLoadStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Label(appState.readinessLabel, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Picker("Language", selection: $appState.selectedLanguage) {
                    ForEach(languages, id: \.0) { lang in
                        Text(lang.1).tag(lang.0)
                    }
                }
            }

            if appState.transcriptionProvider == .local {
                Section("On-device model") {
                    Picker("Model", selection: Binding(
                        get: { appState.asrModelSize },
                        set: { appState.setASRModelSize($0) }
                    )) {
                        Section("Qwen — En + Asian (GPU)") {
                            ForEach([ASRModelSize.small, .large], id: \.id) { size in
                                Text(size.pickerLabel).tag(size)
                            }
                        }
                        Section("Parakeet — En + EU (Neural Engine)") {
                            // Single INT8 fixed-shape export (INT4 HF retired).
                            // Legacy Parakeet-INT4 UserDefaults still load via ASRModelSize.
                            ForEach([ASRModelSize.parakeetInt8], id: \.id) { size in
                                Text(size.pickerLabel).tag(size)
                            }
                        }
                    }
                    .disabled(appState.isModelLoading || appState.isRecording)

                    Text(appState.asrModelSize.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Custom vocabulary") {
                HStack {
                    TextField("Add words… e.g. MacWispr, Grok", text: $newVocabTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addVocabTerm() }
                    Button("Add") { addVocabTerm() }
                        .disabled(newVocabTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if appState.customVocabulary.isEmpty {
                    Text("Optional — names and jargon the model mishears.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(appState.customVocabulary, id: \.self) { term in
                        HStack {
                            Text(term)
                            Spacer()
                            Button {
                                appState.removeVocabularyTerm(term)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(term)")
                        }
                    }

                    Button("Clear all", role: .destructive) {
                        appState.clearVocabulary()
                    }
                }
            }

            // BYOK last — pick provider, keys expand only when needed.
            Section("Speech provider") {
                Picker("Provider", selection: Binding(
                    get: { appState.transcriptionProvider },
                    set: { appState.setTranscriptionProvider($0) }
                )) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .disabled(appState.isRecording)

                if appState.transcriptionProvider == .openAI {
                    DisclosureGroup("OpenAI API key") {
                        VStack(alignment: .leading, spacing: 8) {
                            if appState.hasOpenAIKey {
                                Text(appState.openAIKeyMasked)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            SecureField("sk-…", text: $openAIKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            HStack {
                                Button("Save") { saveOpenAIKey() }
                                    .disabled(openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                if appState.hasOpenAIKey {
                                    Button("Clear", role: .destructive) { clearOpenAIKey() }
                                }
                                Spacer()
                                Link("Get key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                                    .font(.caption)
                            }
                            Text("Stored in Keychain only.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if appState.transcriptionProvider == .elevenLabs {
                    DisclosureGroup("ElevenLabs API key") {
                        VStack(alignment: .leading, spacing: 8) {
                            if appState.hasElevenLabsKey {
                                Text(appState.elevenLabsKeyMasked)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            SecureField("xi-…", text: $elevenLabsKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            HStack {
                                Button("Save") { saveElevenLabsKey() }
                                    .disabled(elevenLabsKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                if appState.hasElevenLabsKey {
                                    Button("Clear", role: .destructive) { clearElevenLabsKey() }
                                }
                                Spacer()
                                Link("Get key", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                                    .font(.caption)
                            }
                            Text("Stored in Keychain only.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let keySaveMessage {
                    Text(keySaveMessage)
                        .font(.caption)
                        .foregroundStyle(keySaveIsError ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addVocabTerm() {
        appState.addVocabularyTerm(newVocabTerm)
        newVocabTerm = ""
    }

    private func saveOpenAIKey() {
        do {
            try appState.saveOpenAIKey(openAIKeyDraft)
            openAIKeyDraft = ""
            keySaveIsError = false
            keySaveMessage = "OpenAI key saved to Keychain."
        } catch {
            keySaveIsError = true
            keySaveMessage = error.localizedDescription
        }
    }

    private func clearOpenAIKey() {
        do {
            try appState.clearOpenAIKey()
            openAIKeyDraft = ""
            keySaveIsError = false
            keySaveMessage = "OpenAI key removed."
        } catch {
            keySaveIsError = true
            keySaveMessage = error.localizedDescription
        }
    }

    private func saveElevenLabsKey() {
        do {
            try appState.saveElevenLabsKey(elevenLabsKeyDraft)
            elevenLabsKeyDraft = ""
            keySaveIsError = false
            keySaveMessage = "ElevenLabs key saved to Keychain."
        } catch {
            keySaveIsError = true
            keySaveMessage = error.localizedDescription
        }
    }

    private func clearElevenLabsKey() {
        do {
            try appState.clearElevenLabsKey()
            elevenLabsKeyDraft = ""
            keySaveIsError = false
            keySaveMessage = "ElevenLabs key removed."
        } catch {
            keySaveIsError = true
            keySaveMessage = error.localizedDescription
        }
    }

    private var hotkeySettings: some View {
        Form {
            Section("Dictation Mode") {
                Picker("Mode", selection: Binding(
                    get: { appState.dictationMode },
                    set: { appState.setDictationMode($0) }
                )) {
                    ForEach(DictationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(appState.dictationMode.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Hotkey")
                    Spacer()
                    Text("⌥ Space")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("Menu bar shows only the control for your current mode (Hold button or Start/Stop).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Also available via Shortcuts / Spotlight: Start, Stop, Toggle dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sound & status") {
                Toggle("Play feedback sounds", isOn: Binding(
                    get: { appState.soundFeedbackEnabled },
                    set: { appState.setSoundFeedbackEnabled($0) }
                ))

                Toggle("Show listening banner", isOn: Binding(
                    get: { appState.listeningHUDEnabled },
                    set: { appState.setListeningHUDEnabled($0) }
                ))
                Text("Floating “Listening” / “Done” banner under the menu bar. Menu bar mic also turns red with a timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.soundFeedbackEnabled {
                    if appState.outputMuted {
                        Label(
                            "Mac sound is muted (or volume is zero). Unmute to hear chimes.",
                            systemImage: "speaker.slash.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Volume")
                            Spacer()
                            Text("\(Int(appState.feedbackSoundVolume * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { appState.feedbackSoundVolume },
                                set: { appState.setFeedbackSoundVolume($0) }
                            ),
                            in: 0...1,
                            step: 0.05
                        )
                        Text("Applies to all MacWispr chimes (separate from system volume).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    chimePicker(
                        title: "Start listening",
                        selection: Binding(
                            get: { appState.startChime },
                            set: { appState.setStartChime($0) }
                        ),
                        preview: { FeedbackSounds.playListeningStarted() }
                    )
                    chimePicker(
                        title: "Stop / release",
                        selection: Binding(
                            get: { appState.stopChime },
                            set: { appState.setStopChime($0) }
                        ),
                        preview: { FeedbackSounds.playListeningStopped() }
                    )
                    chimePicker(
                        title: "Done (final chime)",
                        selection: Binding(
                            get: { appState.successChime },
                            set: { appState.setSuccessChime($0) }
                        ),
                        preview: { FeedbackSounds.playSuccess() }
                    )
                    chimePicker(
                        title: "Error / not ready",
                        selection: Binding(
                            get: { appState.failureChime },
                            set: { appState.setFailureChime($0) }
                        ),
                        preview: { FeedbackSounds.playFailure() }
                    )

                    HStack(spacing: 12) {
                        Button("Preview all") {
                            appState.refreshOutputMuteState()
                            FeedbackSounds.playListeningStarted()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                FeedbackSounds.playListeningStopped()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                FeedbackSounds.playSuccess()
                            }
                        }
                        Button("Recheck mute") {
                            appState.refreshOutputMuteState()
                        }
                        .font(.caption)
                    }
                }

                Button("Show setup checklist again…") {
                    appState.reopenOnboarding()
                }
                .font(.caption)
            }
            .onAppear {
                appState.refreshOutputMuteState()
                appState.refreshInputDevices()
            }

            Section("Microphone") {
                Picker("Input device", selection: Binding(
                    get: { appState.selectedInputDeviceUID },
                    set: { appState.setInputDeviceUID($0) }
                )) {
                    Text("System Default").tag("")
                    ForEach(appState.availableInputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                if appState.selectedInputDeviceUID.isEmpty {
                    Text("Following macOS default: \(AudioInputDevices.defaultInputDeviceName())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Applies on the next dictation. Plug in a USB or Bluetooth mic, then refresh if it does not appear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Refresh device list") {
                    appState.refreshInputDevices()
                }
                .font(.caption)
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if appState.accessibilityTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            appState.repairHotkey()
                        }
                    }
                }
                HStack {
                    Text("Global hotkey")
                    Spacer()
                    if appState.hotkeyArmed {
                        Label("⌥Space ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Repair Hotkey") {
                            appState.repairHotkey()
                        }
                    }
                }
                Text("Accessibility is required for ⌥Space and for pasting into other apps. After an update or reinstall, re-enable MacWispr in System Settings → Privacy & Security → Accessibility (TCC binds to the binary). The hotkey re-arms automatically once granted — no relaunch needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aboutView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let logo = NSImage.appLogo {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                } else {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                }

                Text("MacWispr")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Voice dictation for macOS — local or BYOK cloud")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Version \(AppVersion.display)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    SparkleUpdater.shared.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(!SparkleUpdater.shared.canCheckForUpdates)

                VStack(alignment: .leading, spacing: 8) {
                    aboutRow(icon: "macbook", title: "On-device", detail: "Qwen (En + Asian) · Parakeet v3 (En + EU)")
                    aboutRow(icon: "key.fill", title: "BYOK cloud", detail: "OpenAI · ElevenLabs Scribe v2")
                    aboutRow(icon: "text.badge.checkmark", title: "Polish", detail: "Local LLM or OpenAI · Keychain-only keys")
                    aboutRow(icon: "keyboard", title: "Hotkey", detail: "⌥Space hold or toggle · Both insert by default")
                }
                .frame(maxWidth: 360)
                .padding(.top, 4)

                HStack(spacing: 16) {
                    Link("Website", destination: URL(string: "https://vasanthsreeram.github.io/macwispr/")!)
                    Link("GitHub", destination: URL(string: "https://github.com/vasanthsreeram/macwispr")!)
                    Link("Releases", destination: URL(string: "https://github.com/vasanthsreeram/macwispr/releases")!)
                }
                .font(.callout)

                Text("MIT License · Open source")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func chimePicker(
        title: String,
        selection: Binding<SystemChime>,
        preview: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Picker(title, selection: selection) {
                ForEach(SystemChime.playable) { chime in
                    Text(chime.displayName).tag(chime)
                }
            }
            Button {
                appState.refreshOutputMuteState()
                // Apply binding first is already done; preview uses prefs.
                preview()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Preview")
            .disabled(selection.wrappedValue.isSilent)
        }
    }

    private func aboutRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Single source for the About tab / marketing version string.
enum AppVersion {
    static let display: String = {
        if let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !short.isEmpty
        {
            return short
        }
        return "1.2.3"
    }()
}

/// Resolves PRIVACY.md from the app bundle, repo checkout, or GitHub.
enum PrivacyDoc {
    static var url: URL? {
        if let bundled = Bundle.main.url(forResource: "PRIVACY", withExtension: "md") {
            return bundled
        }
        // Dev / `swift run` from repo root.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidate = cwd.appendingPathComponent("PRIVACY.md")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }
}

// MARK: - First-run / Settings telemetry disclosure (#7)

/// Exact collect / never-collect manifest for the opt-in disclosure sheet.
struct TelemetryDisclosureSheet: View {
    @EnvironmentObject var appState: AppState
    /// When true, "Not now" only dismisses without changing opt-in (re-open from Settings).
    var isRevisit: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anonymous usage data")
                .font(.title2.weight(.semibold))

            Text("MacWispr can send **anonymous, content-free** reliability signals so we can fix issues like a silently dead ⌥Space hotkey after updates. Telemetry is **opt-in** and off by default.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("We collect") {
                VStack(alignment: .leading, spacing: 6) {
                    bullet("App version, macOS version, CPU architecture")
                    bullet("Transcription latency (bucketed: <1s, 1–3s, 3–10s, >10s)")
                    bullet("Dictation event counts (completed / failed)")
                    bullet("Hotkey / Accessibility health flags (booleans only)")
                    bullet("Coarse config: provider, model size, hold/toggle, insertion mode")
                    bullet("Failure category enum (no_audio, mic_denied, paste_no_ax, stt_error)")
                    bullet("A random install ID stored only on this Mac")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("We never collect") {
                VStack(alignment: .leading, spacing: 6) {
                    bullet("Transcription text")
                    bullet("Audio samples or recordings")
                    bullet("Custom vocabulary words")
                    bullet("Clipboard contents")
                    bullet("API keys or secrets")
                    bullet("Hardware identifiers, username, email, or precise location")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            if let privacyURL = PrivacyDoc.url {
                Link("Read PRIVACY.md", destination: privacyURL)
                    .font(.callout)
            } else if let web = URL(string: "https://github.com/vasanthsreeram/macwispr/blob/main/PRIVACY.md") {
                Link("Read PRIVACY.md on GitHub", destination: web)
                    .font(.callout)
            }

            HStack {
                Button("Not now") {
                    if isRevisit {
                        appState.showTelemetryDisclosure = false
                        Telemetry.shared.markDisclosureSeen()
                    } else {
                        appState.acknowledgeTelemetryDisclosure(optIn: false)
                    }
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(appState.telemetryOptIn && isRevisit ? "Keep sharing" : "Share anonymous data") {
                    appState.acknowledgeTelemetryDisclosure(optIn: true)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 480)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension NSImage {
    /// Bundled app logo (`AppLogo.png` in Resources), or nil if missing.
    static var appLogo: NSImage? {
        if let url = Bundle.main.url(forResource: "AppLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        // Fallback: same file as the app icon if present.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        return nil
    }
}

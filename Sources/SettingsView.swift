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

                Text("Clipboard mode copies text and pastes via ⌘V. Type mode simulates keypresses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Post-Processing") {
                Toggle("Remove filler words (uh, um, like...)", isOn: $appState.removeFillerWords)
                Toggle("Auto-capitalize first letter", isOn: $appState.autoCapitalize)

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
                    HStack {
                        Text(TextPolisher.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if appState.isLLMLoaded {
                            Label("Loaded", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if appState.isLLMLoading {
                            ProgressView()
                                .controlSize(.small)
                            Text(appState.llmLoadStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if appState.llmLoadStatus.hasPrefix("Error") {
                            Label(appState.llmLoadStatus, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        } else {
                            Text("Not loaded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !appState.isLLMLoaded && !appState.isLLMLoading {
                        Button("Download polish model (~300 MB)") {
                            Task { await appState.loadLLM() }
                        }
                    }
                } else if appState.polishProvider == .openAI {
                    if appState.hasOpenAIKey {
                        Label("Using saved OpenAI key (\(appState.openAIKeyMasked))", systemImage: "key.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Add an OpenAI key under API Keys first", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
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
                    in: 20...80,
                    step: 5
                )
                Text("Used to estimate how long the same text would take to type. Higher WPM → less estimated time saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Button("Clear transcription history", role: .destructive) {
                    appState.clearHistory()
                }
                Text("History powers the weekly word-count and time-saved dashboard. Stored locally in Application Support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var transcriptionSettings: some View {
        Form {
            Section("Provider (BYOK)") {
                Picker("Speech-to-text", selection: Binding(
                    get: { appState.transcriptionProvider },
                    set: { appState.setTranscriptionProvider($0) }
                )) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .disabled(appState.isRecording)

                Text(appState.transcriptionProvider.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.transcriptionProvider.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
            }

            Section("API Keys") {
                Text("Keys stay on this Mac in the Keychain. They are never uploaded to MacWispr servers (there are none).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("OpenAI")
                            .fontWeight(.medium)
                        Spacer()
                        if appState.hasOpenAIKey {
                            Text(appState.openAIKeyMasked)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not set")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    SecureField("sk-…", text: $openAIKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Button("Save OpenAI key") {
                            saveOpenAIKey()
                        }
                        .disabled(openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if appState.hasOpenAIKey {
                            Button("Clear", role: .destructive) {
                                clearOpenAIKey()
                            }
                        }
                        Spacer()
                        Link("Get key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ElevenLabs")
                            .fontWeight(.medium)
                        Spacer()
                        if appState.hasElevenLabsKey {
                            Text(appState.elevenLabsKeyMasked)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not set")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    SecureField("xi-…", text: $elevenLabsKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Button("Save ElevenLabs key") {
                            saveElevenLabsKey()
                        }
                        .disabled(elevenLabsKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if appState.hasElevenLabsKey {
                            Button("Clear", role: .destructive) {
                                clearElevenLabsKey()
                            }
                        }
                        Spacer()
                        Link("Get key", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)

                if let keySaveMessage {
                    Text(keySaveMessage)
                        .font(.caption)
                        .foregroundStyle(keySaveIsError ? .red : .green)
                }
            }

            if appState.transcriptionProvider == .local {
                Section("On-device Speech Model") {
                    Picker("Size", selection: Binding(
                        get: { appState.asrModelSize },
                        set: { appState.setASRModelSize($0) }
                    )) {
                        ForEach(ASRModelSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(appState.isModelLoading || appState.isRecording)

                    HStack {
                        Text(appState.asrModelSize.displayName)
                        Spacer()
                        if appState.isModelLoaded {
                            Label("Loaded", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if appState.isModelLoading {
                            ProgressView()
                                .controlSize(.small)
                            Text(appState.modelLoadStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Label("Not loaded", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(appState.asrModelSize.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.asrModelSize.help)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(appState.asrModelSize.modelId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            } else {
                Section("Cloud model") {
                    if appState.transcriptionProvider == .openAI {
                        Text("Uses gpt-4o-mini-transcribe over the OpenAI Audio API. Custom vocabulary is sent as a recognition prompt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Uses ElevenLabs scribe_v2. Custom vocabulary is sent as keyterms when present.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Polish Model") {
                HStack {
                    Text(appState.polishProvider.displayName)
                    Spacer()
                    switch appState.polishProvider {
                    case .off:
                        Text("Off")
                            .foregroundStyle(.secondary)
                    case .local:
                        if appState.isLLMLoaded {
                            Label("Loaded", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if appState.isLLMLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Pending", systemImage: "arrow.down.circle")
                                .foregroundStyle(.orange)
                        }
                    case .openAI:
                        if appState.hasOpenAIKey {
                            Label("Key ready", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Needs key", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Text("Optional rewrite for cleaner sentences. Configure under General → Post-Processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Language") {
                Picker("Language", selection: $appState.selectedLanguage) {
                    ForEach(languages, id: \.0) { lang in
                        Text(lang.1).tag(lang.0)
                    }
                }
                Text("Auto-detect works well for most languages. Pin a language for faster results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Custom Vocabulary") {
                Text("Add names, product terms, or jargon you want the speech model to recognize more accurately. Editing a dictation also adds corrected words here automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Add words… e.g. MacWispr, Grok", text: $newVocabTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addVocabTerm() }
                    Button("Add") { addVocabTerm() }
                        .disabled(newVocabTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Tip: paste several at once, separated by commas.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if appState.customVocabulary.isEmpty {
                    Text("No custom words yet — add any that get misheard.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(appState.customVocabulary.count) custom word\(appState.customVocabulary.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                Text("You can also use Hold to Speak / Start Listening in the menu bar panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sound Feedback") {
                Toggle("Play sounds when listening starts and stops", isOn: Binding(
                    get: { appState.soundFeedbackEnabled },
                    set: { appState.setSoundFeedbackEnabled($0) }
                ))
                Text("Start chime when listening begins. End chime only after transcription finishes (not when you release the key).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.soundFeedbackEnabled {
                    HStack(spacing: 12) {
                        Button("Preview start") {
                            FeedbackSounds.playListeningStarted()
                        }
                        Button("Preview stop") {
                            FeedbackSounds.playListeningStopped()
                        }
                    }
                }
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

                VStack(alignment: .leading, spacing: 8) {
                    aboutRow(icon: "macbook", title: "On-device", detail: "Qwen3-ASR 0.6B / 1.7B (MLX 8-bit)")
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
        return "1.2.1"
    }()
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

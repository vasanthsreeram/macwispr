import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

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
        .frame(width: 450, height: 350)
    }

    private var generalSettings: some View {
        Form {
            Section("Text Insertion") {
                Picker("Mode", selection: $appState.insertionMode) {
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
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var transcriptionSettings: some View {
        Form {
            Section("Model") {
                HStack {
                    Text("Qwen3-ASR-0.6B-MLX-4bit")
                    Spacer()
                    if appState.isModelLoaded {
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Load") {
                            Task { await appState.loadModel() }
                        }
                    }
                }
                Text("300MB, on-device, Metal GPU accelerated")
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
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hotkeySettings: some View {
        Form {
            Section("Global Hotkey") {
                HStack {
                    Text("Dictation")
                    Spacer()
                    Text("⌥ Space (hold)")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("Hold the hotkey to record, release to transcribe and insert text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if AXIsProcessTrusted() {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                            AXIsProcessTrustedWithOptions(options)
                        }
                    }
                }
                Text("Required for global hotkeys and text insertion into other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aboutView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("OpenWhispr")
                .font(.title)
                .fontWeight(.bold)

            Text("On-device voice dictation for macOS")
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Powered by Qwen3-ASR-0.6B via MLX")
                Text("Uses soniqo/speech-swift")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

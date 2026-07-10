import SwiftUI
import AppKit

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

            dashboardSettings
                .tabItem { Label("Dashboard", systemImage: "chart.bar") }

            hotkeySettings
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }

            aboutView
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 470, height: 380)
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
                    } else if appState.isModelLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Downloading...", systemImage: "arrow.down.circle")
                            .foregroundStyle(.orange)
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

    private var dashboardSettings: some View {
        Form {
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

            Section("Sound Feedback") {
                Toggle("Play sounds when listening starts and stops", isOn: Binding(
                    get: { appState.soundFeedbackEnabled },
                    set: { appState.setSoundFeedbackEnabled($0) }
                ))
                Text("Soft chime on hold (listening) and release (stopped). The mic opens after the start sound so it is not recorded.")
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
                Text("Required so ⌥Space is swallowed (won’t type spaces), and for pasting into other apps. After granting, quit and reopen MacWispr.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aboutView: some View {
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

            Text("On-device voice dictation for macOS")
                .foregroundStyle(.secondary)

            Text("v1.1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)

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

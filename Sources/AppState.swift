import SwiftUI
import Combine

enum DictationMode: String, CaseIterable, Identifiable {
    case hold = "Hold"
    case toggle = "Toggle"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .hold:
            return "Hold ⌥Space (or the Hold button) while speaking; release to transcribe."
        case .toggle:
            return "Press ⌥Space (or Start) once to begin; press again to stop and transcribe."
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static private(set) var shared: AppState?

    @Published var isRecording = false
    @Published var isModelLoaded = false
    @Published var isModelLoading = false
    @Published var modelLoadProgress: Double = 0
    @Published var modelLoadStatus: String = ""
    @Published var currentTranscription: String = ""
    @Published var transcriptionHistory: [TranscriptionEntry] = []
    @Published var selectedLanguage: String? = nil
    @Published var insertionMode: InsertionMode = .clipboard
    @Published var removeFillerWords = true
    @Published var autoCapitalize = true
    @Published var soundFeedbackEnabled = true
    @Published var dictationMode: DictationMode = .hold
    @Published var typingWPM: Double = UsageStats.defaultTypingWPM

    let transcriptionEngine = TranscriptionEngine()
    let audioRecorder = AudioRecorder()
    let hotkeyManager = HotkeyManager()
    let textInserter = TextInserter()

    private var recordingSession = 0

    init() {
        AppState.shared = self
        transcriptionHistory = HistoryStore.load()
        if let savedWPM = UserDefaults.standard.object(forKey: "typingWPM") as? Double, savedWPM > 0 {
            typingWPM = savedWPM
        }
        if UserDefaults.standard.object(forKey: "soundFeedbackEnabled") != nil {
            soundFeedbackEnabled = UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")
        }
        if let raw = UserDefaults.standard.string(forKey: "dictationMode"),
           let mode = DictationMode(rawValue: raw)
        {
            dictationMode = mode
        }
        setupHotkey()
        Task { await loadModel() }
    }

    func loadModel() async {
        guard !isModelLoaded && !isModelLoading else { return }
        isModelLoading = true
        modelLoadStatus = "Downloading model..."

        do {
            let engine = transcriptionEngine
            try await Task.detached {
                try await engine.loadModel { progress, status in
                    DispatchQueue.main.async { [weak self] in
                        self?.modelLoadProgress = progress
                        self?.modelLoadStatus = status.isEmpty
                            ? "Downloading... \(Int(progress * 100))%"
                            : "\(status) (\(Int(progress * 100))%)"
                    }
                }
            }.value
            isModelLoaded = true
            modelLoadStatus = "Ready"
        } catch {
            modelLoadStatus = "Error: \(error.localizedDescription)"
        }
        isModelLoading = false
    }

    func setDictationMode(_ mode: DictationMode) {
        dictationMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "dictationMode")
    }

    // MARK: - Recording

    func startRecording() {
        guard isModelLoaded, !isRecording else { return }
        isRecording = true
        currentTranscription = ""
        recordingSession += 1
        let session = recordingSession

        if soundFeedbackEnabled {
            FeedbackSounds.playListeningStarted()
        }

        Task { @MainActor in
            if soundFeedbackEnabled {
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            guard isRecording, recordingSession == session else { return }
            audioRecorder.startRecording()
        }
    }

    func stopRecordingAndTranscribe() async {
        guard isRecording else { return }
        isRecording = false
        recordingSession += 1
        let samples = audioRecorder.stopRecording()

        if soundFeedbackEnabled {
            FeedbackSounds.playListeningStopped()
        }

        guard !samples.isEmpty else { return }

        do {
            let text = try await transcriptionEngine.transcribe(
                samples: samples,
                language: selectedLanguage
            )
            let processed = postProcess(text)
            currentTranscription = processed

            let duration = Double(samples.count) / 16000.0
            let entry = TranscriptionEntry(
                text: processed,
                timestamp: Date(),
                duration: duration,
                wordCount: UsageStats.wordCount(in: processed)
            )
            transcriptionHistory.insert(entry, at: 0)
            HistoryStore.save(transcriptionHistory)
            textInserter.insert(text: processed, mode: insertionMode)
        } catch {
            currentTranscription = "Error: \(error.localizedDescription)"
        }
    }

    /// Toggle mode: start if idle, stop+transcribe if listening.
    func toggleRecording() {
        if isRecording {
            Task { await stopRecordingAndTranscribe() }
        } else {
            startRecording()
        }
    }

    func setTypingWPM(_ value: Double) {
        typingWPM = max(10, min(120, value))
        UserDefaults.standard.set(typingWPM, forKey: "typingWPM")
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        soundFeedbackEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "soundFeedbackEnabled")
    }

    func clearHistory() {
        transcriptionHistory = []
        HistoryStore.save(transcriptionHistory)
    }

    private func postProcess(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if removeFillerWords {
            let fillers = ["uh", "um", "like", "you know", "I mean", "so", "actually", "basically", "right"]
            for filler in fillers {
                result = result.replacingOccurrences(
                    of: "\\b\(filler)\\b[,]?\\s*",
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            }
            while result.contains("  ") {
                result = result.replacingOccurrences(of: "  ", with: " ")
            }
        }

        if autoCapitalize && !result.isEmpty {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setupHotkey() {
        hotkeyManager.onHotkeyDown = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                switch self.dictationMode {
                case .hold:
                    self.startRecording()
                case .toggle:
                    self.toggleRecording()
                }
            }
        }
        hotkeyManager.onHotkeyUp = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Only hold-mode stops on release. Toggle ignores key-up.
                if self.dictationMode == .hold {
                    await self.stopRecordingAndTranscribe()
                }
            }
        }
        hotkeyManager.register()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager.ensureRegistered()
        }
    }
}

struct TranscriptionEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    let duration: Double
    let wordCount: Int

    init(id: UUID = UUID(), text: String, timestamp: Date, duration: Double, wordCount: Int? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.wordCount = wordCount ?? UsageStats.wordCount(in: text)
    }
}

enum InsertionMode: String, CaseIterable, Codable {
    case clipboard = "Copy to Clipboard"
    case typeOut = "Type into Active App"
    case both = "Both"
}

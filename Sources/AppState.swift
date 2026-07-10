import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    /// Process-wide instance so AppDelegate can open the dashboard without
    /// waiting on MenuBarExtra's onAppear (which only runs after first click).
    static private(set) var shared: AppState?

    @Published var isRecording = false
    @Published var isModelLoaded = false
    @Published var isModelLoading = false
    @Published var modelLoadProgress: Double = 0
    @Published var modelLoadStatus: String = ""
    @Published var currentTranscription: String = ""
    @Published var transcriptionHistory: [TranscriptionEntry] = []
    @Published var selectedLanguage: String? = nil // nil = auto-detect
    @Published var insertionMode: InsertionMode = .clipboard
    @Published var isStreamingEnabled = true
    @Published var removeFillerWords = true
    @Published var autoCapitalize = true
    /// Soft chime when hold-to-dictate starts / stops.
    @Published var soundFeedbackEnabled = true
    /// Baseline typing speed used for "time saved" estimates.
    @Published var typingWPM: Double = UsageStats.defaultTypingWPM

    let transcriptionEngine = TranscriptionEngine()
    let audioRecorder = AudioRecorder()
    let hotkeyManager = HotkeyManager()
    let textInserter = TextInserter()

    /// Bumps when recording is cancelled so a delayed mic-start is ignored.
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
        setupHotkey()
        // Auto-download model on launch
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

    func startRecording() {
        guard isModelLoaded, !isRecording else { return }
        isRecording = true
        currentTranscription = ""
        recordingSession += 1
        let session = recordingSession

        // Chime first, then open the mic after a short beat so the start
        // sound is not captured into the dictation audio.
        if soundFeedbackEnabled {
            FeedbackSounds.playListeningStarted()
        }

        Task { @MainActor in
            if soundFeedbackEnabled {
                try? await Task.sleep(nanoseconds: 90_000_000) // 90ms
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

        // Play after mic stops so the chime is not part of the transcript.
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

            // Insert text based on mode
            textInserter.insert(text: processed, mode: insertionMode)
        } catch {
            currentTranscription = "Error: \(error.localizedDescription)"
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
            // Clean up double spaces
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
                self?.startRecording()
            }
        }
        hotkeyManager.onHotkeyUp = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }
        hotkeyManager.register()

        // Accessibility may be granted after launch — re-create the event tap
        // so Space starts being swallowed without a full restart.
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

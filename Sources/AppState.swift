import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
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

    let transcriptionEngine = TranscriptionEngine()
    let audioRecorder = AudioRecorder()
    let hotkeyManager = HotkeyManager()
    let textInserter = TextInserter()

    init() {
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
        guard isModelLoaded else { return }
        isRecording = true
        currentTranscription = ""
        audioRecorder.startRecording()
    }

    func stopRecordingAndTranscribe() async {
        guard isRecording else { return }
        isRecording = false
        let samples = audioRecorder.stopRecording()

        guard !samples.isEmpty else { return }

        do {
            let text = try await transcriptionEngine.transcribe(
                samples: samples,
                language: selectedLanguage
            )
            let processed = postProcess(text)
            currentTranscription = processed

            let entry = TranscriptionEntry(
                text: processed,
                timestamp: Date(),
                duration: Double(samples.count) / 16000.0
            )
            transcriptionHistory.insert(entry, at: 0)

            // Insert text based on mode
            textInserter.insert(text: processed, mode: insertionMode)
        } catch {
            currentTranscription = "Error: \(error.localizedDescription)"
        }
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
    }
}

struct TranscriptionEntry: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let duration: Double
}

enum InsertionMode: String, CaseIterable {
    case clipboard = "Copy to Clipboard"
    case typeOut = "Type into Active App"
    case both = "Both"
}

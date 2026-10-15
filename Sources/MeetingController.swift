import AVFoundation
import AppKit
import MacWisprCore

/// Records meetings (microphone + audio from other apps), then transcribes them
/// on-device and saves audio + transcript under Application Support/MacWispr/Meetings.
@MainActor
@Observable
final class MeetingController {
    enum Phase: Equatable {
        case idle
        case recording
        case processing(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var meetings: [MeetingMetadata] = []
    private(set) var elapsedLabel = "0:00"
    private(set) var micLevel: Float = 0
    private(set) var systemLevel: Float = 0
    var lastError: String?

    var recordMicrophone: Bool {
        didSet { UserDefaults.standard.set(recordMicrophone, forKey: Self.micKey) }
    }
    var recordSystemAudio: Bool {
        didSet { UserDefaults.standard.set(recordSystemAudio, forKey: Self.systemKey) }
    }

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { phase != .idle }

    static var systemAudioSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored let paths = MacWisprPaths.default
    @ObservationIgnored private var current: MeetingMetadata?
    @ObservationIgnored private var micSink: MeetingTrackSink?
    @ObservationIgnored private var systemSink: MeetingTrackSink?
    @ObservationIgnored private var micCapture: MeetingMicCapture?
    @ObservationIgnored private var systemCapture: AnyObject?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pendingQueue: [String] = []
    @ObservationIgnored private var isDraining = false

    private static let micKey = "meetingRecordMicrophone"
    private static let systemKey = "meetingRecordSystemAudio"

    init() {
        let d = UserDefaults.standard
        recordMicrophone = d.object(forKey: Self.micKey) as? Bool ?? true
        recordSystemAudio = (d.object(forKey: Self.systemKey) as? Bool ?? true) && Self.systemAudioSupported
    }

    func attach(_ state: AppState) {
        appState = state
        try? FileManager.default.createDirectory(at: paths.meetingsDir, withIntermediateDirectories: true)
        writeAgentsReadme()
        markInterruptedMeetings()
        reload()
    }

    func reload() {
        meetings = AgentDataStore(paths: paths).meetings()
    }

    // MARK: Recording

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    /// Allowed while an earlier meeting is still being transcribed.
    func start() {
        guard !isRecording else { return }
        lastError = nil
        guard recordMicrophone || recordSystemAudio else {
            lastError = "Turn on the microphone, other apps' audio, or both."
            return
        }
        let now = Date()
        var meta = MeetingMetadata(
            id: MeetingMetadata.makeID(for: now),
            title: MeetingMetadata.defaultTitle(for: now),
            startedAt: now,
            recordMicrophone: recordMicrophone,
            recordSystemAudio: recordSystemAudio
        )
        let dir = paths.meetingDir(id: meta.id)
        var warnings: [String] = []
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if recordMicrophone {
                let sink = try MeetingTrackSink(url: dir.appendingPathComponent(MeetingFiles.micPCM), startedAt: now)
                let cap = MeetingMicCapture()
                do {
                    try cap.start(deviceUID: appState?.selectedInputDeviceUID, sink: sink)
                    micSink = sink
                    micCapture = cap
                } catch {
                    sink.close()
                    try? FileManager.default.removeItem(at: sink.writer.url)
                    meta.recordMicrophone = false
                    warnings.append("Microphone: \(error.localizedDescription)")
                }
            }
            if recordSystemAudio, #available(macOS 14.2, *) {
                let sink = try MeetingTrackSink(url: dir.appendingPathComponent(MeetingFiles.systemPCM), startedAt: now)
                let cap = SystemAudioCapture()
                do {
                    try cap.start(sink: sink)
                    systemSink = sink
                    systemCapture = cap
                } catch {
                    sink.close()
                    try? FileManager.default.removeItem(at: sink.writer.url)
                    meta.recordSystemAudio = false
                    warnings.append("Other apps' audio: \(error.localizedDescription)")
                }
            }
        } catch {
            lastError = "Could not start recording: \(error.localizedDescription)"
            teardownCapture()
            try? FileManager.default.removeItem(at: dir)
            return
        }
        guard micSink != nil || systemSink != nil else {
            lastError = warnings.joined(separator: "\n")
            try? FileManager.default.removeItem(at: dir)
            return
        }
        meta.warnings = warnings.isEmpty ? nil : warnings
        lastError = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        current = meta
        save(meta)
        phase = .recording
        elapsedLabel = "0:00"
        startTimer()
        if appState?.soundFeedbackEnabled == true { FeedbackSounds.playListeningStarted() }
        reload()
    }

    func stop() {
        guard phase == .recording, var meta = current else { return }
        stopTimer()
        let micPeak = micSink?.peakLevel ?? 0
        let systemPeak = systemSink?.peakLevel ?? 0
        teardownCapture()
        if appState?.soundFeedbackEnabled == true { FeedbackSounds.playListeningStopped() }
        meta.endedAt = Date()
        meta.durationSeconds = meta.endedAt!.timeIntervalSince(meta.startedAt)
        meta.status = .processing
        var warnings = meta.warnings ?? []
        if meta.recordSystemAudio, systemPeak == 0 {
            warnings.append("Other apps' audio was completely silent. If a call was playing, allow MacWispr in System Settings → Privacy & Security → Screen & System Audio Recording.")
        }
        if meta.recordMicrophone, micPeak == 0 {
            warnings.append("The microphone was completely silent. Check MacWispr's Microphone permission.")
        }
        meta.warnings = warnings.isEmpty ? nil : warnings
        save(meta)
        current = nil
        phase = .idle
        enqueueProcessing(meta.id)
    }

    private func teardownCapture() {
        micCapture?.stop()
        if #available(macOS 14.2, *) { (systemCapture as? SystemAudioCapture)?.stop() }
        micSink?.close()
        systemSink?.close()
        micCapture = nil
        systemCapture = nil
        micSink = nil
        systemSink = nil
        micLevel = 0
        systemLevel = 0
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let meta = current else { return }
        let label = UsageClock.format(seconds: Date().timeIntervalSince(meta.startedAt))
        if label != elapsedLabel { elapsedLabel = label }
        micLevel = micSink?.currentLevel ?? 0
        systemLevel = systemSink?.currentLevel ?? 0
    }

    // MARK: Processing

    /// Transcribes (again) a meeting whose raw audio is still on disk.
    func reprocess(id: String) {
        guard !pendingQueue.contains(id), meetings.contains(where: { $0.id == id }) else { return }
        enqueueProcessing(id)
    }

    func canReprocess(_ meta: MeetingMetadata) -> Bool {
        guard meta.status != .recording, meta.status != .processing else { return false }
        let dir = paths.meetingDir(id: meta.id)
        let fm = FileManager.default
        return [MeetingFiles.micPCM, MeetingFiles.systemPCM, MeetingFiles.micAudio, MeetingFiles.systemAudio]
            .contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    private func enqueueProcessing(_ id: String) {
        pendingQueue.append(id)
        if phase != .recording { phase = .processing("Waiting…") }
        guard !isDraining else { return }
        isDraining = true
        Task { await drainQueue() }
    }

    private func drainQueue() async {
        while let id = pendingQueue.first {
            await process(id: id)
            pendingQueue.removeFirst()
        }
        isDraining = false
        if phase != .recording { phase = .idle }
    }

    private func setProcessing(_ text: String) {
        // A new recording can start while an older one is processed; recording wins the label.
        if phase != .recording { phase = .processing(text) }
    }

    private func process(id: String) async {
        let store = AgentDataStore(paths: paths)
        guard var meta = store.meeting(id: id), let state = appState else { return }
        let dir = paths.meetingDir(id: id)
        meta.status = .processing
        meta.error = nil
        save(meta)
        reload()
        setProcessing("Loading speech model…")

        guard await state.beginMeetingTranscription() else {
            meta.status = .failed
            meta.error = "Speech model is not available: \(state.modelLoadStatus)"
            save(meta)
            reload()
            state.endMeetingTranscription()
            return
        }
        defer { state.endMeetingTranscription() }
        meta.model = ModelCatalog.shippedDisplayName

        do {
            var tracks: [(MeetingSource, URL)] = []
            for source in [MeetingSource.microphone, .system] {
                if let pcm = try ensurePCM(source: source, dir: dir) { tracks.append((source, pcm)) }
            }
            var segments: [MeetingSegment] = []
            let engine = state.transcriptionEngine
            for (source, url) in tracks {
                let reader = try PCM16FileReader(url: url)
                let regions = MeetingSegmenter.regions(
                    levels: MeetingSegmenter.frameLevels(reader),
                    totalSamples: reader.sampleCount
                )
                let label = source == .microphone ? "microphone" : "other apps"
                for (i, r) in regions.enumerated() {
                    setProcessing("Transcribing \(label) \(i + 1)/\(regions.count)…")
                    let samples = reader.read(start: r.lowerBound, count: r.count)
                    let text = try await engine.transcribe(samples: samples)
                    segments.append(MeetingSegment(
                        start: Double(r.lowerBound) / 16_000,
                        end: Double(r.upperBound) / 16_000,
                        source: source,
                        text: text
                    ))
                }
            }
            let merged = MeetingMerge.merge(segments)
            let transcript = MeetingTranscript(segments: merged)
            meta.segmentCount = merged.count
            meta.wordCount = merged.reduce(0) { $0 + UsageStats.wordCount(in: $1.text) }
            try AgentDataStore.makeEncoder().encode(transcript).write(to: dir.appendingPathComponent(MeetingFiles.transcriptJSON), options: .atomic)
            try MeetingTranscriptFormatter.markdown(meta: meta, transcript: transcript)
                .write(to: dir.appendingPathComponent(MeetingFiles.transcriptMarkdown), atomically: true, encoding: .utf8)

            setProcessing("Saving audio…")
            try await Task.detached(priority: .utility) {
                try MeetingAudioExport.export(dir: dir, tracks: tracks)
            }.value
            meta.status = .done
        } catch {
            meta.status = .failed
            meta.error = error.localizedDescription
            NSLog("MacWispr: meeting %@ processing failed: %@", id, error.localizedDescription)
        }
        save(meta)
        reload()
    }

    /// Raw PCM for a track; decodes the saved .m4a when re-transcribing a finished meeting.
    private func ensurePCM(source: MeetingSource, dir: URL) throws -> URL? {
        let pcm = dir.appendingPathComponent(MeetingFiles.pcm(source))
        let fm = FileManager.default
        if fm.fileExists(atPath: pcm.path) { return pcm }
        let m4a = dir.appendingPathComponent(MeetingFiles.audio(source))
        guard fm.fileExists(atPath: m4a.path) else { return nil }
        let samples = try HeadlessTranscribe.loadMono16k(m4a.path)
        try PCMCodec.int16Data(from: samples).write(to: pcm)
        return pcm
    }

    // MARK: Files

    func rename(id: String, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, var meta = AgentDataStore(paths: paths).meeting(id: id) else { return }
        meta.title = t
        save(meta)
        let dir = paths.meetingDir(id: id)
        let store = AgentDataStore(paths: paths)
        if let transcript = store.transcript(id: id) {
            try? MeetingTranscriptFormatter.markdown(meta: meta, transcript: transcript)
                .write(to: dir.appendingPathComponent(MeetingFiles.transcriptMarkdown), atomically: true, encoding: .utf8)
        }
        reload()
    }

    func delete(id: String) {
        guard current?.id != id, !pendingQueue.contains(id) else { return }
        try? FileManager.default.trashItem(at: paths.meetingDir(id: id), resultingItemURL: nil)
        reload()
    }

    func folderURL(id: String) -> URL { paths.meetingDir(id: id) }

    func file(_ name: String, id: String) -> URL? {
        let url = paths.meetingDir(id: id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func save(_ meta: MeetingMetadata) {
        let url = paths.meetingDir(id: meta.id).appendingPathComponent(MeetingFiles.metadata)
        if let data = try? AgentDataStore.makeEncoder().encode(meta) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The app quit mid-recording or mid-processing: keep the audio, flag the meeting.
    private func markInterruptedMeetings() {
        for var meta in AgentDataStore(paths: paths).meetings() where meta.status == .recording || meta.status == .processing {
            meta.status = .interrupted
            if meta.endedAt == nil {
                let dir = paths.meetingDir(id: meta.id)
                let samples = [MeetingFiles.micPCM, MeetingFiles.systemPCM].compactMap {
                    try? PCM16FileReader(url: dir.appendingPathComponent($0)).sampleCount
                }.max() ?? 0
                meta.durationSeconds = Double(samples) / 16_000
                meta.endedAt = meta.startedAt.addingTimeInterval(meta.durationSeconds)
            }
            save(meta)
        }
    }

    /// Stops capture cleanly on quit so the PCM files are complete.
    func prepareForTermination() {
        guard isRecording, var meta = current else { return }
        stopTimer()
        teardownCapture()
        meta.endedAt = Date()
        meta.durationSeconds = meta.endedAt!.timeIntervalSince(meta.startedAt)
        meta.status = .interrupted
        save(meta)
    }

    // MARK: Agent access

    /// `macwispr` CLI bundled in the app, or the dev build next to the app binary.
    var cliURL: URL? {
        let fm = FileManager.default
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/macwispr"),
            // `swift build` names the dev binary after its target.
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("MacWisprCLI"),
        ].compactMap { $0 }
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    static let cliLinkURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/macwispr")

    var isCLIInstalled: Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: Self.cliLinkURL.path) else { return false }
        return target == cliURL?.path
    }

    /// Symlinks the CLI into ~/.local/bin (no admin password needed).
    func installCLI() throws {
        guard let cli = cliURL else { throw MeetingCaptureError.message("The macwispr tool is missing from this build.") }
        let fm = FileManager.default
        try fm.createDirectory(at: Self.cliLinkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? fm.destinationOfSymbolicLink(atPath: Self.cliLinkURL.path)) != nil || fm.fileExists(atPath: Self.cliLinkURL.path) {
            try fm.removeItem(at: Self.cliLinkURL)
        }
        try fm.createSymbolicLink(at: Self.cliLinkURL, withDestinationURL: cli)
    }

    var mcpConfigJSON: String {
        let cmd = cliURL?.path ?? "/Applications/MacWispr.app/Contents/Helpers/macwispr"
        return """
        {
          "mcpServers": {
            "macwispr": { "command": "\(cmd)", "args": ["mcp"] }
          }
        }
        """
    }

    private func writeAgentsReadme() {
        let text = AgentDataReadme.content(paths: paths, cliPath: cliURL?.path)
        try? text.write(to: paths.agentsReadme, atomically: true, encoding: .utf8)
    }
}

/// Encodes the raw PCM tracks to AAC .m4a (each side + a mix) and removes the PCM.
enum MeetingAudioExport {
    static func export(dir: URL, tracks: [(MeetingSource, URL)]) throws {
        guard !tracks.isEmpty else { return }
        let readers = try tracks.map { ($0.0, try PCM16FileReader(url: $0.1)) }
        for (source, reader) in readers {
            try encode(to: dir.appendingPathComponent(MeetingFiles.audio(source)), length: reader.sampleCount) { start, count in
                reader.read(start: start, count: count)
            }
        }
        let length = readers.map(\.1.sampleCount).max() ?? 0
        try encode(to: dir.appendingPathComponent(MeetingFiles.mixedAudio), length: length) { start, count in
            var mix = [Float](repeating: 0, count: count)
            for (_, r) in readers {
                let part = r.read(start: start, count: count)
                for i in 0..<part.count { mix[i] += part[i] }
            }
            for i in 0..<mix.count { mix[i] = max(-1, min(1, mix[i])) }
            return mix
        }
        for (_, url) in tracks { try? FileManager.default.removeItem(at: url) }
    }

    private static func encode(to url: URL, length: Int, block: (Int, Int) -> [Float]) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 16_000 * 10
        var start = 0
        while start < length {
            let samples = block(start, min(chunk, length - start))
            guard !samples.isEmpty,
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count))
            else { break }
            buf.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
            try file.write(from: buf)
            start += samples.count
        }
    }
}

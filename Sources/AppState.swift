import SwiftUI
import Combine
import AVFoundation
import AppKit

enum DictationMode: String, CaseIterable, Identifiable {
    case hold = "Hold"
    case toggle = "Toggle"

    var id: String { rawValue }

    /// Coarse telemetry token (hold / toggle) — never free-form.
    var telemetryValue: String {
        switch self {
        case .hold: return "hold"
        case .toggle: return "toggle"
        }
    }

    var help: String {
        switch self {
        case .hold:
            return "Hold the dictation hotkey while speaking; release to transcribe."
        case .toggle:
            return "Press the dictation hotkey once to begin; press again to stop and transcribe."
        }
    }
}

/// Eyes-free pipeline state for menu bar, HUD, and sounds.
enum DictationPhase: Equatable {
    case setup
    case ready
    case listening
    case transcribing
    case success
    case failed

    var isBusy: Bool {
        switch self {
        case .listening, .transcribing: return true
        default: return false
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
    /// Qwen size; RAM-aware default applied in `init` when no preference is saved.
    @Published var asrModelSize: ASRModelSize = ASRModelSize.recommendedDefault
    @Published var transcriptionProvider: TranscriptionProvider = .local
    @Published var polishProvider: PolishProvider = .off
    @Published var polishLocalModel: PolishLocalModel = .miniCPM
    /// Models → AI Models: when false, polish packs stay hidden (SuperWhisper-style).
    @Published var showExperimentalAIModels = false
    /// Opt-in local debug: save WAV + raw/polished text under Application Support.
    @Published var devCaptureEnabled: Bool = false
    /// Keychain presence flags (never store the raw secrets in @Published).
    @Published var hasOpenAIKey = false
    @Published var hasElevenLabsKey = false
    @Published var openAIKeyMasked: String = ""
    @Published var elevenLabsKeyMasked: String = ""
    @Published var currentTranscription: String = ""
    @Published var transcriptionHistory: [TranscriptionEntry] = []
    @Published var selectedLanguage: String? = nil
    @Published var insertionMode: InsertionMode = .both
    /// Light first-letter capitalize only — no hardcoded filler/word lists (polish model owns cleanup).
    @Published var autoCapitalize = true
    /// Legacy flag kept in sync with polishProvider == .local for older UI bindings.
    @Published var llmPolishEnabled = false
    @Published var isLLMLoaded = false
    @Published var isLLMLoading = false
    @Published var llmLoadStatus: String = ""
    /// 0…1 while downloading / loading the local polish pack (Settings progress).
    @Published var llmLoadProgress: Double = 0
    /// True when Application Support (or bundle/env) has complete polish weights.
    @Published var isPolishModelOnDisk: Bool = PolishLocalModel.miniCPM.isAvailable
    @Published var soundFeedbackEnabled = true
    /// Default output is muted / volume ~0 — chimes will be silent until unmuted.
    @Published var outputMuted = false
    /// 0…1 feedback chime level (settings slider).
    @Published var feedbackSoundVolume: Double = FeedbackSoundPreferences.volume
    @Published var startChime: SystemChime = FeedbackSoundPreferences.startChime
    @Published var stopChime: SystemChime = FeedbackSoundPreferences.stopChime
    @Published var successChime: SystemChime = FeedbackSoundPreferences.successChime
    @Published var failureChime: SystemChime = FeedbackSoundPreferences.failureChime
    @Published var dictationMode: DictationMode = .hold
    /// Global dictation chord (default ⌥Space). Click-to-record in Configuration.
    @Published var dictationHotkey: KeyChord = .defaultDictation
    /// Discard in-progress listening without pasting (default Esc).
    @Published var cancelHotkey: KeyChord = .defaultCancel
    @Published var typingWPM: Double = UsageStats.defaultTypingWPM
    /// Custom vocabulary / domain terms fed to Qwen3-ASR as system context.
    @Published var customVocabulary: [String] = []
    /// Reflects HotkeyManager.isArmed so the menu bar can reactively show Fix.
    @Published var hotkeyArmed = false
    /// AXIsProcessTrusted() polled with hotkey health.
    @Published var accessibilityTrusted = false
    /// Privacy Settings: share anonymous usage data (default OFF).
    @Published var telemetryOptIn = false
    /// First-run (or first Settings visit) disclosure sheet for telemetry.
    @Published var showTelemetryDisclosure = false
    /// Privacy Settings: appear on the public website leaderboard (default OFF).
    /// Identity is anonymous only — never linked to telemetry install ID.
    @Published var leaderboardOptIn = false
    /// Server-derived label (e.g. "Anonymous Otter · a1f2") after first sync.
    @Published var leaderboardDisplayName: String = ""
    /// Public rank (#1 = top). Nil when opted out or not yet synced.
    @Published var leaderboardRank: Int? = nil
    /// Short label for Home UI (e.g. "Otter · a1f2").
    @Published var leaderboardShortName: String = ""
    /// Animal token for cute avatar (e.g. "Otter").
    @Published var leaderboardAnimal: String = ""
    /// Stable avatar art key (non-identifying).
    @Published var leaderboardAvatarKey: String = ""
    /// Last known aggregates from board sync (for Home chips).
    @Published var leaderboardRemoteStats: LeaderboardStats = .zero
    /// True when the board shows a user-chosen competitive name.
    @Published var leaderboardIsCustomName = false
    /// Draft public name (empty = anonymous animal). Synced when opted in.
    @Published var leaderboardPublicNameDraft: String = ""
    /// Human message if the chosen name was rejected (taken / invalid).
    @Published var leaderboardNameError: String? = nil
    /// Pipeline phase for menu bar / HUD (Ready → Listening → Transcribing → Done/Fail).
    @Published var dictationPhase: DictationPhase = .setup
    /// Short human label for the current phase (tooltips, HUD).
    @Published var phaseDetail: String = ""
    /// Seconds since listening started (updates while recording).
    @Published var recordingElapsed: TimeInterval = 0
    /// Clean last transcript (no ⚠️ suffixes) for Copy / Re-paste.
    @Published var lastCleanTranscription: String = ""
    /// Transient failure banner (AX, empty mic, STT) — not mixed into history text.
    @Published var lastFailureMessage: String? = nil
    /// Show a simple floating banner under the menu bar while dictating.
    /// (Not a Dynamic Island — plain app UI, easy to see.)
    /// Prefer `recordingWindowStyle`; this stays in sync for older call sites.
    @Published var listeningHUDEnabled = true
    /// SuperWhisper-style: Classic (live draft) / Mini (timer) / None (off).
    @Published var recordingWindowStyle: RecordingWindowStyle = .classic
    /// Liquid Glass look for the floating recording window (Clear / Tinted).
    @Published var liquidGlassStyle: LiquidGlassStyle = .clear
    /// Live draft while mic is open (only applies when recording window is Classic).
    @Published var livePartialsEnabled = true
    /// First-run setup checklist until the user dismisses it.
    @Published var showOnboarding = false
    /// Connected microphones (refreshed when Settings opens).
    @Published var availableInputDevices: [AudioInputDevice] = []
    /// Core Audio UID; empty string = follow macOS system default.
    @Published var selectedInputDeviceUID: String = ""

    let transcriptionEngine = TranscriptionEngine()
    let textPolisher = TextPolisher()
    let audioRecorder = AudioRecorder()
    let hotkeyManager = HotkeyManager()
    let textInserter = TextInserter()

    private var recordingSession = 0
    private var hotkeyHealthTimer: Timer?
    private var recordingElapsedTimer: Timer?
    private var recordingStartedAt: Date?
    private var phaseResetTask: Task<Void, Never>?
    /// Current health-timer interval (shorter while unarmed so we recover quickly).
    private var hotkeyHealthInterval: TimeInterval = 2.0
    private static let hotkeyHealthIntervalUnarmed: TimeInterval = 2.0
    private static let hotkeyHealthIntervalArmed: TimeInterval = 8.0
    /// History id for the latest dictation (so Dictate edits update the same row).
    private var lastTranscriptionId: UUID?
    /// Bumped when starting a local load or leaving `.local` so a finishing
    /// mid-load progress cannot stomp cloud readiness / UI flags.
    private var modelLoadGeneration = 0
    /// Debounced history persistence — avoids rewriting history.json every dictation.
    private var historySaveTask: Task<Void, Never>?
    /// Live partial ASR while the mic is open (local Qwen + Parakeet).
    private var livePartialTask: Task<Void, Never>?
    /// Prevents overlapping live ASR calls on the engine actor.
    private var livePartialInFlight = false
    /// PCM sample count that produced the last accepted live draft (for release fast-path).
    private var lastLivePartialSampleCount = 0
    private static let historySaveDebounceNs: UInt64 = 750_000_000 // 0.75s
    /// How often to re-transcribe the growing buffer while listening.
    private static let livePartialIntervalNs: UInt64 = 1_100_000_000 // 1.1s
    /// Wait for at least this much audio before first live pass.
    private static let livePartialMinSamples = 16_000 // 1.0s @ 16 kHz
    /// If less audio than this arrived after the last live draft, paste the draft
    /// instead of re-running a full STT pass (avoids 2–3s “finalizing” lag).
    private static let liveDraftReuseMaxNewSamples = 12_000 // 0.75s @ 16 kHz
    /// Max time to wait for an in-flight live pass to finish on release.
    private static let livePartialDrainTimeoutNs: UInt64 = 1_500_000_000 // 1.5s
    private static let customVocabularyKey = "customVocabulary"
    private static let asrModelSizeKey = "asrModelSize"
    private static let transcriptionProviderKey = "transcriptionProvider"
    private static let polishProviderKey = "polishProvider"
    private static let polishLocalModelKey = "polishLocalModel"
    private static let showExperimentalAIModelsKey = "showExperimentalAIModels"
    private static let dictationHotkeyKey = "dictationHotkey"
    private static let cancelHotkeyKey = "cancelHotkey"
    private static let listeningHUDKey = "listeningHUDEnabled"
    private static let recordingWindowStyleKey = "recordingWindowStyle"
    private static let liquidGlassStyleKey = "liquidGlassStyle"
    private static let livePartialsEnabledKey = "livePartialsEnabled"
    private static let onboardingCompletedKey = "hasCompletedOnboarding"
    private static let inputDeviceUIDKey = "inputDeviceUID"

    /// Ready to accept mic input for the active transcription provider.
    var isReadyToDictate: Bool {
        switch transcriptionProvider {
        case .local:
            return isModelLoaded
        case .openAI:
            return hasOpenAIKey
        case .elevenLabs:
            return hasElevenLabsKey
        }
    }

    var readinessLabel: String {
        switch transcriptionProvider {
        case .local:
            if isModelLoaded { return "Ready · Local" }
            if isModelLoading { return modelLoadStatus.isEmpty ? "Loading model…" : modelLoadStatus }
            return modelLoadStatus.hasPrefix("Error") ? modelLoadStatus : "Model not loaded"
        case .openAI:
            return hasOpenAIKey ? "Ready · OpenAI" : "Add OpenAI API key"
        case .elevenLabs:
            return hasElevenLabsKey ? "Ready · ElevenLabs" : "Add ElevenLabs API key"
        }
    }

    /// Formatted m:ss for listening elapsed time (menu / copy).
    var recordingElapsedLabel: String {
        recordingElapsedFixedLabel
    }

    /// Always `m:ss` with monospaced width intent (HUD uses fixed frame).
    var recordingElapsedFixedLabel: String {
        let t = max(0, Int(recordingElapsed))
        let m = t / 60
        let s = t % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Human-readable STT latency for the “Done” banner / menu bar.
    /// Under 1s → milliseconds; otherwise one decimal second.
    static func formatSTTLatency(_ seconds: TimeInterval) -> String {
        let t = max(0, seconds)
        if t < 1.0 {
            return "\(Int((t * 1000).rounded())) ms"
        }
        if t < 10.0 {
            return String(format: "%.1f s", t)
        }
        return "\(Int(t.rounded())) s"
    }

    static func formatSuccessDetail(words: Int, sttLatency: TimeInterval) -> String {
        let latency = formatSTTLatency(sttLatency)
        if words > 0 {
            return "\(words)w · \(latency)"
        }
        return latency
    }

    /// Mic granted (or not yet determined counts as pending setup).
    var microphoneAuthorized: Bool {
        if #available(macOS 14.0, *) {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            return status == .authorized
        }
        return true
    }

    var needsSetup: Bool {
        !isReadyToDictate || !accessibilityTrusted || !hotkeyArmed
    }

    init() {
        AppState.shared = self
        transcriptionHistory = HistoryStore.load()
        if let savedWPM = UserDefaults.standard.object(forKey: "typingWPM") as? Double, savedWPM > 0 {
            typingWPM = savedWPM
        }
        if UserDefaults.standard.object(forKey: "soundFeedbackEnabled") != nil {
            soundFeedbackEnabled = UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")
        }
        feedbackSoundVolume = FeedbackSoundPreferences.volume
        startChime = FeedbackSoundPreferences.startChime
        stopChime = FeedbackSoundPreferences.stopChime
        successChime = FeedbackSoundPreferences.successChime
        failureChime = FeedbackSoundPreferences.failureChime
        // Recording window: Classic / Mini / None (SuperWhisper-style).
        // Migrate legacy listeningHUDEnabled boolean if style key missing.
        if let raw = UserDefaults.standard.string(forKey: Self.recordingWindowStyleKey),
           let style = RecordingWindowStyle(rawValue: raw)
        {
            recordingWindowStyle = style
        } else if UserDefaults.standard.object(forKey: Self.listeningHUDKey) != nil,
                  !UserDefaults.standard.bool(forKey: Self.listeningHUDKey)
        {
            recordingWindowStyle = .none
        } else {
            recordingWindowStyle = .classic
        }
        listeningHUDEnabled = recordingWindowStyle != .none
        UserDefaults.standard.set(recordingWindowStyle.rawValue, forKey: Self.recordingWindowStyleKey)
        UserDefaults.standard.set(listeningHUDEnabled, forKey: Self.listeningHUDKey)

        if let raw = UserDefaults.standard.string(forKey: Self.liquidGlassStyleKey),
           let glass = LiquidGlassStyle(rawValue: raw)
        {
            liquidGlassStyle = glass
        } else {
            liquidGlassStyle = .clear
        }

        if UserDefaults.standard.object(forKey: Self.livePartialsEnabledKey) != nil {
            livePartialsEnabled = UserDefaults.standard.bool(forKey: Self.livePartialsEnabledKey)
        } else {
            livePartialsEnabled = true
        }
        refreshOutputMuteState()
        if let raw = UserDefaults.standard.string(forKey: "insertionMode"),
           let mode = InsertionMode(rawValue: raw)
        {
            insertionMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: "dictationMode"),
           let mode = DictationMode(rawValue: raw)
        {
            dictationMode = mode
        }
        if let data = UserDefaults.standard.data(forKey: Self.dictationHotkeyKey),
           let chord = try? JSONDecoder().decode(KeyChord.self, from: data)
        {
            dictationHotkey = chord
        } else {
            dictationHotkey = .defaultDictation
        }
        if let data = UserDefaults.standard.data(forKey: Self.cancelHotkeyKey),
           let chord = try? JSONDecoder().decode(KeyChord.self, from: data)
        {
            cancelHotkey = chord
        } else {
            cancelHotkey = .defaultCancel
        }
        if let raw = UserDefaults.standard.string(forKey: Self.asrModelSizeKey),
           let size = ASRModelSize(rawValue: raw)
        {
            // Legacy Parakeet-INT4 picker value → single INT8 fixed-shape model.
            if size == .parakeetInt4 {
                asrModelSize = .parakeetInt8
                UserDefaults.standard.set(asrModelSize.rawValue, forKey: Self.asrModelSizeKey)
            } else {
                asrModelSize = size
            }
        } else {
            // First run / no saved choice: 1.7B when RAM > 16 GB, else 0.6B.
            asrModelSize = ASRModelSize.recommendedDefault
            UserDefaults.standard.set(asrModelSize.rawValue, forKey: Self.asrModelSizeKey)
        }
        if let raw = UserDefaults.standard.string(forKey: Self.transcriptionProviderKey),
           let provider = TranscriptionProvider(rawValue: raw)
        {
            transcriptionProvider = provider
        }
        // Polish is Off by default. Only restore a saved choice; never auto-enable.
        // Legacy: llmPolishEnabled=true alone used to imply Local — keep that one-time
        // migration so upgrades don't surprise people who already opted in.
        if let raw = UserDefaults.standard.string(forKey: Self.polishProviderKey),
           let polish = PolishProvider(rawValue: raw)
        {
            polishProvider = polish
        } else if UserDefaults.standard.object(forKey: "llmPolishEnabled") != nil,
                  UserDefaults.standard.bool(forKey: "llmPolishEnabled")
        {
            polishProvider = .local
            UserDefaults.standard.set(PolishProvider.local.rawValue, forKey: Self.polishProviderKey)
        } else {
            polishProvider = .off
            // Persist Off so Settings shows the product default on first run.
            if UserDefaults.standard.string(forKey: Self.polishProviderKey) == nil {
                UserDefaults.standard.set(PolishProvider.off.rawValue, forKey: Self.polishProviderKey)
            }
        }
        llmPolishEnabled = polishProvider == .local

        if let raw = UserDefaults.standard.string(forKey: Self.polishLocalModelKey),
           let m = PolishLocalModel(rawValue: raw),
           m.isSelectable
        {
            polishLocalModel = m
        } else {
            polishLocalModel = .miniCPM
        }
        TextPolisher.setModelPreference(polishLocalModel)
        isPolishModelOnDisk = polishLocalModel.isAvailable

        // Experimental AI (polish) list — default hidden. Auto-show if polish is already on.
        if UserDefaults.standard.object(forKey: Self.showExperimentalAIModelsKey) != nil {
            showExperimentalAIModels = UserDefaults.standard.bool(forKey: Self.showExperimentalAIModelsKey)
        } else {
            showExperimentalAIModels = polishProvider != .off
        }
        if let saved = UserDefaults.standard.stringArray(forKey: Self.customVocabularyKey) {
            customVocabulary = saved
        }
        telemetryOptIn = Telemetry.shared.isOptedIn
        leaderboardOptIn = LeaderboardClient.shared.isOptedIn
        leaderboardPublicNameDraft = LeaderboardClient.shared.publicName
        applyLeaderboardStanding(LeaderboardClient.shared.standing)
        LeaderboardClient.shared.onStandingChanged = { [weak self] standing in
            self?.applyLeaderboardStanding(standing)
        }
        // Dev capture: UserDefaults, or force-on via MACWISPR_DEV_CAPTURE=1.
        devCaptureEnabled = DevCaptureStore.isEnabled
        // First-run disclosure: show once until the user acknowledges the manifest.
        if !Telemetry.shared.hasSeenDisclosure {
            showTelemetryDisclosure = true
        }
        showOnboarding = !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
        if let savedInputUID = UserDefaults.standard.string(forKey: Self.inputDeviceUIDKey) {
            selectedInputDeviceUID = savedInputUID
        }
        syncAudioInputDevice()
        refreshInputDevices()
        refreshKeyPresence()
        syncIdlePhase()
        setupHotkey()
        Task { await prepareActiveProvider() }
        if polishProvider == .local {
            Task { await loadLLM() }
        }
        // After hotkey registration settles, emit the first hotkey_health snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.emitHotkeyHealthIfNeeded()
            self?.syncIdlePhase()
            self?.syncLeaderboardIfNeeded(force: false)
        }
    }

    // MARK: - Telemetry opt-in (#7)

    func setDevCaptureEnabled(_ enabled: Bool) {
        devCaptureEnabled = enabled
        DevCaptureStore.setEnabled(enabled)
        // Keep published flag in sync if env forced true (still allow UI to reflect store).
        if ProcessInfo.processInfo.environment["MACWISPR_DEV_CAPTURE"] == "1" {
            devCaptureEnabled = true
        }
    }

    func setTelemetryOptIn(_ enabled: Bool) {
        Telemetry.shared.setOptIn(enabled)
        telemetryOptIn = Telemetry.shared.isOptedIn
        if enabled {
            emitHotkeyHealthIfNeeded()
        }
    }

    func acknowledgeTelemetryDisclosure(optIn: Bool) {
        Telemetry.shared.markDisclosureSeen()
        showTelemetryDisclosure = false
        setTelemetryOptIn(optIn)
    }

    /// Opt into the public website leaderboard. Separate from reliability telemetry.
    /// You appear only as an anonymous animal name — no real identity is sent.
    func setLeaderboardOptIn(_ enabled: Bool) {
        LeaderboardClient.shared.setOptIn(enabled) { [weak self] in
            self?.currentLeaderboardStats() ?? .zero
        }
        leaderboardOptIn = LeaderboardClient.shared.isOptedIn
        if enabled {
            applyLeaderboardStanding(LeaderboardClient.shared.standing)
        } else {
            applyLeaderboardStanding(.empty)
        }
    }

    func currentLeaderboardStats() -> LeaderboardStats {
        UsageStats(typingWPM: typingWPM).leaderboardStats(entries: transcriptionHistory)
    }

    func syncLeaderboardIfNeeded(force: Bool = false) {
        guard leaderboardOptIn else { return }
        LeaderboardClient.shared.scheduleSync(
            statsProvider: { [weak self] in
                self?.currentLeaderboardStats() ?? .zero
            },
            force: force
        )
        applyLeaderboardStanding(LeaderboardClient.shared.standing)
    }

    /// Pull latest rank for Home without blocking the UI.
    func refreshLeaderboardStanding() {
        guard leaderboardOptIn else { return }
        LeaderboardClient.shared.refreshStanding { [weak self] standing in
            self?.applyLeaderboardStanding(standing)
        }
    }

    func applyLeaderboardStanding(_ standing: LeaderboardStanding) {
        leaderboardDisplayName = standing.displayName
        leaderboardRank = standing.rank
        leaderboardShortName = standing.shortName
        leaderboardAnimal = standing.animal
        leaderboardAvatarKey = standing.avatarKey
        leaderboardIsCustomName = standing.isCustomName
        leaderboardPublicNameDraft = LeaderboardClient.shared.publicName
        leaderboardNameError = Self.friendlyLeaderboardNameError(LeaderboardClient.shared.lastNameError)
        if standing.stats != .zero {
            leaderboardRemoteStats = standing.stats
        }
    }

    /// Set or clear competitive public name (empty → anonymous animal).
    func setLeaderboardPublicName(_ name: String) {
        LeaderboardClient.shared.setPublicName(name) { [weak self] in
            self?.currentLeaderboardStats() ?? .zero
        }
        leaderboardPublicNameDraft = LeaderboardClient.shared.publicName
        leaderboardNameError = nil
        // Standing updates after network; optimistic UI for draft.
        if LeaderboardClient.shared.publicName.isEmpty {
            leaderboardIsCustomName = false
        }
    }

    private static func friendlyLeaderboardNameError(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        switch code {
        case "name_taken":
            return "That name is already on the board — try another."
        case "invalid_name_length":
            return "Name must be 2–24 characters."
        case "invalid_name_chars", "invalid_name":
            return "Use letters, numbers, spaces, or . _ - only."
        case "reserved_name":
            return "That name is reserved."
        default:
            return "Couldn’t set that name (\(code))."
        }
    }

    func openPublicLeaderboard() {
        NSWorkspace.shared.open(LeaderboardClient.publicBoardURL)
    }

    // MARK: - Microphone input

    func refreshInputDevices() {
        availableInputDevices = AudioInputDevices.inputDevices()
        if !selectedInputDeviceUID.isEmpty,
           !availableInputDevices.contains(where: { $0.uid == selectedInputDeviceUID })
        {
            setInputDeviceUID("")
        }
    }

    func setInputDeviceUID(_ uid: String) {
        selectedInputDeviceUID = uid
        UserDefaults.standard.set(uid, forKey: Self.inputDeviceUIDKey)
        syncAudioInputDevice()
    }

    private func syncAudioInputDevice() {
        audioRecorder.inputDeviceUID = selectedInputDeviceUID.isEmpty ? nil : selectedInputDeviceUID
    }

    // MARK: - BYOK keys

    func refreshKeyPresence() {
        if let key = KeychainStore.load(account: .openAI) {
            hasOpenAIKey = true
            openAIKeyMasked = KeychainStore.masked(key)
        } else {
            hasOpenAIKey = false
            openAIKeyMasked = ""
        }
        if let key = KeychainStore.load(account: .elevenLabs) {
            hasElevenLabsKey = true
            elevenLabsKeyMasked = KeychainStore.masked(key)
        } else {
            hasElevenLabsKey = false
            elevenLabsKeyMasked = ""
        }
    }

    func saveOpenAIKey(_ raw: String) throws {
        try KeychainStore.save(raw, account: .openAI)
        refreshKeyPresence()
        if transcriptionProvider == .openAI {
            Task { await prepareActiveProvider() }
        }
    }

    func saveElevenLabsKey(_ raw: String) throws {
        try KeychainStore.save(raw, account: .elevenLabs)
        refreshKeyPresence()
        if transcriptionProvider == .elevenLabs {
            Task { await prepareActiveProvider() }
        }
    }

    func clearOpenAIKey() throws {
        try KeychainStore.delete(account: .openAI)
        refreshKeyPresence()
        if transcriptionProvider == .openAI {
            isModelLoaded = false
            modelLoadStatus = "Add OpenAI API key"
        }
        if polishProvider == .openAI {
            setPolishProvider(.off)
        }
    }

    func clearElevenLabsKey() throws {
        try KeychainStore.delete(account: .elevenLabs)
        refreshKeyPresence()
        if transcriptionProvider == .elevenLabs {
            isModelLoaded = false
            modelLoadStatus = "Add ElevenLabs API key"
        }
    }

    func setTranscriptionProvider(_ provider: TranscriptionProvider) {
        guard provider != transcriptionProvider else { return }
        if isRecording {
            _ = audioRecorder.stopRecording()
            isRecording = false
            recordingSession += 1
            stopElapsedTimer()
        }
        transcriptionProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Self.transcriptionProviderKey)
        Task { await prepareActiveProvider() }
    }

    func setPolishProvider(_ provider: PolishProvider) {
        polishProvider = provider
        llmPolishEnabled = provider == .local
        UserDefaults.standard.set(provider.rawValue, forKey: Self.polishProviderKey)
        UserDefaults.standard.set(llmPolishEnabled, forKey: "llmPolishEnabled")
        // Keep AI Models open when polish is active so users can turn it off.
        if provider != .off, !showExperimentalAIModels {
            setShowExperimentalAIModels(true)
        }
        if provider == .local {
            Task { await loadLLM(force: !isLLMLoaded) }
        }
    }

    func setShowExperimentalAIModels(_ show: Bool) {
        showExperimentalAIModels = show
        UserDefaults.standard.set(show, forKey: Self.showExperimentalAIModelsKey)
    }

    func setPolishLocalModel(_ model: PolishLocalModel) {
        guard model.isSelectable else { return }
        polishLocalModel = model
        TextPolisher.setModelPreference(model)
        UserDefaults.standard.set(model.rawValue, forKey: Self.polishLocalModelKey)
        isPolishModelOnDisk = model.isAvailable
        // Drop in-memory weights so the next load uses the new pack.
        Task {
            await textPolisher.unload()
            await MainActor.run {
                isLLMLoaded = false
                llmLoadStatus = model.isAvailable ? "" : "Download required (\(model.downloadSizeLabel))"
                llmLoadProgress = 0
            }
            if polishProvider == .local {
                await loadLLM(force: true)
            }
        }
    }

    /// Refresh whether polish weights are on disk (Settings badge).
    func refreshPolishModelOnDisk() {
        isPolishModelOnDisk = polishLocalModel.isAvailable
    }

    /// Marks cloud providers ready when a key exists; loads local model otherwise.
    /// Leaving `.local` unloads in-memory ASR weights (disk cache is kept).
    func prepareActiveProvider() async {
        switch transcriptionProvider {
        case .local:
            await loadModel()
        case .openAI:
            await unloadLocalModelForProviderSwitch()
            if hasOpenAIKey {
                isModelLoaded = true
                modelLoadStatus = "Ready · OpenAI"
                modelLoadProgress = 1
            } else {
                isModelLoaded = false
                modelLoadStatus = "Add OpenAI API key in Settings"
                modelLoadProgress = 0
            }
            syncIdlePhase()
        case .elevenLabs:
            await unloadLocalModelForProviderSwitch()
            if hasElevenLabsKey {
                isModelLoaded = true
                modelLoadStatus = "Ready · ElevenLabs"
                modelLoadProgress = 1
            } else {
                isModelLoaded = false
                modelLoadStatus = "Add ElevenLabs API key in Settings"
                modelLoadProgress = 0
            }
            syncIdlePhase()
        }
    }

    /// Free on-device ASR weights and invalidate any in-flight local load so it
    /// cannot rewrite readiness flags after the user moved to a cloud provider.
    private func unloadLocalModelForProviderSwitch() async {
        modelLoadGeneration += 1
        isModelLoading = false
        await transcriptionEngine.unloadModel()
    }

    func loadModel() async {
        // Invalidate any prior in-flight load (size switch or overlapping prepare).
        modelLoadGeneration += 1
        let generation = modelLoadGeneration

        // Allow reload when switching size (isModelLoaded may already be true).
        isModelLoading = true
        isModelLoaded = false
        modelLoadProgress = 0
        modelLoadStatus = "Loading \(asrModelSize.displayName)..."

        do {
            let engine = transcriptionEngine
            let size = asrModelSize
            try await Task.detached {
                // Keep "Download" wording when the pack is not on disk yet so users
                // know a multi‑hundred‑MB HF fetch is in progress (not a local load).
                let alreadyCached = ASRModelCache.looksComplete(size: size)
                try await engine.loadModel(size: size) { progress, status in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.modelLoadGeneration == generation else { return }
                        self.modelLoadProgress = progress
                        var label = status.trimmingCharacters(in: .whitespacesAndNewlines)
                        if alreadyCached {
                            label = label.replacingOccurrences(
                                of: "Download",
                                with: "Load",
                                options: .caseInsensitive
                            )
                        }
                        while label.hasSuffix("…") || label.hasSuffix("...") || label.hasSuffix(".") {
                            if label.hasSuffix("...") {
                                label = String(label.dropLast(3))
                            } else {
                                label = String(label.dropLast())
                            }
                            label = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        if label.isEmpty {
                            label = alreadyCached ? "Loading model" : "Downloading model"
                        }
                        self.modelLoadStatus = "\(label)… \(Int(progress * 100))%"
                    }
                }
            }.value

            // Stale: provider switched away or a newer load superseded us.
            guard generation == modelLoadGeneration else { return }
            guard transcriptionProvider == .local else {
                await engine.unloadModel()
                return
            }

            isModelLoaded = true
            modelLoadStatus = "Ready"
            syncIdlePhase()
        } catch is CancellationError {
            // loadModel was superseded by unload or a newer load — ignore.
            guard generation == modelLoadGeneration else { return }
        } catch {
            guard generation == modelLoadGeneration else { return }
            modelLoadStatus = "Error: \(error.localizedDescription)"
            isModelLoaded = false
            setPhase(.failed, detail: modelLoadStatus)
            schedulePhaseResetToIdle()
        }

        if generation == modelLoadGeneration {
            isModelLoading = false
            if isModelLoaded { syncIdlePhase() }
        }
    }

    func setASRModelSize(_ size: ASRModelSize) {
        guard size != asrModelSize else { return }
        asrModelSize = size
        UserDefaults.standard.set(size.rawValue, forKey: Self.asrModelSizeKey)
        if isRecording {
            _ = audioRecorder.stopRecording()
            isRecording = false
            recordingSession += 1
            stopElapsedTimer()
        }
        // Only reload on-device weights when local STT is active.
        // loadModel() first unloads the previous size (weights + MLX GPU cache).
        guard transcriptionProvider == .local else { return }
        Task { await loadModel() }
    }

    func setDictationMode(_ mode: DictationMode) {
        dictationMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "dictationMode")
    }

    func setDictationHotkey(_ chord: KeyChord) {
        dictationHotkey = chord
        if let data = try? JSONEncoder().encode(chord) {
            UserDefaults.standard.set(data, forKey: Self.dictationHotkeyKey)
        }
        hotkeyManager.setDictationChord(chord)
        refreshHotkeyHealth()
    }

    func resetDictationHotkey() {
        setDictationHotkey(.defaultDictation)
    }

    func setCancelHotkey(_ chord: KeyChord) {
        cancelHotkey = chord
        if let data = try? JSONEncoder().encode(chord) {
            UserDefaults.standard.set(data, forKey: Self.cancelHotkeyKey)
        }
        hotkeyManager.setCancelChord(chord)
    }

    func resetCancelHotkey() {
        setCancelHotkey(.defaultCancel)
    }

    /// Discard listening without STT / paste (cancel hotkey).
    func cancelActiveRecording() {
        guard isRecording else { return }
        recordingSession += 1
        livePartialTask?.cancel()
        livePartialTask = nil
        _ = audioRecorder.stopRecording()
        isRecording = false
        stopElapsedTimer()
        currentTranscription = ""
        setPhase(.ready, detail: "Cancelled")
        if soundFeedbackEnabled {
            FeedbackSounds.playFailure()
        }
        phaseResetTask?.cancel()
        phaseResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !self.isRecording else { return }
            if self.dictationPhase == .ready || self.dictationPhase == .failed {
                self.setPhase(.ready, detail: "")
            }
        }
        ListeningHUDController.shared.hide()
    }

    func setListeningHUDEnabled(_ enabled: Bool) {
        setRecordingWindowStyle(enabled ? .classic : .none)
    }

    func setRecordingWindowStyle(_ style: RecordingWindowStyle) {
        recordingWindowStyle = style
        listeningHUDEnabled = style != .none
        UserDefaults.standard.set(style.rawValue, forKey: Self.recordingWindowStyleKey)
        UserDefaults.standard.set(listeningHUDEnabled, forKey: Self.listeningHUDKey)
        if style == .none {
            ListeningHUDController.shared.hide()
        } else {
            ListeningHUDController.shared.sync(with: self)
        }
    }

    func setLiquidGlassStyle(_ style: LiquidGlassStyle) {
        liquidGlassStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.liquidGlassStyleKey)
        ListeningHUDController.shared.sync(with: self)
    }

    func setLivePartialsEnabled(_ enabled: Bool) {
        livePartialsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.livePartialsEnabledKey)
    }

    /// Remove on-disk ASR weights for this catalog model (frees cache). Active
    /// model is unloaded so the next load re-downloads.
    func deleteDownloadedASRModel(_ size: ASRModelSize) async {
        if asrModelSize == size || (size == .parakeetInt8 && asrModelSize == .parakeetInt4) {
            await unloadLocalModelForProviderSwitch()
            isModelLoaded = false
            modelLoadStatus = "Model removed — download again to use"
            modelLoadProgress = 0
        }
        ASRModelCache.purge(modelId: size.modelId)
        if size == .parakeetInt8 {
            ASRModelCache.purge(modelId: ASRModelSize.parakeetInt4.modelId)
        }
        objectWillChange.send()
    }

    /// Select + ensure model is loaded (download if needed).
    func selectAndLoadASRModel(_ size: ASRModelSize) {
        setTranscriptionProvider(.local)
        if size != asrModelSize {
            setASRModelSize(size)
        } else if !isModelLoaded && !isModelLoading {
            Task { await loadModel() }
        }
    }

    /// Enable local polish and download/load this LLM pack.
    func selectAndLoadPolishModel(_ model: PolishLocalModel) {
        setPolishLocalModel(model)
        setPolishProvider(.local)
        if !isLLMLoaded && !isLLMLoading {
            Task { await loadLLM(force: true) }
        }
    }

    /// Turn off local polish without deleting weights.
    func disableLocalPolish() {
        setPolishProvider(.off)
        Task {
            await textPolisher.unload()
            await MainActor.run {
                isLLMLoaded = false
                llmLoadStatus = ""
                llmLoadProgress = 0
            }
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        showOnboarding = false
    }

    func reopenOnboarding() {
        showOnboarding = true
    }

    // MARK: - Phase / elapsed

    func syncIdlePhase() {
        guard !dictationPhase.isBusy else { return }
        if isReadyToDictate {
            setPhase(.ready, detail: readinessLabel)
        } else if isModelLoading {
            setPhase(.setup, detail: modelLoadStatus.isEmpty ? "Loading model…" : modelLoadStatus)
        } else {
            setPhase(.setup, detail: readinessLabel)
        }
    }

    private func setPhase(_ phase: DictationPhase, detail: String) {
        dictationPhase = phase
        phaseDetail = detail
        ListeningHUDController.shared.sync(with: self)
    }

    private func schedulePhaseResetToIdle(after seconds: TimeInterval = 2.4) {
        phaseResetTask?.cancel()
        phaseResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard !self.dictationPhase.isBusy else { return }
            self.lastFailureMessage = nil
            self.syncIdlePhase()
        }
    }

    private func startElapsedTimer() {
        recordingStartedAt = Date()
        recordingElapsed = 0
        recordingElapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartedAt else { return }
                self.recordingElapsed = Date().timeIntervalSince(start)
                ListeningHUDController.shared.sync(with: self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        recordingElapsedTimer = timer
    }

    private func stopElapsedTimer() {
        recordingElapsedTimer?.invalidate()
        recordingElapsedTimer = nil
        recordingStartedAt = nil
    }

    // MARK: - Recording

    func startRecording() {
        guard isReadyToDictate else {
            // Pressing the hotkey during model load / missing key used to no-op
            // silently, which reads as "the hotkey is broken". Give audible feedback
            // and retry preparing the active provider.
            presentFailure(
                "Not ready — \(readinessLabel)",
                openSetup: true
            )
            if transcriptionProvider == .local, !isModelLoading {
                Task { await loadModel() }
            } else {
                Task { await prepareActiveProvider() }
            }
            return
        }
        guard !isRecording else { return }
        phaseResetTask?.cancel()
        lastFailureMessage = nil
        isRecording = true
        currentTranscription = ""
        lastLivePartialSampleCount = 0
        recordingSession += 1
        let session = recordingSession
        setPhase(.listening, detail: dictationMode == .hold
                 ? "Listening… release to stop"
                 : "Listening… press again to stop")
        startElapsedTimer()

        refreshOutputMuteState()
        if soundFeedbackEnabled {
            FeedbackSounds.playListeningStarted()
        }

        Task { @MainActor in
            // Let the start chime begin before AVAudioEngine claims the input path.
            if soundFeedbackEnabled {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard isRecording, recordingSession == session else { return }
            // Always re-apply the user’s mic choice before opening the engine.
            syncAudioInputDevice()
            audioRecorder.startRecording()
            // Live partials while the mic is open (local Qwen + Parakeet).
            startLivePartialLoop(session: session)
        }
    }

    /// Periodically re-transcribe the growing mic buffer so the HUD types live.
    /// Works for **Qwen (MLX)** and **Parakeet (Core ML)** — both use full-buffer
    /// batch re-runs (Parakeet has no separate token stream API in-app).
    private func startLivePartialLoop(session: Int) {
        livePartialTask?.cancel()
        livePartialInFlight = false

        // Live draft for local engines when enabled and window can show text (Classic)
        // or still compute for mini when user wants drafts in menu status.
        guard transcriptionProvider == .local, livePartialsEnabled else { return }

        livePartialTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 850_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                guard self.isRecording, self.recordingSession == session else { return }
                guard self.dictationPhase == .listening else { return }

                if !self.livePartialInFlight {
                    let snap = self.audioRecorder.snapshotSamples()
                    if snap.count >= Self.livePartialMinSamples {
                        self.livePartialInFlight = true
                        let context = self.asrModelSize.supportsContext ? self.asrContext : nil
                        let language = self.selectedLanguage
                        let engine = self.transcriptionEngine
                        let sessionAtStart = session
                        let snapCount = snap.count
                        Task { [weak self] in
                            defer {
                                Task { @MainActor [weak self] in
                                    self?.livePartialInFlight = false
                                }
                            }
                            do {
                                let text = try await engine.transcribe(
                                    samples: snap,
                                    language: language,
                                    context: context
                                )
                                await MainActor.run { [weak self] in
                                    guard let self else { return }
                                    // Accept draft while listening, or during the brief
                                    // release drain window (session already advanced).
                                    let stillThisSession = self.recordingSession == sessionAtStart
                                        || self.recordingSession == sessionAtStart + 1
                                    guard stillThisSession else { return }
                                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    self.currentTranscription = trimmed
                                    self.lastLivePartialSampleCount = snapCount
                                    if self.dictationPhase == .listening {
                                        self.phaseDetail = trimmed
                                        ListeningHUDController.shared.sync(with: self)
                                    }
                                }
                            } catch {
                                // Ignore transient live failures; final pass still runs on release.
                            }
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: Self.livePartialIntervalNs)
            }
        }
    }

    private func stopLivePartialLoop() {
        livePartialTask?.cancel()
        livePartialTask = nil
        // Leave `livePartialInFlight` alone — an in-flight ASR call clears it
        // when done so release can await a fresher draft before pasting.
    }

    /// Wait briefly for an in-flight live partial so we can paste it instead of
    /// kicking off another full-buffer STT (the main source of 2–3s lag).
    private func drainInFlightLivePartial() async {
        let deadline = DispatchTime.now().uptimeNanoseconds + Self.livePartialDrainTimeoutNs
        while livePartialInFlight {
            if DispatchTime.now().uptimeNanoseconds >= deadline { break }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    /// Prefer the live HUD draft when almost no new audio arrived after it.
    private func shouldReuseLiveDraft(draft: String, totalSamples: Int) -> Bool {
        guard !draft.isEmpty else { return false }
        guard transcriptionProvider == .local else { return false }
        guard lastLivePartialSampleCount >= Self.livePartialMinSamples else { return false }
        let newSamples = totalSamples - lastLivePartialSampleCount
        // Draft covered nearly the whole buffer (or was slightly ahead of stop).
        return newSamples <= Self.liveDraftReuseMaxNewSamples
    }

    func stopRecordingAndTranscribe() async {
        guard isRecording else { return }
        isRecording = false
        recordingSession += 1
        stopElapsedTimer()
        stopLivePartialLoop()
        let samples = audioRecorder.stopRecording()

        // Pop when mic stops (successful capture). Empty/error uses failure chime via presentFailure.
        if soundFeedbackEnabled, !samples.isEmpty {
            refreshOutputMuteState()
            FeedbackSounds.playListeningStopped()
        }

        guard !samples.isEmpty else {
            reportEmptyAudioFailure()
            presentFailure("No audio captured — hold longer, or check Microphone permission.")
            return
        }

        // Keep any live draft visible while we finalize.
        var draft = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        setPhase(
            .transcribing,
            detail: draft.isEmpty ? "Finalizing…" : draft
        )
        ListeningHUDController.shared.sync(with: self)

        // If a live pass is still running, wait for it — that result is usually
        // the full utterance and avoids a second multi-second STT on the actor.
        if livePartialInFlight {
            await drainInFlightLivePartial()
            draft = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !draft.isEmpty {
                phaseDetail = draft
                ListeningHUDController.shared.sync(with: self)
            }
        }

        let audioDuration = Double(samples.count) / 16000.0
        let sttStarted = Date()
        do {
            let text: String
            let reusedLiveDraft = shouldReuseLiveDraft(draft: draft, totalSamples: samples.count)
            if reusedLiveDraft {
                // Fast path: HUD already showed this text — paste without re-STT.
                text = draft
                NSLog(
                    "MacWispr: release using live draft (new samples=%d ≤ %d)",
                    samples.count - lastLivePartialSampleCount,
                    Self.liveDraftReuseMaxNewSamples
                )
            } else {
                // Buffer grew after last draft (or no draft) — full final pass.
                if !draft.isEmpty {
                    setPhase(.transcribing, detail: draft)
                    ListeningHUDController.shared.sync(with: self)
                }
                text = try await transcribeSamples(samples)
            }
            let sttLatency = Date().timeIntervalSince(sttStarted)
            let afterLight = postProcess(text)
            var processed = afterLight
            var polishLatency: TimeInterval? = nil

            // Polish before insert so the cursor gets the formatted text — not
            // raw STT with polish only landing in history/clipboard afterward.
            // Live drafts stay raw STT only; polish runs after the final pass.
            if polishProvider != .off {
                setPhase(.transcribing, detail: "Polishing…")
                ListeningHUDController.shared.sync(with: self)
                let polishStarted = Date()
                processed = await applyPolish(processed)
                polishLatency = Date().timeIntervalSince(polishStarted)
            }

            lastCleanTranscription = processed
            currentTranscription = processed

            let duration = audioDuration
            let entry = TranscriptionEntry(
                text: processed,
                timestamp: Date(),
                duration: duration,
                wordCount: UsageStats.wordCount(in: processed)
            )
            let entryId = entry.id
            lastTranscriptionId = entryId
            transcriptionHistory.insert(entry, at: 0)
            HistoryStore.trimInPlace(&transcriptionHistory)
            scheduleHistorySave()

            // Local-only debug dump (off by default). Never sent as telemetry.
            if devCaptureEnabled || DevCaptureStore.isEnabled {
                DevCaptureStore.save(
                    samples: samples,
                    entryId: entryId,
                    rawSTT: text,
                    afterPostProcess: afterLight,
                    polished: processed,
                    audioDuration: audioDuration,
                    sttLatency: sttLatency,
                    transcriptionProvider: transcriptionProvider.rawValue,
                    asrModel: transcriptionProvider == .local ? asrModelSize.rawValue : nil,
                    polishProvider: polishProvider.rawValue,
                    polishModel: polishProvider == .local ? polishLocalModel.rawValue : nil
                )
            }

            // Carbon can detect ⌥Space without AX, but paste/type still needs it.
            let outcome = textInserter.insert(text: processed, mode: insertionMode)
            let telemetryOutcome: TelemetryInsertionOutcome
            switch outcome {
            case .ok:
                telemetryOutcome = .ok
                let words = UsageStats.wordCount(in: processed)
                setPhase(.success, detail: Self.formatSuccessDetail(words: words, sttLatency: sttLatency))
                if soundFeedbackEnabled { FeedbackSounds.playSuccess() }
                schedulePhaseResetToIdle(after: 2.8)

            case .clipboardOnly(let reason):
                telemetryOutcome = .clipboardOnly
                accessibilityTrusted = false
                hotkeyArmed = hotkeyManager.isArmed
                presentFailure(reason, preferAccessibilityFix: true)
            case .failed(let reason):
                telemetryOutcome = .failed
                if !AXIsProcessTrusted() {
                    Telemetry.shared.reportDictationFailed(reason: .pasteNoAX)
                    presentFailure(reason, preferAccessibilityFix: true)
                } else {
                    presentFailure(reason)
                }
            }

            // Content-free polish metrics only (word buckets / shape / changed).
            let rawWords = UsageStats.wordCount(in: afterLight)
            let polishedWords = UsageStats.wordCount(in: processed)
            reportDictationCompleted(
                sttLatency: sttLatency,
                audioDuration: audioDuration,
                insertionOutcome: telemetryOutcome,
                polishLatency: polishLatency,
                rawWordCount: rawWords,
                polishedWordCount: polishedWords,
                textChangedByPolish: polishProvider != .off && afterLight != processed,
                rawHasNewlines: afterLight.contains(where: \.isNewline),
                polishedHasNewlines: processed.contains(where: \.isNewline),
                polishedLooksLikeList: Telemetry.looksLikeList(processed)
            )
            // Public board aggregates only (if opted in) — never transcript text.
            syncLeaderboardIfNeeded(force: false)
        } catch {
            lastTranscriptionId = nil
            if devCaptureEnabled || DevCaptureStore.isEnabled {
                DevCaptureStore.save(
                    samples: samples,
                    entryId: nil,
                    rawSTT: nil,
                    afterPostProcess: nil,
                    polished: nil,
                    audioDuration: audioDuration,
                    sttLatency: Date().timeIntervalSince(sttStarted),
                    transcriptionProvider: transcriptionProvider.rawValue,
                    asrModel: transcriptionProvider == .local ? asrModelSize.rawValue : nil,
                    polishProvider: polishProvider.rawValue,
                    polishModel: polishProvider == .local ? polishLocalModel.rawValue : nil,
                    error: error.localizedDescription
                )
            }
            Telemetry.shared.reportDictationFailed(reason: .sttError)
            presentFailure("Transcription failed: \(error.localizedDescription)")
        }
    }

    /// Surface a failure without burying it in history text; update phase + HUD.
    func presentFailure(
        _ message: String,
        preferAccessibilityFix: Bool = false,
        openSetup: Bool = false
    ) {
        lastFailureMessage = message
        setPhase(.failed, detail: message)
        if soundFeedbackEnabled {
            FeedbackSounds.playFailure()
        }
        FailureBannerController.shared.show(
            message: message,
            showAccessibilityFix: preferAccessibilityFix || !AXIsProcessTrusted(),
            openSetup: openSetup
        )
        schedulePhaseResetToIdle(after: 3.5)
    }

    func dismissFailureBanner() {
        lastFailureMessage = nil
        FailureBannerController.shared.hide()
        if !dictationPhase.isBusy {
            syncIdlePhase()
        }
    }

    /// Copy last clean transcript to the pasteboard (no focus steal).
    func copyLastTranscription() {
        let text = lastCleanTranscription.isEmpty ? currentTranscription : lastCleanTranscription
        guard !text.isEmpty else { return }
        textInserter.copyToClipboardOnly(text)
    }

    /// Re-run insertion for the last clean transcript.
    func repasteLastTranscription() {
        let text = lastCleanTranscription.isEmpty ? currentTranscription : lastCleanTranscription
        guard !text.isEmpty else { return }
        let outcome = textInserter.insert(text: text, mode: insertionMode)
        switch outcome {
        case .ok:
            setPhase(.success, detail: "Re-inserted")
            if soundFeedbackEnabled { FeedbackSounds.playSuccess() }
            schedulePhaseResetToIdle()
        case .clipboardOnly(let reason):
            presentFailure(reason, preferAccessibilityFix: true)
        case .failed(let reason):
            presentFailure(reason)
        }
    }

    /// Bucketed lifecycle event — no content, no raw timings (#9).
    private func reportDictationCompleted(
        sttLatency: TimeInterval,
        audioDuration: TimeInterval,
        insertionOutcome: TelemetryInsertionOutcome,
        polishLatency: TimeInterval? = nil,
        rawWordCount: Int? = nil,
        polishedWordCount: Int? = nil,
        textChangedByPolish: Bool? = nil,
        rawHasNewlines: Bool? = nil,
        polishedHasNewlines: Bool? = nil,
        polishedLooksLikeList: Bool? = nil
    ) {
        let providerToken: String
        let modelSizeToken: String
        switch transcriptionProvider {
        case .local:
            providerToken = "local"
            modelSizeToken = asrModelSize.rawValue
        case .openAI:
            providerToken = "cloud"
            modelSizeToken = "openai"
        case .elevenLabs:
            providerToken = "cloud"
            modelSizeToken = "elevenlabs"
        }

        let insertionToken: String
        switch insertionMode {
        case .clipboard: insertionToken = "clipboard"
        case .typeOut: insertionToken = "type_out"
        case .both: insertionToken = "both"
        }

        let polishToken: String
        switch polishProvider {
        case .off: polishToken = "off"
        case .local: polishToken = "local"
        case .openAI: polishToken = "openai"
        }

        Telemetry.shared.reportDictationCompleted(
            provider: providerToken,
            modelSize: modelSizeToken,
            mode: dictationMode.telemetryValue,
            insertionMode: insertionToken,
            sttLatencySeconds: sttLatency,
            audioDurationSeconds: audioDuration,
            insertionOutcome: insertionOutcome,
            polishProvider: polishToken,
            polishModel: polishProvider == .local ? polishLocalModel.rawValue : nil,
            polishLatencySeconds: polishLatency,
            rawWordCount: rawWordCount,
            polishedWordCount: polishedWordCount,
            textChangedByPolish: textChangedByPolish,
            rawHasNewlines: rawHasNewlines,
            polishedHasNewlines: polishedHasNewlines,
            polishedLooksLikeList: polishedLooksLikeList
        )
    }

    private func reportEmptyAudioFailure() {
        let micDenied: Bool
        if #available(macOS 14.0, *) {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            micDenied = (status == .denied || status == .restricted)
        } else {
            micDenied = false
        }
        Telemetry.shared.reportDictationFailed(reason: micDenied ? .micDenied : .noAudio)
    }

    func setInsertionMode(_ mode: InsertionMode) {
        insertionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "insertionMode")
    }

    private func transcribeSamples(_ samples: [Float]) async throws -> String {
        switch transcriptionProvider {
        case .local:
            // Parakeet ignores context; only pass vocab for Qwen.
            let context = asrModelSize.supportsContext ? asrContext : nil
            return try await transcriptionEngine.transcribe(
                samples: samples,
                language: selectedLanguage,
                context: context
            )
        case .openAI:
            guard let key = KeychainStore.load(account: .openAI) else {
                throw CloudSTTError.missingAPIKey("OpenAI")
            }
            return try await CloudSTTClient.transcribeOpenAI(
                samples: samples,
                apiKey: key,
                language: selectedLanguage,
                prompt: asrContext
            )
        case .elevenLabs:
            guard let key = KeychainStore.load(account: .elevenLabs) else {
                throw CloudSTTError.missingAPIKey("ElevenLabs")
            }
            return try await CloudSTTClient.transcribeElevenLabs(
                samples: samples,
                apiKey: key,
                language: selectedLanguage,
                keyterms: customVocabulary
            )
        }
    }

    private func applyPolish(_ text: String) async -> String {
        switch polishProvider {
        case .off:
            return text
        case .local:
            if !isLLMLoaded && !isLLMLoading {
                await loadLLM()
            }
            guard isLLMLoaded else { return text }
            let polished = await textPolisher.polish(text)
            return postProcess(polished)
        case .openAI:
            guard let key = KeychainStore.load(account: .openAI) else { return text }
            do {
                let polished = try await CloudSTTClient.polishOpenAI(text: text, apiKey: key)
                return postProcess(polished)
            } catch {
                NSLog("MacWispr OpenAI polish failed: \(error.localizedDescription)")
                return text
            }
        }
    }

    // MARK: - Edit transcription → update history + dictionary

    /// Applies a user edit from the Dictate panel. Learns new words into custom vocabulary.
    func commitCurrentTranscriptionEdit(_ newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = currentTranscription
        guard trimmed != original else { return }

        learnVocabularyFromEdit(original: original, corrected: trimmed)
        currentTranscription = trimmed

        if let id = lastTranscriptionId {
            updateHistoryEntry(id: id, text: trimmed, learnVocab: false)
        }
    }

    /// Applies a user edit from History. Learns new words into custom vocabulary.
    func commitHistoryEdit(id: UUID, newText: String) {
        updateHistoryEntry(id: id, text: newText, learnVocab: true)
    }

    private func updateHistoryEntry(id: UUID, text newText: String, learnVocab: Bool) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = transcriptionHistory.firstIndex(where: { $0.id == id }) else { return }
        let original = transcriptionHistory[index].text
        guard trimmed != original else { return }

        if learnVocab {
            learnVocabularyFromEdit(original: original, corrected: trimmed)
        }

        let old = transcriptionHistory[index]
        transcriptionHistory[index] = TranscriptionEntry(
            id: old.id,
            text: trimmed,
            timestamp: old.timestamp,
            duration: old.duration,
            wordCount: UsageStats.wordCount(in: trimmed)
        )
        scheduleHistorySave()

        if lastTranscriptionId == id {
            currentTranscription = trimmed
        }
    }

    /// Cap + debounce full history rewrites (#4 item 4).
    private func scheduleHistorySave(immediate: Bool = false) {
        HistoryStore.trimInPlace(&transcriptionHistory)
        if immediate {
            historySaveTask?.cancel()
            historySaveTask = nil
            HistoryStore.save(transcriptionHistory)
            return
        }
        historySaveTask?.cancel()
        historySaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.historySaveDebounceNs)
            guard !Task.isCancelled, let self else { return }
            HistoryStore.save(self.transcriptionHistory)
            self.historySaveTask = nil
        }
    }

    /// Words present in the corrected text but not the original are added to the dictionary.
    func learnVocabularyFromEdit(original: String, corrected: String) {
        let originalSet = Set(Self.tokenize(original).map { $0.lowercased() })
        let correctedTokens = Self.tokenize(corrected)

        for token in correctedTokens {
            let lower = token.lowercased()
            if originalSet.contains(lower) { continue }
            if Self.vocabularyStopWords.contains(lower) { continue }
            if token.count < 2 { continue }
            // Prefer proper nouns / jargon (mixed case, hyphen, digits) but allow plain new words too.
            addVocabularyTerm(token)
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Common function words — don't put these in the ASR dictionary from edits.
    private static let vocabularyStopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "else", "when", "while",
        "to", "of", "in", "on", "at", "for", "from", "by", "with", "as", "is", "are",
        "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did",
        "will", "would", "could", "should", "may", "might", "must", "can", "this", "that",
        "these", "those", "it", "its", "i", "me", "my", "we", "our", "you", "your",
        "he", "she", "they", "them", "his", "her", "their", "not", "no", "yes", "so",
        "just", "also", "very", "too", "than", "into", "about", "up", "out", "all",
        "any", "some", "more", "most", "other", "only", "own", "same", "such", "over",
        "after", "before", "between", "through", "during", "without", "again", "further",
        "once", "here", "there", "where", "why", "how", "what", "which", "who", "whom",
    ]

    func setLLMPolishEnabled(_ enabled: Bool) {
        setPolishProvider(enabled ? .local : .off)
    }

    func loadLLM(force: Bool = false) async {
        if isLLMLoading { return }
        if isLLMLoaded && !force { return }
        isLLMLoading = true
        isLLMLoaded = false
        let pack = polishLocalModel
        let needsDownload = !pack.isAvailable
        llmLoadProgress = 0
        llmLoadStatus = needsDownload
            ? "Downloading \(pack.shortName) (\(pack.downloadSizeLabel))…"
            : "Loading \(pack.shortName)…"
        do {
            let polisher = textPolisher
            try await polisher.load(model: pack) { progress, status in
                Task { @MainActor in
                    self.llmLoadProgress = progress
                    self.llmLoadStatus = status
                }
            }
            isLLMLoaded = true
            isPolishModelOnDisk = true
            llmLoadProgress = 1
            llmLoadStatus = "Ready · \(pack.shortName)"
        } catch {
            isLLMLoaded = false
            isPolishModelOnDisk = pack.isAvailable
            llmLoadProgress = 0
            llmLoadStatus = error.localizedDescription
            NSLog("MacWispr polish load failed: \(error.localizedDescription)")
        }
        isLLMLoading = false
    }

    /// Explicit download button (same path as load when missing).
    func downloadPolishModel() async {
        await loadLLM(force: true)
    }

    /// Remove Application Support polish pack (Settings → free space).
    func deleteDownloadedPolishModel() async {
        await textPolisher.unload()
        isLLMLoaded = false
        do {
            try PolishLocalModel.deleteDownloaded(polishLocalModel)
            isPolishModelOnDisk = polishLocalModel.isAvailable
            llmLoadStatus = "Removed downloaded pack"
            llmLoadProgress = 0
        } catch {
            llmLoadStatus = error.localizedDescription
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
        typingWPM = max(10, min(200, value))
        UserDefaults.standard.set(typingWPM, forKey: "typingWPM")
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        soundFeedbackEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "soundFeedbackEnabled")
        if enabled {
            refreshOutputMuteState()
        }
    }

    func setFeedbackSoundVolume(_ value: Double) {
        let v = min(1, max(0, value))
        feedbackSoundVolume = v
        FeedbackSoundPreferences.volume = v
    }

    func setStartChime(_ chime: SystemChime) {
        startChime = chime
        FeedbackSoundPreferences.startChime = chime
    }

    func setStopChime(_ chime: SystemChime) {
        stopChime = chime
        FeedbackSoundPreferences.stopChime = chime
    }

    func setSuccessChime(_ chime: SystemChime) {
        successChime = chime
        FeedbackSoundPreferences.successChime = chime
    }

    func setFailureChime(_ chime: SystemChime) {
        failureChime = chime
        FeedbackSoundPreferences.failureChime = chime
    }

    /// Re-read system output mute / near-zero volume for the chime mute banner.
    func refreshOutputMuteState() {
        outputMuted = FeedbackSounds.isOutputMuted()
    }

    func clearHistory() {
        transcriptionHistory = []
        scheduleHistorySave(immediate: true)
    }

    // MARK: - Custom vocabulary (ASR context)

    /// Builds the system-prompt context string Qwen3-ASR uses as background knowledge.
    var asrContext: String? {
        let terms = customVocabulary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        // Free-form context — model was trained to treat this as domain knowledge.
        return "Proper nouns, product names, and domain terms that may appear in the speech: "
            + terms.joined(separator: ", ")
            + "."
    }

    /// Adds one term, or several if the user pastes a comma/newline-separated list.
    func addVocabularyTerm(_ raw: String) {
        let parts = raw
            .components(separatedBy: CharacterSet(charactersIn: ",\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }

        var changed = false
        for term in parts {
            if customVocabulary.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
                continue
            }
            customVocabulary.append(term)
            changed = true
        }
        if changed { persistVocabulary() }
    }

    func removeVocabularyTerm(_ term: String) {
        customVocabulary.removeAll { $0 == term }
        persistVocabulary()
    }

    func clearVocabulary() {
        customVocabulary = []
        persistVocabulary()
    }

    private func persistVocabulary() {
        UserDefaults.standard.set(customVocabulary, forKey: Self.customVocabularyKey)
    }

    /// Minimal non-semantic cleanup only. **No** hardcoded filler/word stripping —
    /// that belongs in the polish SFT model (regexes break phrases like "and so on").
    private func postProcess(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse runs of whitespace / newlines from STT glitches — not word content.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        if autoCapitalize && !result.isEmpty {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setupHotkey() {
        hotkeyManager.setDictationChord(dictationHotkey)
        hotkeyManager.setCancelChord(cancelHotkey)
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
        hotkeyManager.onCancel = { [weak self] in
            Task { @MainActor in
                self?.cancelActiveRecording()
            }
        }
        hotkeyManager.register()
        refreshHotkeyHealth()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hotkeyManager.ensureRegistered()
                self?.refreshHotkeyHealth()
            }
        }

        // Accessory apps rarely become "active", and granting Accessibility
        // after launch doesn't notify us — poll so the global hotkey heals
        // without a relaunch, and so the menu bar status stays honest.
        // Interval backs off once armed (#4 item 5) to reduce App Nap disruption.
        startHotkeyHealthTimer(interval: Self.hotkeyHealthIntervalUnarmed)
    }

    private func startHotkeyHealthTimer(interval: TimeInterval) {
        hotkeyHealthTimer?.invalidate()
        hotkeyHealthInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickHotkeyHealth()
            }
        }
        // common modes so menu-bar tracking doesn't starve the timer.
        RunLoop.main.add(timer, forMode: .common)
        hotkeyHealthTimer = timer
    }

    private func tickHotkeyHealth() {
        // Once armed and no titled window is visible, still re-enable a disabled
        // tap but skip published-state churn (menu bar isn't showing health UI).
        let hasVisibleWindow = NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        hotkeyManager.ensureRegistered()
        if hasVisibleWindow || !hotkeyManager.isArmed {
            refreshHotkeyHealth()
        }

        let desired = hotkeyManager.isArmed
            ? Self.hotkeyHealthIntervalArmed
            : Self.hotkeyHealthIntervalUnarmed
        if abs(desired - hotkeyHealthInterval) > 0.5 {
            startHotkeyHealthTimer(interval: desired)
        }
    }

    /// Re-read tap/carbon/AX into @Published fields for SwiftUI.
    func refreshHotkeyHealth() {
        let armed = hotkeyManager.isArmed
        let ax = hotkeyManager.accessibilityTrusted
        if hotkeyArmed != armed { hotkeyArmed = armed }
        if accessibilityTrusted != ax { accessibilityTrusted = ax }
        emitHotkeyHealthIfNeeded()
        if !dictationPhase.isBusy {
            syncIdlePhase()
        }
    }

    /// Emit `hotkey_health` on transitions; Telemetry dedupes unchanged snapshots (#8).
    func emitHotkeyHealthIfNeeded() {
        Telemetry.shared.reportHotkeyHealth(
            tapInstalled: hotkeyManager.tapInstalled,
            carbonInstalled: hotkeyManager.carbonInstalled,
            axTrusted: hotkeyManager.accessibilityTrusted,
            armed: hotkeyManager.isArmed
        )
    }

    /// Prompt for Accessibility and re-arm the global hotkey.
    func repairHotkey() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        hotkeyManager.register()
        refreshHotkeyHealth()
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

import SwiftUI
import AppKit

/// Left-sidebar destinations (SuperWhisper-style). Used by the main window rail.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case models
    case vocabulary
    case appearance
    case configuration
    case sound
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: return "Models"
        case .vocabulary: return "Vocabulary"
        case .appearance: return "Appearance"
        case .configuration: return "Configuration"
        case .sound: return "Sound"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .models: return "square.stack.3d.up.fill"
        case .vocabulary: return "text.book.closed.fill"
        case .appearance: return "paintbrush.fill"
        case .configuration: return "gearshape.fill"
        case .sound: return "speaker.wave.2.fill"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    /// Which pane to show (driven by main window sidebar).
    var pane: SettingsPane = .configuration

    @State private var newVocabTerm: String = ""
    @State private var vocabSearch: String = ""
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
        Group {
            switch pane {
            case .models: modelsSettings
            case .vocabulary: vocabularySettings
            case .appearance: appearanceSettings
            case .configuration: configurationSettings
            case .sound: soundSettings
            case .about: aboutView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Configuration = former General + Transcription (no nested tabs).
    private var configurationSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                generalSettings
                Divider().padding(.vertical, 8)
                transcriptionSettings
            }
        }
    }

    /// Sound = hotkeys + chimes (SuperWhisper “Sound” grouping).
    private var soundSettings: some View {
        hotkeySettings
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

            // Polish mode here; LLM weights live under Models → LLM models.
            Section("Post-Processing") {
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
                    Text("Active pack: \(appState.polishLocalModel.catalogTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Download, switch, or remove LLM packs in the Models sidebar.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if appState.isLLMLoading {
                        ProgressView(value: appState.llmLoadProgress) {
                            Text(appState.llmLoadStatus).font(.caption)
                        }
                    } else if appState.isLLMLoaded {
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if !appState.isPolishModelOnDisk {
                        Label("Not downloaded — open Models → LLM models", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else if appState.polishProvider == .openAI, !appState.hasOpenAIKey {
                    Label("Add an OpenAI key under Speech provider below", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Models (Voice + LLM) — icon-first, minimal copy

    private var modelsSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Models")
                    .font(.title2.weight(.semibold))

                if appState.isModelLoading {
                    ProgressView(value: appState.modelLoadProgress)
                        .controlSize(.small)
                }
                if appState.isLLMLoading {
                    ProgressView(value: appState.llmLoadProgress)
                        .controlSize(.small)
                }

                // Voice
                catalogSection(icon: "waveform", title: "Voice") {
                    ForEach(ASRModelSize.dashboardChoices) { size in
                        voiceModelRow(size)
                        if size != ASRModelSize.dashboardChoices.last {
                            Divider().opacity(0.3).padding(.leading, 44)
                        }
                    }
                }

                // LLM polish (Off is just a row of icons — no long copy)
                catalogSection(icon: "text.badge.checkmark", title: "Polish") {
                    polishOffRow
                    Divider().opacity(0.3).padding(.leading, 44)
                    // Only show packs that are downloadable or already on disk — skip empty LFM noise.
                    ForEach(PolishLocalModel.catalogCases.filter { $0.huggingfaceRepoId != nil || $0.isAvailable }) { model in
                        llmModelRow(model)
                    }
                }

                // Cloud — icons only
                catalogSection(icon: "cloud", title: "Cloud") {
                    cloudProviderRow(.openAI, title: "OpenAI", symbol: "cloud")
                    Divider().opacity(0.3).padding(.leading, 44)
                    cloudProviderRow(.elevenLabs, title: "ElevenLabs", symbol: "cloud")
                }
            }
            .padding(20)
        }
    }

    private func catalogSection<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func voiceModelRow(_ size: ASRModelSize) -> some View {
        let isActive = appState.transcriptionProvider == .local
            && (appState.asrModelSize == size
                || (size == .parakeetInt8
                    && (appState.asrModelSize == .parakeetInt8 || appState.asrModelSize == .parakeetInt4)))
        return compactModelRow(
            title: size.catalogTitle,
            badge: size.languageBadge,
            sizeLabel: size.downloadSizeLabel,
            symbol: size.dashboardSymbol,
            isActive: isActive,
            onDisk: size.isDownloaded,
            busy: appState.isModelLoading || appState.isRecording,
            onSelect: { appState.selectAndLoadASRModel(size) },
            onDelete: { Task { await appState.deleteDownloadedASRModel(size) } }
        )
    }

    private var polishOffRow: some View {
        let isActive = appState.polishProvider == .off
        return HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .font(.body)
                .frame(width: 22)
            Image(systemName: "xmark.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            Text("Off")
                .font(.body.weight(.medium))
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { appState.disableLocalPolish() }
    }

    private func llmModelRow(_ model: PolishLocalModel) -> some View {
        let isActive = appState.polishProvider == .local && appState.polishLocalModel == model
        return compactModelRow(
            title: model.catalogTitle,
            badge: model.catalogBadge,
            sizeLabel: model.downloadSizeLabel,
            symbol: "text.badge.checkmark",
            isActive: isActive,
            onDisk: model.isAvailable,
            busy: appState.isLLMLoading,
            onSelect: { appState.selectAndLoadPolishModel(model) },
            onDelete: {
                Task {
                    if appState.polishLocalModel == model {
                        await appState.deleteDownloadedPolishModel()
                    } else {
                        try? PolishLocalModel.deleteDownloaded(model)
                        appState.refreshPolishModelOnDisk()
                    }
                }
            }
        )
    }

    /// Icon-first row: check · type icon · name · badge · size · download/trash.
    private func compactModelRow(
        title: String,
        badge: String,
        sizeLabel: String,
        symbol: String,
        isActive: Bool,
        onDisk: Bool,
        busy: Bool,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .font(.body)
                .frame(width: 22)

            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 26)

            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Text(badge)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Capsule())

            Spacer(minLength: 8)

            Text(sizeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            if onDisk {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .help("Remove")
                .disabled(busy)
            } else {
                Button(action: onSelect) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Download \(sizeLabel)")
                .disabled(busy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !busy else { return }
            onSelect()
        }
    }

    private func cloudProviderRow(_ provider: TranscriptionProvider, title: String, symbol: String) -> some View {
        let isActive = appState.transcriptionProvider == provider
        return HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .font(.body)
                .frame(width: 22)
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 26)
            Text(title)
                .font(.body.weight(.medium))
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !appState.isRecording else { return }
            appState.setTranscriptionProvider(provider)
        }
    }

    // MARK: - Vocabulary

    private var vocabularySettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Vocabulary")
                    .font(.title2.weight(.semibold))
                Text("Names and jargon the speech model should prefer. Used as context for Qwen (Parakeet ignores this).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // SuperWhisper-style add bar
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)
                TextField("Add a word or name…", text: $newVocabTerm)
                    .textFieldStyle(.plain)
                    .onSubmit { addVocabTerm() }
                Button("Add word") { addVocabTerm() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newVocabTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search vocabulary", text: $vocabSearch)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            if filteredVocabulary.isEmpty {
                ContentUnavailableView(
                    vocabSearch.isEmpty ? "No words yet" : "No matches",
                    systemImage: "text.book.closed",
                    description: Text(vocabSearch.isEmpty
                        ? "Add product names, people, or jargon you dictate often."
                        : "Try a different search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredVocabulary, id: \.self) { term in
                        HStack {
                            Text(term)
                                .font(.body)
                            Spacer()
                            Button {
                                appState.removeVocabularyTerm(term)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                        .listRowSeparator(.visible)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)

                if !appState.customVocabulary.isEmpty {
                    HStack {
                        Text("\(appState.customVocabulary.count) word(s)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("Clear all", role: .destructive) {
                            appState.clearVocabulary()
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var filteredVocabulary: [String] {
        let q = vocabSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return appState.customVocabulary }
        return appState.customVocabulary.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    // MARK: - Appearance (System Settings–style icon tiles)

    private var appearanceSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Appearance")
                    .font(.title2.weight(.semibold))

                // One grouped card like System Settings → Appearance
                VStack(spacing: 0) {
                    appearanceIconRow(
                        label: "Window",
                        items: RecordingWindowStyle.allCases.map { style in
                            AppearanceTileItem(
                                id: style.rawValue,
                                title: style.displayName,
                                isSelected: appState.recordingWindowStyle == style,
                                select: { appState.setRecordingWindowStyle(style) },
                                preview: { AnyView(recordingWindowPreview(style)) }
                            )
                        }
                    )

                    Divider().padding(.leading, 16)

                    appearanceIconRow(
                        label: "Liquid Glass",
                        items: LiquidGlassStyle.allCases.map { glass in
                            AppearanceTileItem(
                                id: glass.rawValue,
                                title: glass.displayName,
                                isSelected: appState.liquidGlassStyle == glass,
                                select: { appState.setLiquidGlassStyle(glass) },
                                preview: { AnyView(liquidGlassPreview(glass)) }
                            )
                        }
                    )

                    if appState.recordingWindowStyle == .classic {
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("Live draft")
                                .font(.body)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { appState.livePartialsEnabled },
                                set: { appState.setLivePartialsEnabled($0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
            .padding(20)
        }
    }

    /// System Settings–style row: left label, right icon tiles with short titles under them.
    private func appearanceIconRow(
        label: String,
        items: [AppearanceTileItem]
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(.body)
                .frame(width: 110, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                ForEach(items) { item in
                    Button(action: item.select) {
                        VStack(spacing: 8) {
                            item.preview()
                                .frame(width: 72, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            item.isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                            lineWidth: item.isSelected ? 2.5 : 1
                                        )
                                )
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(item.isSelected ? Color.primary : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Mini mock of Classic / Mini / None recording windows.
    private func recordingWindowPreview(_ style: RecordingWindowStyle) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.18, blue: 0.45),
                    Color(red: 0.25, green: 0.35, blue: 0.75),
                    Color(red: 0.45, green: 0.55, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            switch style {
            case .classic:
                VStack(spacing: 3) {
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 36, height: 3)
                    Capsule().fill(Color.white.opacity(0.55)).frame(width: 48, height: 3)
                    Capsule().fill(Color.white.opacity(0.40)).frame(width: 28, height: 3)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                )
                .frame(width: 56, height: 32)
            case .mini:
                HStack(spacing: 4) {
                    Circle().fill(Color.white.opacity(0.85)).frame(width: 5, height: 5)
                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 22, height: 4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.4)))
            case .none:
                Image(systemName: "eye.slash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    /// Liquid Glass Clear / Tinted swatches (same idea as System Settings).
    private func liquidGlassPreview(_ style: LiquidGlassStyle) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.10, blue: 0.55),
                    Color(red: 0.35, green: 0.20, blue: 0.85),
                    Color(red: 0.55, green: 0.40, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Capsule()
                .fill(Color.white.opacity(style == .clear ? 0.22 : 0.12))
                .frame(width: 40, height: 22)
                .overlay {
                    if #available(macOS 26.0, *) {
                        Capsule()
                            .fill(Color.clear)
                            .glassEffect(
                                style == .clear
                                    ? .clear
                                    : .regular.tint(Color.accentColor.opacity(0.55)),
                                in: Capsule()
                            )
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule().fill(
                                    style == .tinted
                                        ? Color.accentColor.opacity(0.35)
                                        : Color.white.opacity(0.15)
                                )
                            )
                    }
                }
                .overlay(
                    // Diagonal sheen like Apple’s glass tiles
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
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

                if appState.transcriptionProvider == .local {
                    Text("Speech model: \(appState.asrModelSize.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Change or download models in the Models tab.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
                Text("Recording window (Classic / Mini / None) is under Appearance.")
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

/// Icon tile for Appearance pickers (System Settings pattern).
private struct AppearanceTileItem: Identifiable {
    let id: String
    let title: String
    let isSelected: Bool
    let select: () -> Void
    let preview: () -> AnyView
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

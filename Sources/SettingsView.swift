import SwiftUI
import AppKit
import Carbon
import MacWisprCore

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
    @Environment(AppState.self) var appState
    /// Which pane to show (driven by main window sidebar).
    var pane: SettingsPane = .configuration

    @State private var newVocabTerm: String = ""
    @State private var vocabSearch: String = ""
    @State private var openAIKeyDraft: String = ""
    @State private var elevenLabsKeyDraft: String = ""
    @State private var keySaveMessage: String?
    @State private var keySaveIsError = false
    @State private var confirmClearHistory = false

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

    /// Configuration: speech model, shortcuts, mic and permissions, then general options.
    private var configurationSettings: some View {
        Form {
            transcriptionSettings
            ReduxRuntimeSettings()
            keyboardShortcutsSettings
            microphoneAndPermissionsSettings
            generalSettings
        }
        .formStyle(.grouped)
        .settingsColumn()
    }

    /// Sound = chimes only (hotkeys live under Configuration).
    private var soundSettings: some View {
        Form {
            soundAndChimesSection
        }
        .formStyle(.grouped)
        .settingsColumn()
    }

    @ViewBuilder
    private var generalSettings: some View {
        Group {
            Section {
                Picker("Insert text by", selection: Binding(
                    get: { appState.insertionMode },
                    set: { appState.setInsertionMode($0) }
                )) {
                    ForEach(InsertionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Toggle("Capitalize first letter", isOn: Bindable(appState).autoCapitalize)
                LabeledContent {
                    HStack(spacing: DS.Space.m) {
                        Slider(
                            value: Binding(
                                get: { appState.typingWPM },
                                set: { appState.setTypingWPM($0) }
                            ),
                            in: 20...200,
                            step: 5
                        )
                        .frame(width: 160)
                        Text("\(Int(appState.typingWPM)) WPM")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                } label: {
                    Text("Your typing speed")
                    Text("Used to estimate time saved")
                }
            } header: {
                Text("Text")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { appState.telemetryOptIn },
                    set: { appState.setTelemetryOptIn($0) }
                )) {
                    Text("Share anonymous usage data")
                    Text("Never includes your words or audio")
                }
                Button("What we collect…") {
                    appState.showTelemetryDisclosure = true
                }
                .buttonStyle(.link)
            } header: {
                Text("Privacy")
            }

            Section {
                if appState.reduxRuntimeConfiguration.runtime == .photon {
                    LabeledContent("Speech model") {
                        Button("Re-download") {
                            Task {
                                await appState.deleteDownloadedASRModel(appState.asrModelSize)
                                await appState.loadModel()
                            }
                        }
                        .disabled(appState.isModelLoading || appState.isRecording)
                    }
                }
                LabeledContent("History") {
                    Button("Clear All…", role: .destructive) {
                        confirmClearHistory = true
                    }
                    .disabled(appState.transcriptionHistory.isEmpty)
                }
            } header: {
                Text("Advanced")
            }
            .confirmationDialog(
                "Clear all transcription history?",
                isPresented: $confirmClearHistory
            ) {
                Button("Clear History", role: .destructive) { appState.clearHistory() }
            } message: {
                Text("This deletes \(appState.transcriptionHistory.count) dictations from this Mac and resets your stats.")
            }
        }
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

                // Voice STT
                catalogSection(icon: "waveform", title: "Voice") {
                    ForEach(ASRModelSize.dashboardChoices) { size in
                        voiceModelRow(size)
                        if size != ASRModelSize.dashboardChoices.last {
                            Divider().opacity(0.3).padding(.leading, 44)
                        }
                    }
                }

                // AI Models — SuperWhisper-style: polish packs gated behind experimental toggle
                catalogSection(icon: "atom", title: "AI Models") {
                    experimentalAIModelsToggleRow

                    if appState.showExperimentalAIModels {
                        Divider().opacity(0.3).padding(.leading, 14)
                        polishOffRow
                        // Only show packs that are downloadable or already on disk.
                        ForEach(PolishLocalModel.catalogCases.filter { $0.huggingfaceRepoId != nil || $0.isAvailable }) { model in
                            Divider().opacity(0.3).padding(.leading, 44)
                            llmModelRow(model)
                        }
                    }
                }

                // Cloud STT — icons only
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

    /// SuperWhisper-style row: “Show experimental models” + toggle.
    private var experimentalAIModelsToggleRow: some View {
        HStack(spacing: 12) {
            Text("Show experimental models")
                .font(.body)
            Button {
                // Tiny help affordance (popover)
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Optional on-device polish LLMs that clean up dictation after STT. Downloads only when you pick a pack.")
            Spacer(minLength: 8)
            Image(systemName: "atom")
                .font(.body)
                .foregroundStyle(.secondary)
            Toggle(
                "",
                isOn: Binding(
                    get: { appState.showExperimentalAIModels },
                    set: { appState.setShowExperimentalAIModels($0) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
            VStack(alignment: .leading, spacing: DS.Space.l) {
                PaneHeader(pane: .appearance, subtitle: "How the recording window looks while you speak.")
                    .padding(.horizontal, -DS.Space.xs)

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
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live draft")
                                Text("Show words as you speak")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                .card(padding: 0)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.l)
            .frame(maxWidth: DS.contentMaxWidth - 120)
            .frame(maxWidth: .infinity)
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
                                            item.isSelected ? Color.accentColor : DS.hairline,
                                            lineWidth: item.isSelected ? 2 : 1
                                        )
                                        .padding(item.isSelected ? -3 : 0)
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

    /// Wallpaper stand-in behind the appearance tiles (icon graphite + ember).
    private var previewBackdrop: some View {
        ZStack {
            LinearGradient(colors: [DS.graphiteTop, DS.graphiteBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [DS.ember.opacity(0.45), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 70)
        }
    }

    /// Mini mock of Classic / Mini / None recording windows.
    private func recordingWindowPreview(_ style: RecordingWindowStyle) -> some View {
        ZStack {
            previewBackdrop

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
            previewBackdrop

            Capsule()
                .fill(Color.white.opacity(style == .clear ? 0.22 : 0.12))
                .frame(width: 40, height: 22)
                .overlay {
                    // Material stand-in for Liquid Glass (macOS 26 SDK not on GHA yet).
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

    /// The one on-device model and its status. Nothing to pick.
    @ViewBuilder
    private var transcriptionSettings: some View {
        Group {
            Section {
                HStack(alignment: .center, spacing: 12) {
                    GlyphTile(systemImage: "waveform", size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ModelCatalog.shippedDisplayName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(speechStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if appState.isModelLoading {
                        ProgressView().controlSize(.small)
                    } else if appState.isReadyToDictate {
                        StatusDot(tone: .ready, text: "Ready")
                    } else {
                        Button(appState.modelLoadStatus.hasPrefix("Error") ? "Try Again" : "Set Up") {
                            Task { await appState.loadModel() }
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    PaneHeader(pane: .configuration, subtitle: "Speech model, shortcuts, microphone, and permissions.")
                    Text("Speech model")
                }
            }
        }
    }

    private var speechStatusText: String {
        if appState.isModelLoading {
            return appState.modelLoadStatus.isEmpty ? "Setting up…" : appState.modelLoadStatus
        }
        if appState.modelLoadStatus.hasPrefix("Error") { return appState.modelLoadStatus }
        return "\(appState.reduxRuntimeConfiguration.runtime.displayName) · Runs on this Mac. Your voice never leaves it."
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

    // MARK: - Keyboard shortcuts (Configuration)

    @ViewBuilder
    private var keyboardShortcutsSettings: some View {
        Group {
            Section {
                Picker("Dictation mode", selection: Binding(
                    get: { appState.dictationMode },
                    set: { appState.setDictationMode($0) }
                )) {
                    ForEach(DictationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                shortcutRow(
                    title: "Dictation",
                    subtitle: appState.dictationMode == .hold
                        ? "Hold to record, release when done"
                        : "Starts and stops recording",
                    chord: appState.dictationHotkey,
                    onRecorded: { appState.setDictationHotkey($0) },
                    onReset: { appState.resetDictationHotkey() },
                    requireSafeGlobal: true
                )
                shortcutRow(
                    title: "Cancel Recording",
                    subtitle: "Discards the active recording",
                    chord: appState.cancelHotkey,
                    onRecorded: { appState.setCancelHotkey($0) },
                    onReset: { appState.resetCancelHotkey() },
                    requireSafeGlobal: false
                )
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("\(appState.dictationMode.help) Click a shortcut to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shortcutRow(
        title: String,
        subtitle: String,
        chord: KeyChord,
        onRecorded: @escaping (KeyChord) -> Void,
        onReset: @escaping () -> Void,
        requireSafeGlobal: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                onReset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reset to default")

            ShortcutRecorderControl(
                chord: chord,
                requireSafeGlobal: requireSafeGlobal,
                onRecorded: onRecorded
            )
        }
        .padding(.vertical, 2)
    }

    private var soundAndChimesSection: some View {
        Section {
            Toggle("Play feedback sounds", isOn: Binding(
                get: { appState.soundFeedbackEnabled },
                set: { appState.setSoundFeedbackEnabled($0) }
            ))

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
                            set: { appState.setFeedbackSoundVolume(($0 * 20).rounded() / 20) }
                        ),
                        in: 0...1
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").foregroundStyle(.tertiary)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.tertiary)
                    }
                }

                chimePicker(
                    title: "Start",
                    selection: Binding(
                        get: { appState.startChime },
                        set: { appState.setStartChime($0) }
                    ),
                    preview: { FeedbackSounds.playListeningStarted() }
                )
                chimePicker(
                    title: "Stop",
                    selection: Binding(
                        get: { appState.stopChime },
                        set: { appState.setStopChime($0) }
                    ),
                    preview: { FeedbackSounds.playListeningStopped() }
                )
                chimePicker(
                    title: "Done",
                    selection: Binding(
                        get: { appState.successChime },
                        set: { appState.setSuccessChime($0) }
                    ),
                    preview: { FeedbackSounds.playSuccess() }
                )
                chimePicker(
                    title: "Error",
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
                    Spacer()
                    Button("Recheck mute") {
                        appState.refreshOutputMuteState()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        } header: {
            PaneHeader(pane: .sound, subtitle: "Chimes when recording starts, stops, and finishes.")
        }
        .onAppear {
            appState.refreshOutputMuteState()
        }
    }

    @ViewBuilder
    private var microphoneAndPermissionsSettings: some View {
        Group {
            Section {
                Picker("Input device", selection: Binding(
                    get: { appState.selectedInputDeviceUID },
                    set: { appState.setInputDeviceUID($0) }
                )) {
                    Text("System Default").tag("")
                    ForEach(appState.availableInputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                HStack {
                    Text(appState.selectedInputDeviceUID.isEmpty
                         ? "Following macOS: \(AudioInputDevices.defaultInputDeviceName())"
                         : "Applies on the next dictation.")
                    Spacer()
                    Button("Refresh") { appState.refreshInputDevices() }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if appState.accessibilityTrusted {
                        StatusDot(tone: .ready, text: "Granted")
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
                        StatusDot(tone: .ready, text: "Active")
                    } else {
                        Button("Repair Hotkey") {
                            appState.repairHotkey()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                HStack(alignment: .top) {
                    Text("Needed for the shortcut and for typing into other apps. After an update, re-enable MacWispr in Privacy & Security → Accessibility.")
                    Spacer()
                    Button("Setup checklist") { appState.reopenOnboarding() }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            appState.refreshInputDevices()
        }
    }

    private var aboutView: some View {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                VStack(spacing: DS.Space.m) {
                    Group {
                        if let logo = NSImage.appLogo {
                            Image(nsImage: logo).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            GlyphTile(systemImage: "mic.fill", size: 88)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .shadow(color: DS.ember.opacity(0.25), radius: 18, y: 8)

                    VStack(spacing: DS.Space.xs) {
                        Text("MacWispr")
                            .font(.system(size: 26, weight: .semibold))
                        Text("Private voice dictation for your Mac")
                            .foregroundStyle(.secondary)
                        Text("Version \(AppVersion.display)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }

                    Button("Check for Updates…") {
                        SparkleUpdater.shared.checkForUpdates()
                    }
                    .controlSize(.large)
                    .disabled(!SparkleUpdater.shared.canCheckForUpdates)
                    .padding(.top, DS.Space.xs)
                }

                VStack(spacing: 0) {
                    aboutRow(icon: "lock.shield", title: "On-device", detail: "\(ModelCatalog.shippedDisplayName) by Moondream. Your voice never leaves this Mac.")
                    Divider().padding(.leading, 44)
                    aboutRow(icon: "keyboard", title: "Shortcut", detail: "Hold or toggle \(appState.dictationHotkey.displayString). Change it in Configuration.")
                }
                .card(padding: 0)
                .frame(maxWidth: 420)

                HStack(spacing: DS.Space.l) {
                    Link("Website", destination: URL(string: "https://vasanthsreeram.github.io/macwispr/")!)
                    Text("·").foregroundStyle(.tertiary)
                    Link("GitHub", destination: URL(string: "https://github.com/vasanthsreeram/macwispr")!)
                    Text("·").foregroundStyle(.tertiary)
                    Link("Releases", destination: URL(string: "https://github.com/vasanthsreeram/macwispr/releases")!)
                }
                .font(.callout)

                Text("MIT License · Open source")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(DS.Space.xxl)
            .padding(.top, DS.Space.xl)
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
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
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

// MARK: - Click-to-record shortcut (SuperWhisper-style)

/// Click → “Recording…” → next key chord becomes the shortcut.
struct ShortcutRecorderControl: View {
    let chord: KeyChord
    var requireSafeGlobal: Bool = true
    let onRecorded: (KeyChord) -> Void

    @Environment(AppState.self) private var appState
    @State private var isRecording = false
    @State private var flashError = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording {
                stopRecording(commit: nil)
            } else {
                startRecording()
            }
        } label: {
            Group {
                if isRecording {
                    Text("Recording…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if flashError {
                    Text("Need ⌘/⌥/⌃")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    HStack(spacing: 4) {
                        ForEach(chord.badgeLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption.weight(.semibold).monospaced())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press keys now · Esc cancels" : "Click to record a new shortcut")
        .onDisappear {
            stopRecording(commit: nil)
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        flashError = false
        appState.hotkeyManager.isCapturingShortcut = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc alone → cancel capture
            if event.keyCode == UInt16(kVK_Escape),
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            {
                DispatchQueue.main.async { stopRecording(commit: nil) }
                return nil
            }
            guard let captured = KeyChord.from(event: event) else {
                return nil // swallow pure modifiers
            }
            if requireSafeGlobal, !captured.isSafeForGlobalDictation {
                DispatchQueue.main.async {
                    flashError = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        flashError = false
                    }
                }
                return nil
            }
            DispatchQueue.main.async {
                stopRecording(commit: captured)
            }
            return nil // swallow
        }
    }

    private func stopRecording(commit: KeyChord?) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        appState.hotkeyManager.isCapturingShortcut = false
        if let commit {
            onRecorded(commit)
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
    @Environment(AppState.self) var appState
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

// MARK: - Pane chrome

/// Title block at the top of a settings pane, matching its sidebar symbol.
struct PaneHeader: View {
    let pane: SettingsPane
    let subtitle: String

    var body: some View {
        HStack(spacing: DS.Space.m) {
            GlyphTile(systemImage: pane.systemImage, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.system(size: 20, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .textCase(nil)
        .padding(.bottom, DS.Space.s)
    }
}

extension View {
    /// Grouped forms read best at a fixed width; center them in wide windows.
    func settingsColumn() -> some View {
        self
            .frame(maxWidth: DS.contentMaxWidth - 80)
            .frame(maxWidth: .infinity)
    }
}

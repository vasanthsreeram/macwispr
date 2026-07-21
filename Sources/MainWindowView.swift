import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSidebar: SidebarItem = .home

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailView
        }
        .navigationTitle(selectedSidebar.title)
        .toolbar {
            // Mic picker (not start/stop) — dictate via ⌥Space or Dictate sidebar.
            ToolbarItem(placement: .primaryAction) {
                micInputToolbarMenu
            }
        }
        .onAppear {
            appState.refreshInputDevices()
        }
        .sheet(isPresented: $appState.showTelemetryDisclosure) {
            TelemetryDisclosureSheet(isRevisit: Telemetry.shared.hasSeenDisclosure)
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
    }

    /// Top-right: choose which microphone MacWispr uses for dictation.
    private var micInputToolbarMenu: some View {
        Menu {
            Button {
                appState.setInputDeviceUID("")
            } label: {
                let title = "System Default (\(AudioInputDevices.defaultInputDeviceName()))"
                if appState.selectedInputDeviceUID.isEmpty {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }
            if !appState.availableInputDevices.isEmpty {
                Divider()
                ForEach(appState.availableInputDevices) { device in
                    Button {
                        appState.setInputDeviceUID(device.uid)
                    } label: {
                        let label = AudioInputDevices.isSystemDefault(uid: device.uid)
                            ? "\(device.name) — macOS default"
                            : device.name
                        if appState.selectedInputDeviceUID == device.uid {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }
            Divider()
            Button("Refresh device list") {
                appState.refreshInputDevices()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mic.fill")
                Text(toolbarMicLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .help("Microphone: \(toolbarMicLabel)\nUsed for the next dictation.")
        .onAppear {
            appState.refreshInputDevices()
        }
    }

    private var toolbarMicLabel: String {
        if appState.selectedInputDeviceUID.isEmpty {
            return "Mic: \(AudioInputDevices.defaultInputDeviceName())"
        }
        return appState.availableInputDevices
            .first(where: { $0.uid == appState.selectedInputDeviceUID })?
            .name ?? "Microphone"
    }

    /// SuperWhisper-style left rail — one item per destination, no nested tab bar.
    private var sidebar: some View {
        List(selection: $selectedSidebar) {
            Section {
                Label("Home", systemImage: "house.fill")
                    .tag(SidebarItem.home)
            }

            Section("Library") {
                Label("Models", systemImage: "square.stack.3d.up.fill")
                    .tag(SidebarItem.models)
                Label("Vocabulary", systemImage: "text.book.closed.fill")
                    .tag(SidebarItem.vocabulary)
            }

            Section("App") {
                Label("Appearance", systemImage: "paintbrush.fill")
                    .tag(SidebarItem.appearance)
                Label("Configuration", systemImage: "gearshape.fill")
                    .tag(SidebarItem.configuration)
                Label("Sound", systemImage: "speaker.wave.2.fill")
                    .tag(SidebarItem.sound)
            }

            Section {
                Label("History", systemImage: "clock.fill")
                    .tag(SidebarItem.history)
                Label("About", systemImage: "info.circle.fill")
                    .tag(SidebarItem.about)
            }
        }
        .listStyle(.sidebar)
    }

    private var detailView: some View {
        Group {
            switch selectedSidebar {
            case .home:
                DashboardView()
            case .models:
                SettingsView(pane: .models)
            case .vocabulary:
                SettingsView(pane: .vocabulary)
            case .appearance:
                SettingsView(pane: .appearance)
            case .configuration:
                SettingsView(pane: .configuration)
            case .sound:
                SettingsView(pane: .sound)
            case .history:
                historyDetail
            case .about:
                SettingsView(pane: .about)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedSidebar) { _, item in
            // Content-free nav telemetry (whitelisted surfaces only).
            switch item {
            case .home: Telemetry.shared.reportUIOpen(surface: "dashboard")
            case .history: Telemetry.shared.reportUIOpen(surface: "history")
            case .configuration, .models, .vocabulary, .appearance, .sound, .about:
                Telemetry.shared.reportUIOpen(surface: "settings")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macWisprShowSettings)) { _ in
            // Menu “Settings…” → Configuration (not a nested tab strip).
            selectedSidebar = .configuration
        }
    }

    private var historyDetail: some View {
        Group {
            if appState.transcriptionHistory.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "text.bubble",
                    description: Text("Your dictations will appear here and feed the weekly dashboard.")
                )
            } else {
                List {
                    ForEach(appState.transcriptionHistory) { entry in
                        EditableHistoryRow(entry: entry)
                    }
                }
            }
        }
    }

}

/// History row with inline edit; saving learns new words into custom vocabulary.
/// When polish ran, shows Polished + Raw with independent copy actions.
private struct EditableHistoryRow: View {
    @EnvironmentObject var appState: AppState
    let entry: TranscriptionEntry
    @State private var isEditing = false
    @State private var draft: String = ""
    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 140)
                    .scrollContentBackground(.hidden)
                HStack {
                    Text("Corrected words join your custom vocabulary.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        isEditing = false
                    }
                    Button("Save") {
                        appState.commitHistoryEdit(id: entry.id, newText: draft)
                        isEditing = false
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            } else {
                // Final / polished text (what was inserted).
                VStack(alignment: .leading, spacing: 4) {
                    if entry.hasRaw {
                        HStack(spacing: 6) {
                            Text(entry.hasDistinctRaw ? "Polished" : "Result")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if entry.hasDistinctRaw {
                                Text("changed by polish")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("polish left unchanged")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                appState.copyTextToClipboard(entry.text)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .help("Copy polished / final text")
                        }
                    }
                    Text(entry.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Raw STT (pre-polish) — expand when present.
                if entry.hasRaw, let raw = entry.rawText {
                    DisclosureGroup(isExpanded: $showRaw) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(raw)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                Button {
                                    appState.copyTextToClipboard(raw)
                                } label: {
                                    Label("Copy raw", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                Spacer()
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text(entry.hasDistinctRaw ? "Raw (before polish)" : "Raw STT")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    // Open by default when polish actually changed the text.
                    .onAppear {
                        if entry.hasDistinctRaw { showRaw = true }
                    }
                }

                HStack(spacing: 8) {
                    Text(entry.timestamp, style: .date)
                    Text(entry.timestamp, style: .time)
                    Text("•")
                    Text(String(format: "%.1fs", entry.duration))
                    Text("•")
                    Text("\(entry.wordCount) words")
                    Spacer()
                    Button("Edit") {
                        draft = entry.text
                        isEditing = true
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit") {
                draft = entry.text
                isEditing = true
            }
            Button("Copy polished") {
                appState.copyTextToClipboard(entry.text)
            }
            if let raw = entry.rawText, entry.hasRaw {
                Button("Copy raw") {
                    appState.copyTextToClipboard(raw)
                }
            }
        }
    }
}

private enum SidebarItem: Hashable {
    case home
    case models
    case vocabulary
    case appearance
    case configuration
    case sound
    case history
    case about

    var title: String {
        switch self {
        case .home: return "Home"
        case .models: return "Models"
        case .vocabulary: return "Vocabulary"
        case .appearance: return "Appearance"
        case .configuration: return "Configuration"
        case .sound: return "Sound"
        case .history: return "History"
        case .about: return "About"
        }
    }
}

extension Notification.Name {
    static let macWisprShowSettings = Notification.Name("macWisprShowSettings")
}

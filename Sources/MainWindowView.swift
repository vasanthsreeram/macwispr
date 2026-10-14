import SwiftUI
import MacWisprCore

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSidebar: MainPane

    init(initialPane: MainPane = .home) {
        _selectedSidebar = State(initialValue: initialPane)
    }

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
        HStack(spacing: 5) {
            Image(systemName: "mic.fill")
            Text(toolbarMicLabel)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .allowsHitTesting(false)
        .overlay {
            GeometryReader { _ in
                AppKitPullDownMenu(
                    items: toolbarMicMenuItems,
                    accessibilityLabel: "Microphone \(toolbarMicLabel)",
                    toolTip: "Microphone: \(toolbarMicLabel)\nUsed for the next dictation."
                )
            }
        }
        .help("Microphone: \(toolbarMicLabel)\nUsed for the next dictation.")
        .onAppear {
            appState.refreshInputDevices()
        }
    }

    private var toolbarMicMenuItems: [AppKitSafeMenuItem] {
        var items: [AppKitSafeMenuItem] = [
            .action(
                title: "System Default",
                checked: appState.selectedInputDeviceUID.isEmpty
            ) {
                appState.setInputDeviceUID("")
            }
        ]
        if !appState.availableInputDevices.isEmpty {
            items.append(.separator)
            for device in appState.availableInputDevices {
                let uid = device.uid
                items.append(.action(
                    title: device.name.isEmpty ? "Microphone" : device.name,
                    checked: appState.selectedInputDeviceUID == uid
                ) {
                    appState.setInputDeviceUID(uid)
                })
            }
        }
        items.append(.separator)
        items.append(.action(title: "Refresh device list") {
            appState.refreshInputDevices()
        })
        return items
    }

    private var toolbarMicLabel: String {
        if appState.selectedInputDeviceUID.isEmpty {
            return "Mic: \(AudioInputDevices.defaultInputDeviceName())"
        }
        return appState.availableInputDevices
            .first(where: { $0.uid == appState.selectedInputDeviceUID })?
            .name ?? "Microphone"
    }

    /// Three destinations only: Home, History, Settings.
    private var sidebar: some View {
        List(selection: $selectedSidebar) {
            ForEach(MainPane.allCases, id: \.self) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
        }
        .listStyle(.sidebar)
    }

    private var detailView: some View {
        Group {
            switch selectedSidebar {
            case .home:
                DashboardView()
            case .history:
                historyDetail
            case .settings:
                SimpleSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedSidebar) { _, item in
            // Content-free nav telemetry (whitelisted surfaces only).
            switch item {
            case .home: Telemetry.shared.reportUIOpen(surface: "dashboard")
            case .history: Telemetry.shared.reportUIOpen(surface: "history")
            case .settings: Telemetry.shared.reportUIOpen(surface: "settings")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macWisprShowSettings)) { _ in
            selectedSidebar = .settings
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
private struct EditableHistoryRow: View {
    @EnvironmentObject var appState: AppState
    let entry: TranscriptionEntry
    @State private var isEditing = false
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
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
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            }
        }
    }
}

extension Notification.Name {
    static let macWisprShowSettings = Notification.Name("macWisprShowSettings")
    static let macWisprShowLeaderboard = Notification.Name("macWisprShowLeaderboard")
}

import SwiftUI
import MacWisprCore

struct MainWindowView: View {
    @Environment(AppState.self) var appState
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
        .sheet(isPresented: Bindable(appState).showTelemetryDisclosure) {
            TelemetryDisclosureSheet(isRevisit: Telemetry.shared.hasSeenDisclosure)
                .environment(appState)
        }
        .sheet(isPresented: Bindable(appState).showOnboarding) {
            OnboardingView()
                .environment(appState)
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

    private var sidebar: some View {
        List(selection: $selectedSidebar) {
            ForEach(MainPane.sidebarSections.indices, id: \.self) { i in
                Section {
                    ForEach(MainPane.sidebarSections[i], id: \.self) { pane in
                        Label(pane.title, systemImage: pane.systemImage)
                            .tag(pane)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarStatus
        }
    }

    /// Always-visible readiness and shortcut at the foot of the sidebar.
    private var sidebarStatus: some View {
        let status = appState.readiness
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            StatusDot(tone: status.tone, text: status.text)
            HStack(spacing: 6) {
                Text(appState.dictationMode == .hold ? "Hold" : "Press")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Keycaps(keys: appState.dictationHotkey.badgeLabels, size: 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private var detailView: some View {
        Group {
            switch selectedSidebar {
            case .home:
                DashboardView()
            case .appearance:
                SettingsView(pane: .appearance)
            case .configuration:
                SettingsView(pane: .configuration)
            case .sound:
                SettingsView(pane: .sound)
            case .history:
                historyDetail
            case .meetings:
                MeetingsView()
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
            case .meetings: break
            case .appearance, .configuration, .sound, .about:
                Telemetry.shared.reportUIOpen(surface: "settings")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macWisprShowSettings)) { _ in
            selectedSidebar = MainPane.settings
        }
    }

    private var historyDetail: some View {
        HistoryPane()
    }

}

/// Dictation history grouped by day, with search.
private struct HistoryPane: View {
    @Environment(AppState.self) var appState
    @State private var query = ""

    private struct DayGroup: Identifiable {
        let id: Date
        let title: String
        let entries: [TranscriptionEntry]
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        return f
    }()

    private var groups: [DayGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        var result: [DayGroup] = []
        var current: [TranscriptionEntry] = []
        var currentDay: Date?
        for entry in appState.transcriptionHistory {
            if entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if !q.isEmpty, !entry.text.localizedCaseInsensitiveContains(q) { continue }
            let day = calendar.startOfDay(for: entry.timestamp)
            if day != currentDay, let d = currentDay {
                result.append(DayGroup(id: d, title: Self.title(for: d), entries: current))
                current = []
            }
            currentDay = day
            current.append(entry)
        }
        if let d = currentDay, !current.isEmpty {
            result.append(DayGroup(id: d, title: Self.title(for: d), entries: current))
        }
        return result
    }

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return dayFormatter.string(from: day)
    }

    var body: some View {
        let groups = groups
        Group {
            if appState.transcriptionHistory.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "waveform",
                    description: Text("Hold \(appState.dictationHotkey.displayString) and speak. Your dictations appear here.")
                )
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                EditableHistoryRow(entry: entry)
                            }
                        } header: {
                            HStack {
                                Text(group.title)
                                Spacer()
                                Text("\(group.entries.reduce(0) { $0 + $1.wordCount }.formatted()) words")
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search dictations")
    }
}

/// History row with inline edit; saving learns new words into custom vocabulary.
private struct EditableHistoryRow: View {
    @Environment(AppState.self) var appState
    let entry: TranscriptionEntry
    @State private var isEditing = false
    @State private var isHovering = false
    @State private var draft: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text(entry.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if isEditing {
                    TextEditor(text: $draft)
                        .font(.system(size: 13))
                        .frame(minHeight: 60, maxHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: DS.Radius.s))
                    HStack {
                        Text("Corrected words join your custom vocabulary.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { isEditing = false }
                        Button("Save") {
                            appState.commitHistoryEdit(id: entry.id, newText: draft)
                            isEditing = false
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                } else {
                    Text(entry.text)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                    Text("\(entry.wordCount) words · \(String(format: "%.1fs", entry.duration))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isEditing {
                HStack(spacing: 2) {
                    rowIcon("doc.on.doc", label: "Copy") { copy() }
                    rowIcon("pencil", label: "Edit") { beginEdit() }
                }
                .opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.vertical, 6)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy") { copy() }
            Button("Edit") { beginEdit() }
        }
    }

    private func rowIcon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 22)
            .appKitTap(label, action: action)
            .help(label)
    }

    private func beginEdit() {
        draft = entry.text
        isEditing = true
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }
}

extension Notification.Name {
    static let macWisprShowSettings = Notification.Name("macWisprShowSettings")
    static let macWisprShowLeaderboard = Notification.Name("macWisprShowLeaderboard")
}

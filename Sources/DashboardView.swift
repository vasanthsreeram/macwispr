import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    private var stats: UsageStats { UsageStats(typingWPM: appState.typingWPM) }
    private var week: UsageStats.Snapshot { stats.weeklySnapshot(entries: appState.transcriptionHistory) }
    private var allTime: UsageStats.Snapshot { stats.allTimeSnapshot(entries: appState.transcriptionHistory) }
    private var days: [UsageStats.DayBucket] { stats.lastSevenDays(entries: appState.transcriptionHistory) }
    private var maxWords: Int { max(days.map(\.words).max() ?? 1, 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                weekCards
                weeklyChart
                allTimeRow
                leaderboardRow
                tip
            }
            .padding(20)
        }
    }

    private var leaderboardRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Leaderboard", systemImage: "trophy.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Board") {
                    appState.openPublicLeaderboard()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if appState.leaderboardOptIn {
                HStack(spacing: 14) {
                    LeaderboardAvatarView(
                        animal: appState.leaderboardAnimal,
                        avatarKey: appState.leaderboardAvatarKey.isEmpty
                            ? appState.leaderboardDisplayName
                            : appState.leaderboardAvatarKey,
                        size: 56
                    )

                    // Big rank — primary Home signal
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rankHeadline)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(rankColor)
                        Text(nameLine)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(statsLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                if appState.leaderboardRank == nil || appState.leaderboardDisplayName.isEmpty {
                    Text("Syncing your rank…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not on the board")
                            .font(.subheadline.weight(.semibold))
                        Text("Opt in under Configuration → Privacy. Anonymous animals only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.45)))
        .onAppear {
            appState.refreshLeaderboardStanding()
            if appState.leaderboardOptIn {
                appState.syncLeaderboardIfNeeded(force: false)
            }
        }
    }

    private var rankHeadline: String {
        if let rank = appState.leaderboardRank {
            return "#\(rank)"
        }
        return "#—"
    }

    private var rankColor: Color {
        switch appState.leaderboardRank {
        case 1: return Color(red: 0.79, green: 0.54, blue: 0.07)
        case 2: return Color(red: 0.48, green: 0.48, blue: 0.51)
        case 3: return Color(red: 0.69, green: 0.42, blue: 0.24)
        default: return .primary
        }
    }

    private var nameLine: String {
        if !appState.leaderboardShortName.isEmpty {
            return appState.leaderboardShortName
        }
        if !appState.leaderboardDisplayName.isEmpty {
            return appState.leaderboardDisplayName.replacingOccurrences(of: "Anonymous ", with: "")
        }
        return "Anonymous speaker"
    }

    private var statsLine: String {
        let local = appState.currentLeaderboardStats()
        let remote = appState.leaderboardRemoteStats
        let streak = remote.streakDays > 0 ? remote.streakDays : local.streakDays
        let saved = remote.timeSavedMinutes > 0 ? remote.timeSavedMinutes : local.timeSavedMinutes
        let words = remote.words > 0 ? remote.words : local.words
        let dicts = remote.dictations > 0 ? remote.dictations : local.dictations
        // Rank is by words; lead with that.
        return "\(Self.shortCount(words)) words · \(Self.shortCount(dicts))× · \(streak)d · \(Self.shortDuration(minutes: saved))"
    }

    private static func shortDuration(minutes: Double) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            if h >= 10 { return "\(Int(h.rounded()))h" }
            return String(format: "%.1fh", h).replacingOccurrences(of: ".0h", with: "h")
        }
        return "\(max(0, Int(minutes.rounded())))m"
    }

    private static func shortCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0M", with: "M") }
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000).replacingOccurrences(of: ".0k", with: "k") }
        return "\(n)"
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time Saved")
                    .font(.title2.weight(.semibold))
                Text("Last 7 days · typing baseline \(Int(appState.typingWPM)) WPM")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(alignment: .top, spacing: 10) {
                micQuickSwitch
                modelQuickSwitch
            }
        }
        .onAppear {
            appState.refreshInputDevices()
        }
    }

    /// Quick mic picker (same devices as toolbar / menu bar).
    private var micQuickSwitch: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Menu {
                Button {
                    appState.setInputDeviceUID("")
                } label: {
                    if appState.selectedInputDeviceUID.isEmpty {
                        Label("System Default", systemImage: "checkmark")
                    } else {
                        Text("System Default")
                    }
                }
                if !appState.availableInputDevices.isEmpty {
                    Divider()
                    ForEach(appState.availableInputDevices) { device in
                        Button {
                            appState.setInputDeviceUID(device.uid)
                        } label: {
                            if appState.selectedInputDeviceUID == device.uid {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                }
                Divider()
                Button("Refresh device list") {
                    appState.refreshInputDevices()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.caption.weight(.semibold))
                    Text(dashboardMicLabel)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.7), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Microphone used for dictation")

            Text(appState.selectedInputDeviceUID.isEmpty ? "System default" : "Selected")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var dashboardMicLabel: String {
        if appState.selectedInputDeviceUID.isEmpty {
            let name = AudioInputDevices.defaultInputDeviceName()
            return name.count > 18 ? String(name.prefix(16)) + "…" : name
        }
        let name = appState.availableInputDevices
            .first(where: { $0.uid == appState.selectedInputDeviceUID })?
            .name ?? "Mic"
        return name.count > 18 ? String(name.prefix(16)) + "…" : name
    }

    /// Top-right chip: current STT model / provider with a one-click switcher.
    private var modelQuickSwitch: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Menu {
                Section("Local") {
                    ForEach(ASRModelSize.dashboardChoices) { size in
                        Button {
                            appState.setTranscriptionProvider(.local)
                            appState.setASRModelSize(size)
                        } label: {
                            if isSelectedLocalModel(size) {
                                Label(size.displayName, systemImage: "checkmark")
                            } else {
                                Text(size.displayName)
                            }
                        }
                        .disabled(appState.isModelLoading || appState.isRecording)
                    }
                }
                Section("Cloud (BYOK)") {
                    Button {
                        appState.setTranscriptionProvider(.openAI)
                    } label: {
                        if appState.transcriptionProvider == .openAI {
                            Label("OpenAI", systemImage: "checkmark")
                        } else {
                            Text("OpenAI")
                        }
                    }
                    Button {
                        appState.setTranscriptionProvider(.elevenLabs)
                    } label: {
                        if appState.transcriptionProvider == .elevenLabs {
                            Label("ElevenLabs", systemImage: "checkmark")
                        } else {
                            Text("ElevenLabs")
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if appState.isModelLoading && appState.transcriptionProvider == .local {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: modelChipSymbol)
                            .font(.caption.weight(.semibold))
                    }
                    Text(modelChipTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.7), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(appState.isRecording)
            .help(modelChipHelp)

            if appState.isModelLoading, appState.transcriptionProvider == .local {
                Text(appState.modelLoadStatus.isEmpty ? "Loading…" : appState.modelLoadStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 200, alignment: .trailing)
            } else if !appState.isReadyToDictate, appState.transcriptionProvider != .local {
                Text("Add API key in Settings")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text(modelChipSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var modelChipTitle: String {
        switch appState.transcriptionProvider {
        case .local:
            // Clean chip label; specific model is in the menu + subtitle.
            return "Local"
        case .openAI:
            return "OpenAI"
        case .elevenLabs:
            return "ElevenLabs"
        }
    }

    private var modelChipSymbol: String {
        switch appState.transcriptionProvider {
        case .local:
            return "laptopcomputer"
        case .openAI, .elevenLabs:
            return "cloud"
        }
    }

    private var modelChipHelp: String {
        switch appState.transcriptionProvider {
        case .local:
            return "\(appState.asrModelSize.displayName)\n\(appState.asrModelSize.subtitle)"
        case .openAI:
            return "Cloud STT via your OpenAI key"
        case .elevenLabs:
            return "Cloud STT via your ElevenLabs key"
        }
    }

    /// Second line under the chip — which local engine, not the chip title.
    private var modelChipSubtitle: String {
        switch appState.transcriptionProvider {
        case .local:
            return appState.asrModelSize.shortName
        case .openAI, .elevenLabs:
            return "Cloud · BYOK"
        }
    }

    private func isSelectedLocalModel(_ size: ASRModelSize) -> Bool {
        guard appState.transcriptionProvider == .local else { return false }
        // Legacy Parakeet-INT4 maps to the same INT8 weights as parakeetInt8.
        if size == .parakeetInt8 {
            return appState.asrModelSize == .parakeetInt8 || appState.asrModelSize == .parakeetInt4
        }
        return appState.asrModelSize == size
    }

    private var weekCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                title: "Time Saved",
                value: week.formattedTimeSaved,
                subtitle: "vs typing",
                systemImage: "clock.arrow.circlepath",
                tint: .green
            )
            StatCard(
                title: "Words",
                value: week.words.formatted(),
                subtitle: "\(week.dictations) dictations",
                systemImage: "text.word.spacing",
                tint: .blue
            )
            StatCard(
                title: "Spoken",
                value: week.formattedAudio,
                subtitle: "audio captured",
                systemImage: "waveform",
                tint: .purple
            )
        }
    }

    private var weeklyChart: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Words per day")
                    .font(.headline)

                if week.words == 0 {
                    ContentUnavailableView(
                        "No dictations this week",
                        systemImage: "mic.badge.plus",
                        description: Text("Hold ⌥Space, speak, release — text lands in the focused app. Time saved appears here after your first dictation.")
                    )
                    .frame(height: 180)
                } else {
                    Chart(days) { day in
                        BarMark(
                            x: .value("Day", day.label),
                            y: .value("Words", day.words)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor.opacity(0.7), .accentColor],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(4)
                    }
                    .chartYScale(domain: 0...max(maxWords + maxWords / 5, 10))
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 200)
                }
            }
            .padding(8)
        }
    }

    private var allTimeRow: some View {
        GroupBox("All time") {
            HStack(spacing: 24) {
                labeledValue("Words", allTime.words.formatted())
                labeledValue("Dictations", allTime.dictations.formatted())
                labeledValue("Time saved", allTime.formattedTimeSaved)
                Spacer()
            }
            .padding(8)
        }
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            Text("Time saved estimates how long the same text would take to type at \(Int(appState.typingWPM)) WPM, minus the time you spent speaking. Adjust the baseline in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func labeledValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }
}

// MARK: - Cute animal avatar (deterministic, non-identifying)

struct LeaderboardAvatarView: View {
    let animal: String
    let avatarKey: String
    var size: CGFloat = 48

    private static let emoji: [String: String] = [
        "Otter": "🦦", "Fox": "🦊", "Wren": "🐦", "Lynx": "🐱", "Heron": "🦩", "Pika": "🐹",
        "Moth": "🦋", "Seal": "🦭", "Badger": "🦡", "Crane": "🦢", "Dove": "🕊️", "Elk": "🦌",
        "Finch": "🐤", "Gecko": "🦎", "Hare": "🐰", "Ibis": "🪿", "Jay": "🦜", "Koala": "🐨",
        "Lark": "🐦", "Mink": "🦫", "Newt": "🐸", "Orca": "🐋", "Puffin": "🐧", "Quail": "🐥",
        "Raven": "🐦‍⬛", "Swan": "🦢", "Teal": "🦆", "Urchin": "🦔", "Vole": "🐭", "Wolf": "🐺",
        "Yak": "🐂", "Zebu": "🐮",
    ]
    private static let hats = ["🎩", "👑", "🎀", "🧢", "⛑️", "🎓", "🌟", "✨"]
    private static let palettes: [(Color, Color)] = [
        (Color(red: 1, green: 0.84, blue: 0.88), Color(red: 1, green: 0.56, blue: 0.67)),
        (Color(red: 0.79, green: 0.94, blue: 0.97), Color(red: 0.28, green: 0.79, blue: 0.89)),
        (Color(red: 0.91, green: 0.93, blue: 0.79), Color(red: 0.68, green: 0.76, blue: 0.47)),
        (Color(red: 0.99, green: 0.89, blue: 0.89), Color(red: 0.96, green: 0.64, blue: 0.38)),
        (Color(red: 0.88, green: 0.67, blue: 1), Color(red: 0.62, green: 0.31, blue: 0.87)),
        (Color(red: 0.85, green: 0.95, blue: 0.86), Color(red: 0.32, green: 0.72, blue: 0.53)),
    ]

    var body: some View {
        let h = Self.fnv(avatarKey.isEmpty ? animal : avatarKey)
        let pal = Self.palettes[Int(h % UInt32(Self.palettes.count))]
        let emoji = Self.emoji[animal.isEmpty ? "Otter" : animal] ?? "🐾"
        let hat = Self.hats[Int(h % UInt32(Self.hats.count))]

        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(LinearGradient(colors: [pal.0, pal.1], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(emoji)
                .font(.system(size: size * 0.46))
            Text(hat)
                .font(.system(size: size * 0.22))
                .offset(x: size * 0.22, y: -size * 0.28)
                .rotationEffect(.degrees(16))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .accessibilityHidden(true)
    }

    private static func fnv(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 {
            h ^= UInt32(b)
            h = h &* 16_777_619
        }
        return h
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

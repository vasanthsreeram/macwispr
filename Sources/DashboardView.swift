import SwiftUI
import AppKit
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
            }
            .padding(20)
        }
    }

    /// Compact Home strip → full Leaderboard pane for join / name / rank.
    private var leaderboardRow: some View {
        HStack(spacing: 14) {
            if appState.leaderboardOptIn {
                LeaderboardAvatarView(
                    animal: appState.leaderboardAnimal.isEmpty ? "Otter" : appState.leaderboardAnimal,
                    avatarKey: appState.leaderboardAvatarKey.isEmpty
                        ? appState.leaderboardDisplayName
                        : appState.leaderboardAvatarKey,
                    size: 48
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(rankHeadline)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(rankColor)
                    Text(nameLine)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(statsLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboard")
                        .font(.subheadline.weight(.semibold))
                    Text("Join, pick a name, see your rank")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.45)))
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .overlay {
            GeometryReader { _ in
                AppKitClickTarget(
                    accessibilityLabel: appState.leaderboardOptIn
                        ? "\(rankHeadline) \(nameLine)"
                        : "Leaderboard",
                    action: {
                        NotificationCenter.default.post(name: .macWisprShowLeaderboard, object: nil)
                    }
                )
            }
        }
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
                Text("This week")
                    .font(.title2.weight(.semibold))
                Text("Hold \(appState.dictationHotkey.displayString), speak, let go. Your words appear where you are typing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            readinessPill
        }
        .onAppear {
            appState.refreshInputDevices()
        }
    }

    /// Quick mic picker (same devices as toolbar / menu bar).
    private var micQuickSwitch: some View {
        VStack(alignment: .trailing, spacing: 4) {
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
            .allowsHitTesting(false)
            .overlay {
                GeometryReader { _ in
                    AppKitPullDownMenu(
                        items: micMenuItems,
                        accessibilityLabel: "Microphone \(dashboardMicLabel)",
                        toolTip: "Microphone used for dictation"
                    )
                }
            }
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

    private var micMenuItems: [AppKitSafeMenuItem] {
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
                let title = device.name.isEmpty ? "Microphone" : device.name
                items.append(.action(
                    title: title,
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

    /// One glanceable status: ready, setting up (with progress), or needs attention.
    private var readinessPill: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                if appState.isModelLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: pillOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(pillOK ? .green : .orange)
                }
                Text(pillTitle)
                    .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.7), in: Capsule())
            if appState.isModelLoading {
                ProgressView(value: appState.modelLoadProgress)
                    .frame(width: 180)
                Text(appState.modelLoadStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !appState.accessibilityTrusted || !appState.hotkeyArmed {
                Button(appState.accessibilityTrusted ? "Fix Shortcut" : "Turn on Accessibility…") {
                    appState.repairHotkey()
                }
                .controlSize(.small)
            } else if !appState.isReadyToDictate {
                Button("Set Up") { Task { await appState.loadModel() } }
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var pillOK: Bool {
        appState.isReadyToDictate && appState.accessibilityTrusted && appState.hotkeyArmed
    }

    private var pillTitle: String {
        if appState.isModelLoading { return "Setting up…" }
        if !appState.isReadyToDictate { return "Speech model not ready" }
        if !appState.accessibilityTrusted { return "Needs Accessibility" }
        if !appState.hotkeyArmed { return "Shortcut not active" }
        return "Ready · hold \(appState.dictationHotkey.displayString)"
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

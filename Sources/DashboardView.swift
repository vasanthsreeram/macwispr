import SwiftUI
import AppKit
import Charts

struct DashboardView: View {
    @Environment(AppState.self) var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: UsageStats.Summary { appState.usageSummary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                hero
                statRow
                weeklyChart
                allTimeStrip
            }
            .padding(.horizontal, DS.Space.xxl)
            .padding(.vertical, DS.Space.xl)
            .frame(maxWidth: DS.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .onAppear { appState.refreshUsageSummary() }
    }

    // MARK: Hero

    private var hero: some View {
        let status = appState.readiness
        return VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(alignment: .center) {
                StatusDot(tone: status.tone, text: status.text)
                Spacer()
                heroAction
            }

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Time saved this week")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(summary.week.formattedTimeSaved)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: summary.week.formattedTimeSaved)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            HStack(spacing: DS.Space.s) {
                Text("Hold")
                Keycaps(keys: appState.dictationHotkey.badgeLabels, size: 12, onDark: true)
                Text("anywhere, speak, let go.")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)

            if appState.isModelLoading {
                ProgressView(value: appState.modelLoadProgress)
                    .tint(DS.ember)
                Text(appState.modelLoadStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandSurface()
    }

    @ViewBuilder
    private var heroAction: some View {
        if appState.isModelLoading {
            EmptyView()
        } else if !appState.accessibilityTrusted || !appState.hotkeyArmed {
            pillButton(appState.accessibilityTrusted ? "Fix Shortcut" : "Turn On Accessibility") {
                appState.repairHotkey()
            }
        } else if !appState.isReadyToDictate {
            pillButton("Set Up") { Task { await appState.loadModel() } }
        } else if summary.streakDays > 1 {
            Label("\(summary.streakDays)-day streak", systemImage: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.ember)
        }
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white))
            .appKitTap(title, action: action)
            .fixedSize()
    }

    // MARK: Stats

    private var statRow: some View {
        HStack(spacing: DS.Space.m) {
            StatCard(
                title: "Words",
                value: summary.week.words.formatted(),
                subtitle: "\(summary.week.dictations) dictations",
                systemImage: "text.word.spacing"
            )
            StatCard(
                title: "Spoken",
                value: summary.week.formattedAudio,
                subtitle: "audio captured",
                systemImage: "waveform"
            )
            StatCard(
                title: "Speed",
                value: speakingWPM.map { "\($0)" } ?? "—",
                subtitle: "WPM vs \(Int(appState.typingWPM)) typing",
                systemImage: "gauge.with.dots.needle.67percent"
            )
        }
    }

    /// Effective dictation speed this week.
    private var speakingWPM: Int? {
        let minutes = summary.week.audioSeconds / 60
        guard minutes > 0.05 else { return nil }
        return Int((Double(summary.week.words) / minutes).rounded())
    }

    // MARK: Chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionLabel(title: "Words per day", trailing: "Last 7 days")

            if summary.week.words == 0 {
                VStack(spacing: DS.Space.s) {
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("No dictations this week")
                        .font(.system(size: 13, weight: .medium))
                    Text("Your words per day show up here after your first dictation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(summary.days) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Words", day.words),
                        width: .ratio(0.5)
                    )
                    .foregroundStyle(isToday(day) ? DS.ember : Color.primary.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .annotation(position: .top, spacing: 4) {
                        if day.words > 0 {
                            Text(Self.compact(day.words))
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(isToday(day) ? DS.ember : Color.secondary)
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(height: 170)
            }
        }
        .card(padding: DS.Space.l + 4)
    }

    private func isToday(_ day: UsageStats.DayBucket) -> Bool {
        Calendar.current.isDateInToday(day.date)
    }

    // MARK: All time

    private var allTimeStrip: some View {
        HStack(spacing: 0) {
            allTimeValue("Words", summary.allTime.words.formatted())
            divider
            allTimeValue("Dictations", summary.allTime.dictations.formatted())
            divider
            allTimeValue("Time saved", summary.allTime.formattedTimeSaved)
        }
        .card(padding: DS.Space.l)
        .overlay(alignment: .topLeading) {
            Text("All time")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.leading, DS.Space.l)
                .offset(y: -18)
        }
        .padding(.top, DS.Space.s)
    }

    private var divider: some View {
        Rectangle().fill(DS.hairline).frame(width: 1, height: 28)
    }

    private func allTimeValue(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    static func compact(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000).replacingOccurrences(of: ".0k", with: "k") }
        return "\(n)"
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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .card()
    }
}

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
                tip
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time Saved")
                .font(.title2.weight(.semibold))
            Text("Last 7 days · typing baseline \(Int(appState.typingWPM)) WPM")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
                        description: Text("Hold ⌥Space and speak — stats show up here.")
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

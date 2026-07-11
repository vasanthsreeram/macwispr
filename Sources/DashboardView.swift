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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time Saved")
                    .font(.title2.weight(.semibold))
                Text("Last 7 days · typing baseline \(Int(appState.typingWPM)) WPM")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            modelQuickSwitch
        }
    }

    /// Top-right chip: current STT model / provider with a one-click switcher.
    private var modelQuickSwitch: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Menu {
                Section("On-device") {
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

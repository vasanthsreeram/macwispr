import SwiftUI

/// Dedicated leaderboard surface: join, optional public name, live rank.
struct LeaderboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var nameDraft: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusCard
                if appState.leaderboardOptIn {
                    nameCard
                    actionsRow
                } else {
                    joinCard
                }
                privacyNote
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            nameDraft = appState.leaderboardPublicNameDraft
            appState.refreshLeaderboardStanding()
            if appState.leaderboardOptIn {
                appState.syncLeaderboardIfNeeded(force: false)
            }
        }
        .onChange(of: appState.leaderboardPublicNameDraft) { _, new in
            // Keep draft in sync after successful server name update.
            if !nameFocused {
                nameDraft = new
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Leaderboard", systemImage: "trophy.fill")
                .font(.title2.weight(.semibold))
            Text("Ranked by words dictated. Opt in to appear on the public board.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 16) {
            LeaderboardAvatarView(
                animal: appState.leaderboardAnimal.isEmpty ? "Otter" : appState.leaderboardAnimal,
                avatarKey: appState.leaderboardAvatarKey.isEmpty
                    ? appState.leaderboardDisplayName
                    : appState.leaderboardAvatarKey,
                size: 72
            )

            VStack(alignment: .leading, spacing: 4) {
                if appState.leaderboardOptIn {
                    Text(rankHeadline)
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(rankColor)
                        .monospacedDigit()
                    Text(displayLine)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(statsLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("You’re not on the board")
                        .font(.title3.weight(.semibold))
                    Text(localPreviewLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Join to publish your word count and rank.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.45))
        )
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Public name (optional)")
                .font(.subheadline.weight(.semibold))
            TextField("e.g. Vas — leave blank for Anonymous Otter", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onChange(of: nameDraft) { _, v in
                    nameDraft = LeaderboardClient.sanitizeLocalPublicName(v)
                }
            Text("Compete with a name, or stay fully anonymous.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                // Seed name draft before opt-in so first sync includes it.
                LeaderboardClient.shared.publicName = nameDraft
                appState.leaderboardPublicNameDraft = nameDraft
                appState.setLeaderboardOptIn(true)
                if !nameDraft.isEmpty {
                    appState.setLeaderboardPublicName(nameDraft)
                } else {
                    appState.syncLeaderboardIfNeeded(force: true)
                }
            } label: {
                Label("Join leaderboard", systemImage: "trophy.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your public name")
                .font(.subheadline.weight(.semibold))
            TextField("Leave blank for anonymous animal", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { saveName() }
                .onChange(of: nameDraft) { _, v in
                    nameDraft = LeaderboardClient.sanitizeLocalPublicName(v)
                }
            if let err = appState.leaderboardNameError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Save name") { saveName() }
                    .buttonStyle(.borderedProminent)
                Button("Use anonymous") {
                    nameDraft = ""
                    appState.setLeaderboardPublicName("")
                }
                .buttonStyle(.bordered)
            }
            Text(appState.leaderboardIsCustomName
                 ? "Showing as “\(appState.leaderboardDisplayName)” on the public board."
                 : "Showing as anonymous animal. Add a name anytime to compete.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button {
                appState.syncLeaderboardIfNeeded(force: true)
                appState.refreshLeaderboardStanding()
            } label: {
                Label("Refresh rank", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                appState.openPublicLeaderboard()
            } label: {
                Label("Open website", systemImage: "safari")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Leave board", role: .destructive) {
                appState.setLeaderboardOptIn(false)
                nameDraft = ""
            }
            .buttonStyle(.bordered)
        }
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Privacy")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(
                "Only word count, dictation count, time saved, and streak leave your Mac. "
                + "No transcripts or install ID. A public name is optional and visible to everyone. "
                + "Separate from Settings → Share anonymous usage data."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func saveName() {
        appState.setLeaderboardPublicName(nameDraft)
        nameFocused = false
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

    private var displayLine: String {
        if !appState.leaderboardDisplayName.isEmpty {
            return appState.leaderboardDisplayName
        }
        return "Syncing name…"
    }

    private var statsLine: String {
        let local = appState.currentLeaderboardStats()
        let remote = appState.leaderboardRemoteStats
        let words = remote.words > 0 ? remote.words : local.words
        let dicts = remote.dictations > 0 ? remote.dictations : local.dictations
        let streak = remote.streakDays > 0 ? remote.streakDays : local.streakDays
        return "\(words.formatted()) words · \(dicts.formatted()) dictations · \(streak)d streak"
    }

    private var localPreviewLine: String {
        let s = appState.currentLeaderboardStats()
        if s.words == 0 {
            return "Dictate a bit first — your word count is empty so far."
        }
        return "You have about \(s.words.formatted()) words ready to publish."
    }
}

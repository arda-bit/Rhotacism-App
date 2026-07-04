import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning" }
        if h < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    serverStatusBanner
                    statsRow
                    currentLevelCard
                    if !store.sessions.isEmpty { recentSessionsList }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Rhotacism Therapy")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.checkServer() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.indigo)
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(.largeTitle.bold())
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var serverStatusBanner: some View {
        if !store.serverOnline {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Server offline")
                        .font(.subheadline.weight(.semibold))
                    Text("Start the backend to enable recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(
                value: "\(store.sessions.count)",
                label: "Sessions",
                icon: "mic.fill",
                iconColor: .indigo
            )
            StatCard(
                value: store.sessions.isEmpty ? "—" : String(format: "%.0f%%", store.averageScore * 100),
                label: "Avg score",
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .teal
            )
            StatCard(
                value: "Lv \(store.currentLevel.levelNumber)",
                label: store.currentLevel.displayName,
                icon: "star.fill",
                iconColor: .orange
            )
        }
    }

    private var currentLevelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Current level", systemImage: "graduationcap")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Level \(store.currentLevel.levelNumber) of 4")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
            }

            Text(store.currentLevel.displayName)
                .font(.title3.bold())

            let words = store.currentLevel.words
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(words.indices, id: \.self) { i in
                        Text(words[i].capitalized)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                i == store.currentWordIndex
                                    ? Color.indigo.opacity(0.15)
                                    : Color.primary.opacity(0.06),
                                in: Capsule()
                            )
                            .foregroundStyle(i == store.currentWordIndex ? .indigo : .secondary)
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 5)
                    Capsule()
                        .fill(Color.indigo)
                        .frame(
                            width: geo.size.width * CGFloat(store.currentWordIndex + 1) / CGFloat(max(words.count, 1)),
                            height: 5
                        )
                        .animation(.easeInOut, value: store.currentWordIndex)
                }
            }
            .frame(height: 5)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent sessions")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 1) {
                ForEach(store.sessions.prefix(5)) { session in
                    PracticeSessionRow(session: session)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Sub-components

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let iconColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ScoreRing: View {
    let score: Double   // 0.0 – 1.0
    let size: CGFloat

    private var color: Color {
        switch score {
        case 0.8...: return .green
        case 0.6...: return .yellow
        case 0.4...: return .orange
        default:     return .red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(score, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: score)
            VStack(spacing: 0) {
                Text(String(format: "%.0f", score * 100))
                    .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: size * 0.14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct PracticeSessionRow: View {
    let session: PracticeSession

    private var levelWord: WordLevel? { WordLevel(rawValue: session.level) }
    private var scoreColor: Color {
        switch session.averageScore {
        case 0.8...: return .green
        case 0.6...: return .yellow
        case 0.4...: return .orange
        default:     return .red
        }
    }

    private var dateStr: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: session.date)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "mic.circle.fill")
                .foregroundStyle(scoreColor)
                .font(.system(size: 22))

            VStack(alignment: .leading, spacing: 2) {
                Text(levelWord?.displayName ?? session.level.capitalized)
                    .font(.subheadline.weight(.medium))
                Text("\(session.wordResults.count) words · \(dateStr)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(String(format: "%.0f%%", session.averageScore * 100))
                .font(.subheadline.weight(.semibold))

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

#Preview {
    HomeView().environmentObject(AppStore())
}

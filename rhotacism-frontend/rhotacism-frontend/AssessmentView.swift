import SwiftUI

struct AssessmentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if !store.sessions.isEmpty {
                        sessionProgressSection
                    }
                    if store.sessions.count >= 2 {
                        trendSection
                    }
                    if !store.sessions.isEmpty {
                        sessionHistorySection
                    }
                    if store.sessions.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Assessment")
                        .font(.headline)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No sessions yet")
                .font(.headline)
            Text("Complete a therapy session to see your progress here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Sessions progress

    private var sessionProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall progress")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                ScoreRing(score: store.averageScore, size: 80)

                VStack(alignment: .leading, spacing: 8) {
                    MiniStatRow(label: "Sessions completed", value: "\(store.sessions.count)")
                    MiniStatRow(label: "Avg score", value: String(format: "%.0f%%", store.averageScore * 100))
                    MiniStatRow(label: "Current level", value: "Lv \(store.currentLevel.levelNumber) — \(store.currentLevel.displayName)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
    }

    // MARK: - Trend chart

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Score trend")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.sessions.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ScoreTrendChart(sessions: Array(store.sessions.reversed()))
                .frame(height: 120)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    // MARK: - Session history

    private var sessionHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session history")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 1) {
                ForEach(store.sessions) { session in
                    PracticeSessionRow(session: session)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

}

// MARK: - Sub-components

struct ImpairmentScoreRow: View {
    let impairment: ImpairmentType
    let score: Double

    private var color: Color {
        switch score {
        case 0.8...: return .green
        case 0.6...: return .yellow
        case 0.4...: return .orange
        default:     return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(impairment.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.0f%%", score * 100))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score), height: 6)
                        .animation(.easeOut(duration: 0.5), value: score)
                }
            }
            .frame(height: 6)
        }
    }
}

struct PhonemeRow: View {
    let result: PhonemeResult

    private var errorColor: Color {
        switch result.errorType {
        case "correct":        return .green
        case "partial":        return .orange
        case "unclear":        return .gray
        default:               return .red
        }
    }

    private var errorIcon: String {
        switch result.errorType {
        case "correct":        return "checkmark.circle.fill"
        case "partial":        return "exclamationmark.circle.fill"
        case "unclear":        return "questionmark.circle.fill"
        default:               return "xmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: errorIcon)
                .foregroundStyle(errorColor)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text("/\(result.phoneme)/ at \(String(format: "%.2f", result.startTime))s")
                    .font(.subheadline.weight(.medium))
                Text(ErrorType(rawValue: result.errorType)?.label ?? result.errorType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f%%", result.score * 100))
                    .font(.subheadline.weight(.semibold))
                Text("F3: \(Int(result.rawMetric)) Hz")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

struct MiniStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ScoreTrendChart: View {
    let sessions: [PracticeSession]

    private var scores: [Double] { sessions.map(\.averageScore) }
    private var minScore: Double { scores.min() ?? 0 }
    private var maxScore: Double { max(scores.max() ?? 1, minScore + 0.1) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                gridLines(w: geo.size.width, h: geo.size.height, pad: 10)
                if sessions.count > 1 {
                    linePath(w: geo.size.width, h: geo.size.height, pad: 10)
                    dotLayer(w: geo.size.width, h: geo.size.height, pad: 10)
                    dateLabels(w: geo.size.width, h: geo.size.height, pad: 10)
                }
            }
        }
    }

    private func points(w: CGFloat, h: CGFloat, pad: CGFloat) -> [CGPoint] {
        scores.enumerated().map { i, s in
            let x = pad + (w - pad * 2) * CGFloat(i) / CGFloat(max(scores.count - 1, 1))
            let y = h - pad - CGFloat((s - minScore) / (maxScore - minScore)) * (h - pad * 2 - 14)
            return CGPoint(x: x, y: y)
        }
    }

    private func gridLines(w: CGFloat, h: CGFloat, pad: CGFloat) -> some View {
        ForEach([0.25, 0.5, 0.75] as [Double], id: \.self) { pct in
            Path { p in
                let y = h - pad - CGFloat(pct) * (h - pad * 2)
                p.move(to: CGPoint(x: pad, y: y))
                p.addLine(to: CGPoint(x: w - pad, y: y))
            }
            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func linePath(w: CGFloat, h: CGFloat, pad: CGFloat) -> some View {
        let pts = points(w: w, h: h, pad: pad)
        return Path { p in
            p.move(to: pts[0])
            pts.dropFirst().forEach { p.addLine(to: $0) }
        }
        .stroke(Color.indigo, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    private func dotLayer(w: CGFloat, h: CGFloat, pad: CGFloat) -> some View {
        let pts = points(w: w, h: h, pad: pad)
        return ForEach(pts.indices, id: \.self) { i in
            Circle()
                .fill(scoreColor(scores[i]))
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                .position(pts[i])
        }
    }

    private func dateLabels(w: CGFloat, h: CGFloat, pad: CGFloat) -> some View {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return Group {
            Text(fmt.string(from: sessions.first!.date))
                .position(x: pad + 16, y: h - 8)
            Text(fmt.string(from: sessions.last!.date))
                .position(x: w - pad - 16, y: h - 8)
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }

    private func scoreColor(_ s: Double) -> Color {
        switch s {
        case 0.8...: return .green
        case 0.6...: return .yellow
        case 0.4...: return .orange
        default:     return .red
        }
    }
}

#Preview {
    AssessmentView().environmentObject(AppStore())
}

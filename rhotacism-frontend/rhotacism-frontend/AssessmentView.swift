import SwiftUI

struct AssessmentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var recorder = AudioRecorder()

    @State private var report: SpeechReport? = nil
    @State private var error: String? = nil
    @State private var isRecording = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    freeSpeechRecorder
                    if let r = report {
                        reportSection(r)
                    } else if report == nil && !store.sessions.isEmpty {
                        sessionProgressSection
                    }
                    if store.sessions.count >= 2 {
                        trendSection
                    }
                    if !store.sessions.isEmpty {
                        sessionHistorySection
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
                ToolbarItem(placement: .topBarTrailing) {
                    if report != nil {
                        Button("Clear") { withAnimation { report = nil } }
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { await recorder.requestPermission() }
    }

    // MARK: - Free speech recorder

    private var freeSpeechRecorder: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free speech analysis")
                        .font(.headline)
                    Text("Record any sentence to detect rhotacism, sigmatism, and lambdacism.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            WaveformBars(level: recorder.level, isRecording: recorder.state == .recording)
                .frame(height: 44)

            if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                handleFreeSpeechTap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: recorder.state == .recording ? "stop.fill" : "mic.fill")
                    Text(buttonLabel)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(recorder.state == .recording ? Color.red : Color.indigo, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(recorder.state == .processing)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .padding(.top, 8)
    }

    private var buttonLabel: String {
        switch recorder.state {
        case .idle:       return "Record free speech"
        case .recording:  return "Stop and analyze"
        case .processing: return "Analyzing…"
        }
    }

    // MARK: - Report

    private func reportSection(_ r: SpeechReport) -> some View {
        VStack(spacing: 20) {
            primaryConcernBanner(r)
            impairmentScores(r)
            if !r.phonemeResults.isEmpty { phonemeList(r) }
            if !r.feedback.isEmpty { feedbackSection(r) }
        }
    }

    private func primaryConcernBanner(_ r: SpeechReport) -> some View {
        let imp = r.primaryConcern.flatMap { ImpairmentType(rawValue: $0) }
        let (color, icon): (Color, String) = imp == nil
            ? (.green, "checkmark.circle.fill")
            : (.orange, "exclamationmark.triangle.fill")

        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text("Diagnosis")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(imp?.displayName ?? "No impairment detected")
                    .font(.title3.bold())
                if let transcript = r.transcript.nilIfEmpty {
                    Text("\"\(transcript)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(20)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.2), lineWidth: 0.5))
    }

    private func impairmentScores(_ r: SpeechReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Impairment scores")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if r.impairmentScores.isEmpty {
                Text("No target phonemes detected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(ImpairmentType.allCases, id: \.self) { imp in
                    if let score = r.impairmentScores[imp.rawValue] {
                        ImpairmentScoreRow(impairment: imp, score: score)
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func phonemeList(_ r: SpeechReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Phoneme-by-phoneme")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 1) {
                ForEach(r.phonemeResults) { p in
                    PhonemeRow(result: p)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func feedbackSection(_ r: SpeechReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feedback")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(r.feedback, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(Color.yellow.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
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

    // MARK: - Actions

    private func handleFreeSpeechTap() {
        error = nil
        switch recorder.state {
        case .idle:
            recorder.start()
        case .recording:
            guard let url = recorder.stop() else { recorder.state = .idle; return }
            Task { await analyzeFreeSpeech(url: url) }
        case .processing:
            break
        }
    }

    private func analyzeFreeSpeech(url: URL) async {
        do {
            let r = try await store.submitFreeSpeech(audioURL: url)
            withAnimation(.spring(duration: 0.4)) { report = r }
        } catch {
            withAnimation { self.error = error.localizedDescription }
        }
        recorder.state = .idle
        try? FileManager.default.removeItem(at: url)
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

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview {
    AssessmentView().environmentObject(AppStore())
}

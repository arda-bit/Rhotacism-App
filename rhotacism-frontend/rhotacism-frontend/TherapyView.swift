import SwiftUI

struct TherapyView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var recorder = AudioRecorder()

    @State private var result: AnalyzeWordResponse? = nil
    @State private var error: String? = nil
    @State private var showLevelUp = false
    @State private var showMouthDiagram = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                levelBadge
                progressBar
                Spacer()
                wordPrompt
                Spacer()
                waveformView
                Spacer()
                resultCard
                recordButton
                    .padding(.bottom, 48)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Therapy")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.currentSessionAttempts.isEmpty {
                        Button("Finish") { store.finishSession() }
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .overlay {
                if showLevelUp { levelUpOverlay }
            }
        }
        .task { await recorder.requestPermission() }
        .sheet(isPresented: $showMouthDiagram) {
            MouthDiagramSheet(
                errorType: result.flatMap { ErrorType(rawValue: $0.errorType ?? "") },
                score: result?.score ?? 0
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Microphone access denied", isPresented: $recorder.permissionDenied) {
            Button("OK") {}
        } message: {
            Text("Enable microphone access in Settings to use Therapy mode.")
        }
    }

    // MARK: - Level badge

    private var levelBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.caption2.weight(.bold))
            Text("Level \(store.currentLevel.levelNumber) — \(store.currentLevel.displayName)")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.indigo)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.indigo.opacity(0.1), in: Capsule())
        .padding(.top, 12)
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let total = store.wordsInLevel.count
        let done  = min(store.currentWordIndex, total)

        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 4)
                    Capsule()
                        .fill(Color.indigo)
                        .frame(width: geo.size.width * CGFloat(done) / CGFloat(max(total, 1)), height: 4)
                        .animation(.easeInOut(duration: 0.3), value: done)
                }
            }
            .frame(height: 4)

            HStack {
                Text("Word \(min(store.currentWordIndex + 1, total)) of \(total)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(store.wordsInLevel.indices, id: \.self) { i in
                        Circle()
                            .fill(dotColor(index: i))
                            .frame(width: i == store.currentWordIndex ? 7 : 5,
                                   height: i == store.currentWordIndex ? 7 : 5)
                            .animation(.spring(duration: 0.25), value: store.currentWordIndex)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private func dotColor(index: Int) -> Color {
        if let attempts = attemptedIndices, attempts.contains(index) { return .green }
        if index == store.currentWordIndex { return .indigo }
        return Color.primary.opacity(0.2)
    }

    private var attemptedIndices: Set<Int>? {
        let attempted = store.currentSessionAttempts.count
        guard attempted > 0 else { return nil }
        return Set(0..<attempted)
    }

    // MARK: - Word prompt

    private var wordPrompt: some View {
        VStack(spacing: 14) {
            Text("Say this word:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(store.currentWord)
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.35), value: store.currentWord)

            Text("Focus on the /r/ sound")
                .font(.caption.weight(.medium))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.indigo.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Waveform

    private var waveformView: some View {
        VStack(spacing: 10) {
            WaveformBars(level: recorder.level, isRecording: recorder.state == .recording)
                .frame(height: 60)

            recorderStatusLabel
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var recorderStatusLabel: some View {
        switch recorder.state {
        case .recording:
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text("Recording…")
            }
        case .processing:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.8)
                Text(store.serverOnline ? "Analyzing…" : "Server offline")
            }
        case .idle:
            Text(store.serverOnline ? "Tap the mic to start" : "Server offline — check connection")
        }
    }

    // MARK: - Result card

    @ViewBuilder
    private var resultCard: some View {
        if let r = result {
            VStack(spacing: 0) {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ScoreRing(score: r.score, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.verified ? errorLabel(r.errorType) : "Wrong word")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(scoreColor(r.score))
                            Text(r.message)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }

                    if !r.cue.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(r.cue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let f3 = r.f3Hz {
                        Text("F3: \(Int(f3)) Hz")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        showMouthDiagram = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mouth.fill")
                                .font(.caption.weight(.semibold))
                            Text("See mouth position")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.indigo)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Record button

    private var recordButton: some View {
        Button {
            handleTap()
        } label: {
            ZStack {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 88, height: 88)
                    .scaleEffect(recorder.state == .recording ? 1.06 : 1.0)
                    .animation(
                        recorder.state == .recording
                            ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                            : .default,
                        value: recorder.state == .recording
                    )

                Image(systemName: buttonIcon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .disabled(recorder.state == .processing)
        .padding(.top, 20)
    }

    private var buttonColor: Color {
        switch recorder.state {
        case .idle:       return .indigo
        case .recording:  return .red
        case .processing: return Color(.systemGray3)
        }
    }

    private var buttonIcon: String {
        switch recorder.state {
        case .idle:       return "mic.fill"
        case .recording:  return "stop.fill"
        case .processing: return "ellipsis"
        }
    }

    // MARK: - Actions

    private func handleTap() {
        withAnimation(.spring(duration: 0.3)) { result = nil; error = nil }
        switch recorder.state {
        case .idle:
            recorder.start()
        case .recording:
            guard let url = recorder.stop() else { recorder.state = .idle; return }
            Task { await submit(audioURL: url) }
        case .processing:
            break
        }
    }

    private func submit(audioURL: URL) async {
        do {
            let r = try await store.submitWord(audioURL: audioURL)
            withAnimation(.spring(duration: 0.4)) { result = r }
            if r.levelUp { triggerLevelUp() }
        } catch {
            withAnimation { self.error = error.localizedDescription }
        }
        recorder.state = .idle
        try? FileManager.default.removeItem(at: audioURL)
    }

    private func triggerLevelUp() {
        showLevelUp = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showLevelUp = false }
        }
    }

    // MARK: - Level-up overlay

    private var levelUpOverlay: some View {
        VStack(spacing: 16) {
            Text("🎉")
                .font(.system(size: 64))
            Text("Level up!")
                .font(.title.bold())
            Text("Moving to \(store.currentLevel.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(40)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Helpers

    private func errorLabel(_ raw: String?) -> String {
        ErrorType(rawValue: raw ?? "")?.label ?? "Result"
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

// MARK: - Waveform bars

struct WaveformBars: View {
    let level: Float
    let isRecording: Bool
    private let count = 28

    private func barHeight(index: Int) -> CGFloat {
        guard isRecording else { return 4 }
        let phase = Double(index) + Date().timeIntervalSince1970 * 8
        let wave = abs(sin(phase)) * Double(level) * 55
        return max(4, CGFloat(wave) + 4)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(isRecording ? Color.indigo : Color.primary.opacity(0.15))
                    .frame(width: 3, height: barHeight(index: i))
                    .animation(.easeInOut(duration: 0.08), value: level)
            }
        }
    }
}

#Preview {
    TherapyView().environmentObject(AppStore())
}

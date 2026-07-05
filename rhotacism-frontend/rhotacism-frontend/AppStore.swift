import SwiftUI

@MainActor
final class AppStore: ObservableObject {

    @Published var currentLevel: WordLevel = .initial
    @Published var currentWordIndex: Int = 0
    @Published var sessionScores: [Double] = []
    @Published var sessions: [PracticeSession] = []
    @Published var currentSessionAttempts: [WordAttempt] = []
    @Published var lastResult: AnalyzeWordResponse? = nil
    @Published var lastReport: SpeechReport? = nil
    @Published var serverOnline: Bool = false

    var currentWord: String {
        let words = currentLevel.words
        guard currentWordIndex < words.count else { return words[0] }
        return words[currentWordIndex].capitalized
    }

    var wordsInLevel: [String] { currentLevel.words.map(\.capitalized) }

    var averageScore: Double {
        let all = sessions.flatMap { $0.wordResults.map(\.score) }
        guard !all.isEmpty else { return 0 }
        return all.reduce(0, +) / Double(all.count)
    }

    init() {
        loadSessions()
        Task { await checkServer() }
    }

    // MARK: - API

    func submitWord(audioURL: URL) async throws -> AnalyzeWordResponse {
        let result = try await NetworkService.shared.analyzeWord(
            audioURL: audioURL,
            targetWord: currentLevel.words[currentWordIndex],
            sessionScores: sessionScores
        )
        lastResult = result

        if result.verified {
            sessionScores.append(result.score)
            currentSessionAttempts.append(WordAttempt(
                id: UUID(),
                word: currentWord,
                score: result.score,
                errorType: result.errorType ?? "unclear",
                message: result.message
            ))
            if result.levelUp, let next = currentLevel.next {
                advanceLevel(to: next)
            } else {
                advanceWord()
            }
        }
        return result
    }

    func submitFreeSpeech(audioURL: URL) async throws -> SpeechReport {
        let report = try await NetworkService.shared.analyzeSpeech(audioURL: audioURL)
        lastReport = report
        return report
    }

    func checkServer() async {
        serverOnline = await NetworkService.shared.checkHealth()
    }

    // MARK: - Navigation

    func advanceWord() {
        currentWordIndex = (currentWordIndex + 1) % currentLevel.words.count
        sessionScores = []
    }

    func advanceLevel(to level: WordLevel) {
        currentLevel = level
        currentWordIndex = 0
        sessionScores = []
    }

    func selectLevel(_ level: WordLevel) {
        currentLevel = level
        currentWordIndex = 0
        sessionScores = []
        currentSessionAttempts = []
    }

    func finishSession() {
        guard !currentSessionAttempts.isEmpty else { return }
        let session = PracticeSession(
            id: UUID(),
            date: Date(),
            level: currentLevel.rawValue,
            wordResults: currentSessionAttempts
        )
        sessions.insert(session, at: 0)
        currentSessionAttempts = []
        sessionScores = []
        saveSessions()
    }

    // MARK: - Persistence

    private let sessionsKey = "practiceSessions_v2"

    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let saved = try? JSONDecoder().decode([PracticeSession].self, from: data)
        else { return }
        sessions = saved
    }
}

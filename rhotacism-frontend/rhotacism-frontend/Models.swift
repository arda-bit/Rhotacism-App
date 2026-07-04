import Foundation

// MARK: - API Response Models

struct AnalyzeWordResponse: Codable {
    let verified: Bool
    let transcription: String
    let message: String
    let cue: String
    let score: Double
    let levelUp: Bool
    let f3Hz: Double?
    let errorType: String?

    enum CodingKeys: String, CodingKey {
        case verified, transcription, message, cue, score
        case levelUp    = "level_up"
        case f3Hz       = "f3_hz"
        case errorType  = "error_type"
    }
}

struct SpeechReport: Codable {
    let transcript: String
    let duration: Double
    let primaryConcern: String?
    let impairmentScores: [String: Double]
    let feedback: [String]
    let phonemeResults: [PhonemeResult]

    enum CodingKeys: String, CodingKey {
        case transcript, duration, feedback
        case primaryConcern    = "primary_concern"
        case impairmentScores  = "impairment_scores"
        case phonemeResults    = "phoneme_results"
    }
}

struct PhonemeResult: Codable, Identifiable {
    var id: String { "\(phoneme)-\(startTime)" }
    let phoneme: String
    let startTime: Double
    let endTime: Double
    let impairmentType: String
    let errorType: String
    let score: Double
    let confidence: Double
    let rawMetric: Double

    enum CodingKeys: String, CodingKey {
        case phoneme, score, confidence
        case startTime     = "start_time"
        case endTime       = "end_time"
        case impairmentType = "impairment_type"
        case errorType     = "error_type"
        case rawMetric     = "raw_metric"
    }
}

// MARK: - Local Domain Models

enum ErrorType: String {
    case correct        = "correct"
    case wSubstitution  = "w_substitution"
    case lSubstitution  = "l_substitution"
    case dentalLisp     = "dental_lisp"
    case partial        = "partial"
    case unclear        = "unclear"

    var label: String {
        switch self {
        case .correct:       return "Correct"
        case .wSubstitution: return "/w/ substitution"
        case .lSubstitution: return "/l/ substitution"
        case .dentalLisp:    return "Dental lisp"
        case .partial:       return "Partial"
        case .unclear:       return "Unclear"
        }
    }

    var color: String {
        switch self {
        case .correct:                    return "green"
        case .wSubstitution, .lSubstitution, .dentalLisp: return "red"
        case .partial:                    return "orange"
        case .unclear:                    return "gray"
        }
    }
}

enum ImpairmentType: String, CaseIterable {
    case rhotacism  = "rhotacism"
    case sigmatism  = "sigmatism"
    case lambdacism = "lambdacism"

    var displayName: String {
        switch self {
        case .rhotacism:  return "Rhotacism (/r/)"
        case .sigmatism:  return "Sigmatism (/s/, /z/)"
        case .lambdacism: return "Lambdacism (/l/)"
        }
    }

    var phoneme: String {
        switch self {
        case .rhotacism:  return "/r/"
        case .sigmatism:  return "/s/, /z/"
        case .lambdacism: return "/l/"
        }
    }
}

// MARK: - Word Progression

enum WordLevel: String, CaseIterable {
    case initial = "initial"
    case medial  = "medial"
    case final_  = "final"
    case cluster = "cluster"

    var displayName: String {
        switch self {
        case .initial: return "Initial /r/"
        case .medial:  return "Medial /r/"
        case .final_:  return "Final /r/"
        case .cluster: return "Consonant clusters"
        }
    }

    var levelNumber: Int {
        switch self {
        case .initial: return 1
        case .medial:  return 2
        case .final_:  return 3
        case .cluster: return 4
        }
    }

    var words: [String] {
        switch self {
        case .initial: return ["red", "run", "rabbit", "rain", "robot", "ring", "river", "road"]
        case .medial:  return ["very", "carry", "forest", "orange", "around", "parrot"]
        case .final_:  return ["car", "far", "floor", "door", "four", "more"]
        case .cluster: return ["green", "brown", "three", "bring", "friend", "dress"]
        }
    }

    var next: WordLevel? {
        switch self {
        case .initial: return .medial
        case .medial:  return .final_
        case .final_:  return .cluster
        case .cluster: return nil
        }
    }
}

// MARK: - Session History

struct PracticeSession: Identifiable, Codable {
    let id: UUID
    let date: Date
    let level: String
    let wordResults: [WordAttempt]

    var averageScore: Double {
        guard !wordResults.isEmpty else { return 0 }
        return wordResults.map(\.score).reduce(0, +) / Double(wordResults.count)
    }
}

struct WordAttempt: Identifiable, Codable {
    let id: UUID
    let word: String
    let score: Double
    let errorType: String
    let message: String
}

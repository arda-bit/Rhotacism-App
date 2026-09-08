import Foundation

enum NetworkError: LocalizedError {
    case invalidURL, serverError(Int), decodingError, noAudio, audioReadError

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid server URL."
        case .serverError(let c): return "Server returned error \(c)."
        case .decodingError:    return "Could not parse server response."
        case .noAudio:          return "No audio file to upload."
        case .audioReadError:   return "Could not read the recorded audio."
        }
    }
}

final class NetworkService {
    static let shared = NetworkService()

    // Production: replace with your Railway URL after deploying.
    // Format: "https://your-app-name.up.railway.app"
    // For local Simulator testing switch back to "http://localhost:8000".
    var baseURL = "https://your-app-name.up.railway.app"

    private init() {}

    // MARK: - /analyze-word

    func analyzeWord(
        audioURL: URL,
        targetWord: String,
        sessionScores: [Double]
    ) async throws -> AnalyzeWordResponse {
        let url = try endpoint("/analyze-word")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try readAudio(at: audioURL)
        let scoresJSON = (try? JSONEncoder().encode(sessionScores)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        var body = Data()
        body.appendField("target_word", value: targetWord, boundary: boundary)
        body.appendField("session_scores", value: scoresJSON, boundary: boundary)
        body.appendFile("audio", data: audioData, filename: "recording.m4a", mimeType: "audio/m4a", boundary: boundary)
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        return try await perform(request)
    }

    // MARK: - /analyze (free speech)

    func analyzeSpeech(audioURL: URL) async throws -> SpeechReport {
        let url = try endpoint("/analyze")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try readAudio(at: audioURL)
        var body = Data()
        body.appendFile("audio", data: audioData, filename: "recording.m4a", mimeType: "audio/m4a", boundary: boundary)
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        return try await perform(request)
    }

    // MARK: - /health

    func checkHealth() async -> Bool {
        guard let url = try? endpoint("/health") else { return false }
        let request = URLRequest(url: url, timeoutInterval: 5)
        let (_, response) = (try? await URLSession.shared.data(for: request)) ?? (Data(), nil)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Helpers

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else { throw NetworkError.invalidURL }
        return url
    }

    private func readAudio(at url: URL) throws -> Data {
        guard let data = try? Data(contentsOf: url) else { throw NetworkError.audioReadError }
        return data
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NetworkError.serverError(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError
        }
    }
}

// MARK: - Multipart helpers

private extension Data {
    mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }

    mutating func appendField(_ name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendFile(_ name: String, data: Data, filename: String, mimeType: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}

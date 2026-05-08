import Foundation

public class GeminiTextCleanup {

    public init() {}

    public enum CleanupError: Error, LocalizedError {
        case apiKeyNotFound
        case requestFailed(statusCode: Int, message: String)
        case noTextInResponse
        case blocked(reason: String)

        public var errorDescription: String? {
            switch self {
            case .apiKeyNotFound:
                return "Gemini API key not configured."
            case .requestFailed(let statusCode, let message):
                return "API request failed (\(statusCode)): \(message)"
            case .noTextInResponse:
                return "No text in API response"
            case .blocked(let reason):
                return "Request blocked: \(reason)"
            }
        }
    }

    private struct GenerateContentResponse: Codable {
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?

        struct Candidate: Codable {
            let content: Content?
            let finishReason: String?
        }

        struct Content: Codable {
            let parts: [Part]?
        }

        struct Part: Codable {
            let text: String?
        }

        struct PromptFeedback: Codable {
            let blockReason: String?
        }
    }

    public func cleanupText(_ rawText: String, prompt: String) async throws -> String {
        guard GeminiConfig.isConfigured else {
            throw CleanupError.apiKeyNotFound
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: [
            "system_instruction": ["parts": [["text": prompt]]],
            "contents": [["parts": [["text": rawText]]]],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 1024,
                "responseMimeType": "text/plain"
            ]
        ] as [String: Any]) else {
            throw CleanupError.requestFailed(statusCode: 0, message: "Failed to serialize request")
        }

        let selected = GeminiConfig.selectedModel
        do {
            let result = try await sendRequest(model: selected, body: jsonData)
            GeminiCallLog.shared.append(success: true, detail: "OK - \(selected)")
            return result
        } catch {
            GeminiCallLog.shared.append(success: false, detail: logDetail(error))
            throw error
        }
    }

    private func logDetail(_ error: Error) -> String {
        if let e = error as? CleanupError {
            switch e {
            case .apiKeyNotFound: return "API key missing"
            case .requestFailed(let code, _):
                switch code {
                case 429: return "Rate limited (429)"
                case 401: return "Invalid API key (401)"
                case 400: return "Bad request (400)"
                case 500, 503: return "Server error (\(code))"
                default: return "HTTP \(code)"
                }
            case .noTextInResponse: return "Empty response"
            case .blocked(let reason): return "Blocked: \(reason)"
            }
        }
        if (error as? URLError)?.code == .timedOut { return "Timeout" }
        return error.localizedDescription
    }

    private func sendRequest(model: String, body: Data) async throws -> String {
        print("🤖 Gemini cleanup using model: \(model)")
        let apiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: apiURL, timeoutInterval: TimeInterval(TranscriptionPreferences.cleanupTimeout))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GeminiConfig.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CleanupError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

        if let blockReason = decoded.promptFeedback?.blockReason {
            throw CleanupError.blocked(reason: blockReason)
        }

        guard let text = decoded.candidates?.first?.content?.parts?.first?.text else {
            throw CleanupError.noTextInResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

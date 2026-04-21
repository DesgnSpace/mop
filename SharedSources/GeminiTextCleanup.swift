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

        let fullPrompt = "\(prompt)\n\(rawText)"

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": fullPrompt]]]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 1024
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw CleanupError.requestFailed(statusCode: 0, message: "Failed to serialize request")
        }

        let model = GeminiConfig.selectedModel
        print("🤖 Gemini cleanup using model: \(model)")
        let apiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: apiURL, timeoutInterval: 8.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GeminiConfig.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = jsonData

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

import Foundation

public class OpenAITextCleanup: TextCleanupDriver {
    public let driverID: CleanupDriver = .openai
    private let apiKey: String
    private let model: String

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    public enum CleanupError: Error, LocalizedError {
        case apiKeyNotFound
        case requestFailed(statusCode: Int, message: String)
        case noTextInResponse

        public var errorDescription: String? {
            switch self {
            case .apiKeyNotFound: return "OpenAI API key not configured."
            case .requestFailed(let code, let msg): return "Request failed (\(code)): \(msg)"
            case .noTextInResponse: return "No text in response."
            }
        }
    }

    public func cleanup(_ text: String, prompt: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanupError.apiKeyNotFound
        }
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw CleanupError.requestFailed(statusCode: 0, message: "Invalid URL")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(TranscriptionPreferences.cleanupTimeout))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CleanupError.requestFailed(statusCode: http.statusCode, message: msg)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw CleanupError.noTextInResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: Message
        }
        struct Message: Decodable {
            let content: String
        }
    }
}

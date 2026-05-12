import Foundation

public class AnthropicTextCleanup: TextCleanupDriver {
    public let driverID: CleanupDriver = .anthropic
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
            case .apiKeyNotFound: return "Anthropic API key not configured."
            case .requestFailed(let code, let msg): return "Request failed (\(code)): \(msg)"
            case .noTextInResponse: return "No text in response."
            }
        }
    }

    public func cleanup(_ text: String, prompt: String) async throws -> CleanupResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanupError.apiKeyNotFound
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw CleanupError.requestFailed(statusCode: 0, message: "Invalid URL")
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "system": prompt,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(TranscriptionPreferences.cleanupTimeout))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CleanupError.requestFailed(statusCode: http.statusCode, message: msg)
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let content = decoded.content.first?.text else {
            throw CleanupError.noTextInResponse
        }
        return CleanupResult(
            text: content.trimmingCharacters(in: .whitespacesAndNewlines),
            model: decoded.model
        )
    }

    private struct MessagesResponse: Decodable {
        let model: String?
        let content: [ContentBlock]
        struct ContentBlock: Decodable {
            let text: String
        }
    }
}

import Foundation

public class LocalLLMTextCleanup: TextCleanupDriver {
    public let driverID: CleanupDriver
    private let baseURL: String
    private let model: String

    public init(driverID: CleanupDriver = .ollama, baseURL: String, model: String) {
        self.driverID = driverID
        self.baseURL = baseURL
        self.model = model
    }

    public func cleanup(_ text: String, prompt: String) async throws -> CleanupResult {
        let result = try await cleanupText(text, prompt: prompt)
        return CleanupResult(text: result, model: model)
    }

    public enum CleanupError: Error, LocalizedError {
        case invalidEndpoint
        case modelNotSet
        case requestFailed(statusCode: Int, message: String)
        case noTextInResponse

        public var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "Invalid endpoint URL."
            case .modelNotSet: return "No model selected."
            case .requestFailed(let code, let msg): return "Request failed (\(code)): \(msg)"
            case .noTextInResponse: return "No text in response."
            }
        }
    }

    public func cleanupText(_ rawText: String, prompt: String) async throws -> String {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanupError.modelNotSet
        }
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw CleanupError.invalidEndpoint
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": rawText]
            ],
            "temperature": 0
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(TranscriptionPreferences.cleanupTimeout))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CleanupError.requestFailed(statusCode: http.statusCode, message: msg)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content else {
            throw CleanupError.noTextInResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

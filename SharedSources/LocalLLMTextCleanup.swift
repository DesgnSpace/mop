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
        do {
            let result = try await cleanupText(text, prompt: prompt)
            CleanupCallLog.shared.append(success: true, detail: "OK - \(model)")
            return CleanupResult(text: result, model: model)
        } catch {
            CleanupCallLog.shared.append(success: false, detail: error.localizedDescription)
            throw error
        }
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

        if driverID == .ollama {
            return try await cleanupViaOllamaGenerate(rawText, prompt: prompt)
        } else {
            return try await cleanupViaChatCompletions(rawText, prompt: prompt)
        }
    }

    private func cleanupViaOllamaGenerate(_ rawText: String, prompt: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw CleanupError.invalidEndpoint
        }
        let body: [String: Any] = [
            "model": model,
            "system": prompt,
            "prompt": rawText,
            "stream": false,
            "think": false
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
        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        guard !decoded.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanupError.noTextInResponse
        }
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanupViaChatCompletions(_ rawText: String, prompt: String) async throws -> String {
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

    private struct OllamaGenerateResponse: Decodable {
        let response: String
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

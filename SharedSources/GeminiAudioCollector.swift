import Foundation

public class GeminiAudioCollector {
    private let apiKey: String
    private var isStreaming = false

    public enum GeminiAudioCollectorError: Error, LocalizedError {
        case notConfigured
        case streamingFailed(String)
        case noAudioData

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Gemini API key not configured"
            case .streamingFailed(let message):
                return "Streaming failed: \(message)"
            case .noAudioData:
                return "No audio data received"
            }
        }
    }

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func collectAudioChunks(from text: String, completion: ((Result<Void, Error>) -> Void)? = nil) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let audioData = try await generateAudio(text: text)
                    continuation.yield(audioData)
                    continuation.finish()
                    completion?(.success(()))
                } catch {
                    continuation.finish(throwing: error)
                    completion?(.failure(error))
                }
            }
        }
    }

    private func generateAudio(text: String) async throws -> Data {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:streamGenerateContent?alt=sse&key=\(apiKey)")!

        var request = URLRequest(url: url, timeoutInterval: 30.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": text]]]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 1024
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAudioCollectorError.streamingFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiAudioCollectorError.streamingFailed("Status \(httpResponse.statusCode): \(message)")
        }

        return data
    }
}
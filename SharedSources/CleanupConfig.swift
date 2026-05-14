import Foundation

public enum CleanupDriver: String, CaseIterable, Codable {
    case gemini
    case openai
    case anthropic
    case ollama
    case lmStudio

    public var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }
}

public enum CleanupConfig {
    public static var selectedDriver: CleanupDriver {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "cleanupDriver"),
                  let driver = CleanupDriver(rawValue: raw) else { return .gemini }
            return driver
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "cleanupDriver") }
    }

    public static var ollamaEndpoint: String {
        get { UserDefaults.standard.string(forKey: "ollamaEndpoint") ?? "http://localhost:11434" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaEndpoint") }
    }

    public static var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }

    public static var lmStudioEndpoint: String {
        get { UserDefaults.standard.string(forKey: "lmStudioEndpoint") ?? "http://localhost:1234" }
        set { UserDefaults.standard.set(newValue, forKey: "lmStudioEndpoint") }
    }

    public static var lmStudioModel: String {
        get { UserDefaults.standard.string(forKey: "lmStudioModel") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lmStudioModel") }
    }

    public static var openAIAPIKey: String {
        get { UserDefaults.standard.string(forKey: "openAIAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openAIAPIKey") }
    }

    public static var openAIModel: String {
        get { UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-4o-mini" }
        set { UserDefaults.standard.set(newValue, forKey: "openAIModel") }
    }

    public static var anthropicAPIKey: String {
        get { UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "anthropicAPIKey") }
    }

    public static var anthropicModel: String {
        get { UserDefaults.standard.string(forKey: "anthropicModel") ?? "claude-haiku-4-5-20251001" }
        set { UserDefaults.standard.set(newValue, forKey: "anthropicModel") }
    }

    private static let cacheTTL: TimeInterval = 3 * 24 * 3600

    // MARK: - OpenAI model fetching

    public static let openAIFallbackModels = ["gpt-4o-mini", "gpt-4o", "gpt-4-turbo"]

    public static var openAICachedModels: [String]? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "openAICachedModels"),
                  let models = try? JSONDecoder().decode([String].self, from: data),
                  !models.isEmpty else { return nil }
            return models
        }
        set {
            if let val = newValue, let data = try? JSONEncoder().encode(val) {
                UserDefaults.standard.set(data, forKey: "openAICachedModels")
                UserDefaults.standard.set(Date(), forKey: "openAICachedModelsDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "openAICachedModels")
                UserDefaults.standard.removeObject(forKey: "openAICachedModelsDate")
            }
        }
    }

    public static var openAIModelsCacheStale: Bool {
        guard let date = UserDefaults.standard.object(forKey: "openAICachedModelsDate") as? Date else { return true }
        return Date().timeIntervalSince(date) > cacheTTL
    }

    public static var effectiveOpenAIModels: [String] {
        openAICachedModels ?? openAIFallbackModels
    }

    public static func fetchOpenAIModels(apiKey: String) async -> [String]? {
        guard !apiKey.isEmpty else { return nil }

        if !openAIModelsCacheStale, let cached = openAICachedModels {
            return cached
        }

        guard let url = URL(string: "https://api.openai.com/v1/models") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        struct Response: Decodable {
            let data: [ModelEntry]
        }
        struct ModelEntry: Decodable {
            let id: String
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let models = decoded.data.map { $0.id }.sorted()
        guard !models.isEmpty else { return nil }
        openAICachedModels = models
        return models
    }

    // MARK: - Ollama/LM Studio model fetching

    public static func fetchModels(from endpoint: String) async -> [String]? {
        guard let url = URL(string: "\(endpoint)/v1/models") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return json.data.map { $0.id }.sorted()
        } catch {
            return nil
        }
    }

    private struct ModelsResponse: Decodable {
        let data: [ModelEntry]
        struct ModelEntry: Decodable {
            let id: String
        }
    }
}

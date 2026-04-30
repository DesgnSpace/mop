import Foundation

public enum GeminiConfig {
    private static let apiKeyKey = "GEMINI_API_KEY"
    private static let selectedModelKey = "GEMINI_SELECTED_MODEL"
    private static let cachedModelsKey = "GEMINI_CACHED_MODELS"
    private static let cachedModelsDateKey = "GEMINI_CACHED_MODELS_DATE"
    private static let cacheTTL: TimeInterval = 3 * 24 * 3600

    public struct ModelInfo: Codable, Identifiable, Hashable {
        public let id: String
        public let displayName: String
    }

    public static let defaultCleanupModel = "gemini-2.5-flash-lite"

    public static let fallbackModels: [ModelInfo] = [
        ModelInfo(id: "gemini-3.1-flash-lite-preview", displayName: "Gemini 3.1 Flash Lite (preview)"),
        ModelInfo(id: "gemini-3-flash-preview", displayName: "Gemini 3 Flash (preview)"),
        ModelInfo(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash Lite (fastest)"),
        ModelInfo(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash (balanced)"),
        ModelInfo(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro (highest quality)"),
        ModelInfo(id: "gemma-4-31b-it", displayName: "Gemma 4 31B"),
        ModelInfo(id: "gemma-4-26b-a4b-it", displayName: "Gemma 4 26B"),
    ]

    public static var availableModels: [String] { effectiveModels.map(\.id) }

    public static var effectiveModels: [ModelInfo] {
        cachedModels ?? fallbackModels
    }

    public static var cachedModels: [ModelInfo]? {
        get {
            guard let data = UserDefaults.standard.data(forKey: cachedModelsKey),
                  let models = try? JSONDecoder().decode([ModelInfo].self, from: data),
                  !models.isEmpty else { return nil }
            return models
        }
        set {
            if let val = newValue, let data = try? JSONEncoder().encode(val) {
                UserDefaults.standard.set(data, forKey: cachedModelsKey)
                UserDefaults.standard.set(Date(), forKey: cachedModelsDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: cachedModelsKey)
                UserDefaults.standard.removeObject(forKey: cachedModelsDateKey)
            }
        }
    }

    public static var isCacheStale: Bool {
        guard let date = UserDefaults.standard.object(forKey: cachedModelsDateKey) as? Date else { return true }
        return Date().timeIntervalSince(date) > cacheTTL
    }

    public static var apiKey: String {
        get {
            UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: apiKeyKey)
            setenv("GEMINI_API_KEY", newValue, 1)
        }
    }

    public static var selectedModel: String {
        get {
            let stored = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
            return stored.isEmpty ? defaultCleanupModel : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: selectedModelKey)
        }
    }

    public static var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func fetchModels() async -> [ModelInfo]? {
        guard isConfigured else { return nil }

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        struct Response: Codable {
            struct RawModel: Codable {
                let name: String
                let displayName: String?
                let supportedGenerationMethods: [String]?
            }
            let models: [RawModel]?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let rawModels = decoded.models else { return nil }

        let models = rawModels.compactMap { raw -> ModelInfo? in
            let id = raw.name.hasPrefix("models/") ? String(raw.name.dropFirst(7)) : raw.name
            let display = raw.displayName ?? id
            guard raw.supportedGenerationMethods?.contains("generateContent") == true else { return nil }
            let idLower = id.lowercased()
            let displayLower = display.lowercased()
            guard !idLower.contains("tts"), !displayLower.contains("tts") else { return nil }
            guard !idLower.contains("nano"), !displayLower.contains("nano") else { return nil }
            guard !idLower.contains("embedding"), !displayLower.contains("embedding") else { return nil }
            guard !idLower.contains("robotics"), !displayLower.contains("robotics") else { return nil }
            return ModelInfo(id: id, displayName: display)
        }

        return models.isEmpty ? nil : models
    }

    public static func migrateFromEnvFile() {
        if isConfigured { return }

        let candidates = [
            FileManager.default.currentDirectoryPath + "/.env",
            Bundle.main.bundleURL.deletingLastPathComponent().path + "/.env",
            NSHomeDirectory() + "/.mop/.env"
        ]

        for path in candidates {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("GEMINI_API_KEY=") else { continue }
                let value = String(trimmed.dropFirst("GEMINI_API_KEY=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty {
                    apiKey = value
                    return
                }
            }
        }
    }
}

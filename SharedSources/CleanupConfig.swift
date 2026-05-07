import Foundation

public enum CleanupDriver: String, CaseIterable, Codable {
    case gemini
    case ollama
    case lmStudio

    public var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
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

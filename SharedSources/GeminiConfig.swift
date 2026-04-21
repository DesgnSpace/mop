import Foundation

public enum GeminiConfig {
    private static let apiKeyKey = "GEMINI_API_KEY"

    public static var apiKey: String {
        get {
            UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: apiKeyKey)
            setenv("GEMINI_API_KEY", newValue, 1)
        }
    }

    public static var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
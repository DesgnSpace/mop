import Foundation

public enum CleanupDriverRegistry {
    public static func driver(for id: CleanupDriver) -> TextCleanupDriver {
        switch id {
        case .gemini:
            return GeminiTextCleanup()
        case .ollama:
            return LocalLLMTextCleanup(driverID: .ollama, baseURL: CleanupConfig.ollamaEndpoint, model: CleanupConfig.ollamaModel)
        case .lmStudio:
            return LocalLLMTextCleanup(driverID: .lmStudio, baseURL: CleanupConfig.lmStudioEndpoint, model: CleanupConfig.lmStudioModel)
        case .openai:
            return OpenAITextCleanup(apiKey: CleanupConfig.openAIAPIKey, model: CleanupConfig.openAIModel)
        case .anthropic:
            return AnthropicTextCleanup(apiKey: CleanupConfig.anthropicAPIKey, model: CleanupConfig.anthropicModel)
        }
    }
}

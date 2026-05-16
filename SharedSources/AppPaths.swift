import Foundation

public enum AppPaths {
    public static let appName = "MOP"

    private static let fileManager = FileManager.default

    public static var appSupportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static func ensureDirectoryExists(_ url: URL) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public static var modelsDirectory: URL {
        let url = appSupportDirectory.appendingPathComponent("Models", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    /// Path to FluidAudio's streaming-EOU model cache (outside MOP's tree — read-only tracking).
    public static var streamingEouModelPath: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-eou-streaming", isDirectory: true)
    }

    public static var whisperKitModelsDirectory: URL {
        return modelsDirectory
    }

    public static var parakeetModelsDirectory: URL {
        let url = modelsDirectory.appendingPathComponent("parakeet", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    public static var qwen3ModelsDirectory: URL {
        let url = modelsDirectory.appendingPathComponent("qwen3", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    public static var transcriptionHistoryFile: URL {
        ensureDirectoryExists(appSupportDirectory)
        return appSupportDirectory.appendingPathComponent("transcription_history.json")
    }

    public static var transcriptionStatsFile: URL {
        ensureDirectoryExists(appSupportDirectory)
        return appSupportDirectory.appendingPathComponent("transcription_stats.json")
    }

    public static func whisperKitModelPath(for modelName: String) -> URL {
        return whisperKitModelsDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
    }

    public static func parakeetModelPath(for modelName: String) -> URL {
        return parakeetModelsDirectory.appendingPathComponent(modelName, isDirectory: true)
    }

    public static func qwen3ModelPath(for modelName: String) -> URL {
        return qwen3ModelsDirectory.appendingPathComponent(modelName, isDirectory: true)
    }
}

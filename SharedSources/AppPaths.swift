import Foundation

public enum AppPaths {
    public static let appName = "SuperVoiceAssistant"

    public static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public static var modelsDirectory: URL {
        let url = appSupportDirectory.appendingPathComponent("Models", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    public static var whisperKitModelsDirectory: URL {
        let url = modelsDirectory.appendingPathComponent("WhisperKit", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    public static var parakeetModelsDirectory: URL {
        let url = modelsDirectory.appendingPathComponent("Parakeet", isDirectory: true)
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
        return whisperKitModelsDirectory.appendingPathComponent(modelName, isDirectory: true)
    }

    public static func parakeetModelPath(for modelName: String) -> URL {
        return parakeetModelsDirectory.appendingPathComponent(modelName, isDirectory: true)
    }
}
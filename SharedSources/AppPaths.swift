import Foundation

public enum AppPaths {
    public static let appName = "MOP"

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
        migrateLegacyModelDirectories(to: url)
        return url
    }

    public static var whisperKitModelsDirectory: URL {
        return modelsDirectory
    }

    public static var parakeetModelsDirectory: URL {
        return modelsDirectory
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

    private static func migrateLegacyModelDirectories(to modelsDirectory: URL) {
        let legacyDirectories = [
            modelsDirectory.appendingPathComponent("WhisperKit", isDirectory: true),
            modelsDirectory.appendingPathComponent("Parakeet", isDirectory: true)
        ]

        for legacyDirectory in legacyDirectories {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: legacyDirectory,
                includingPropertiesForKeys: nil
            ) else { continue }

            for child in children {
                let destination = modelsDirectory.appendingPathComponent(child.lastPathComponent, isDirectory: child.hasDirectoryPath)
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                try? FileManager.default.moveItem(at: child, to: destination)
            }

            try? FileManager.default.removeItem(at: legacyDirectory)
        }
    }
}

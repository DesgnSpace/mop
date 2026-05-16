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
        migrateLegacyModelDirectories(to: url)
        migrateParakeetToSubdir(to: url)
        cleanOrphanedCoreMLDirsOnce(in: url.appendingPathComponent("parakeet", isDirectory: true))
        cleanOrphanedCoreMLDirsOnce(in: url.appendingPathComponent("qwen3", isDirectory: true))
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

    // MARK: - Migrations

    private static var migrationMarker: URL {
        appSupportDirectory.appendingPathComponent("Models").appendingPathComponent(".mop_migration_v1")
    }

    private static func migrateLegacyModelDirectories(to modelsDirectory: URL) {
        let legacyDirectories = [
            modelsDirectory.appendingPathComponent("WhisperKit", isDirectory: true),
            modelsDirectory.appendingPathComponent("Parakeet", isDirectory: true)
        ]

        for legacyDirectory in legacyDirectories {
            guard let children = try? fileManager.contentsOfDirectory(
                at: legacyDirectory,
                includingPropertiesForKeys: nil
            ) else { continue }

            for child in children {
                let dest = modelsDirectory.appendingPathComponent(child.lastPathComponent, isDirectory: child.hasDirectoryPath)
                guard !fileManager.fileExists(atPath: dest.path) else { continue }
                try? fileManager.moveItem(at: child, to: dest)
            }

            try? fileManager.removeItem(at: legacyDirectory)
        }
    }

    private static func migrateParakeetToSubdir(to modelsDirectory: URL) {
        guard !fileManager.fileExists(atPath: migrationMarker.path) else { return }

        let parakeetDir = modelsDirectory.appendingPathComponent("parakeet", isDirectory: true)
        ensureDirectoryExists(parakeetDir)

        guard let children = try? fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for child in children {
            guard child.lastPathComponent.hasPrefix("parakeet-"), child.hasDirectoryPath else { continue }
            let dest = parakeetDir.appendingPathComponent(child.lastPathComponent, isDirectory: true)
            guard !fileManager.fileExists(atPath: dest.path) else { continue }
            try? fileManager.moveItem(at: child, to: dest)
        }

        try? Data().write(to: migrationMarker)
    }

    private static var coreMLCleanupMarker: URL {
        appSupportDirectory.appendingPathComponent("Models").appendingPathComponent(".coreml_orphan_cleanup_done")
    }

    private static func cleanOrphanedCoreMLDirsOnce(in directory: URL) {
        guard !fileManager.fileExists(atPath: coreMLCleanupMarker.path) else { return }
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for child in children where child.lastPathComponent.hasSuffix("-coreml") {
            try? fileManager.removeItem(at: child)
        }
        try? Data().write(to: coreMLCleanupMarker)
    }
}

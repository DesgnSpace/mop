import Foundation

/// Shared sentinel for tracking model download completeness across all engines.
/// Written to `.download_metadata.json` inside the model directory after a successful download.
public struct ModelDownloadMetadata: Codable {
    public let modelName: String
    public let downloadDate: Date
    public let downloadVersion: String
    public let fileCount: Int?
    public let totalSize: Int64?
    public let isComplete: Bool

    static let fileName = ".download_metadata.json"

    public static func write(to directory: URL, modelName: String) {
        let fm = FileManager.default
        var count = 0
        var size: Int64 = 0
        if let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            while let url = enumerator.nextObject() as? URL {
                count += 1
                if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        let meta = ModelDownloadMetadata(
            modelName: modelName,
            downloadDate: Date(),
            downloadVersion: "1.0",
            fileCount: count,
            totalSize: size,
            isComplete: true
        )
        let destFile = directory.appendingPathComponent(fileName)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: destFile)
        }
    }

    public static func isComplete(at directory: URL) -> Bool {
        let metaFile = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: metaFile),
              let meta = try? JSONDecoder().decode(ModelDownloadMetadata.self, from: data) else {
            return false
        }
        return meta.isComplete
    }

    public static func remove(from directory: URL) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}

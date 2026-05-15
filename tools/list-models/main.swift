import Foundation
import SharedModels

print("MOP Local Models")
print(String(repeating: "=", count: 40))

let fm = FileManager.default
var totalSize: Int64 = 0

func dirSize(_ url: URL) -> Int64 {
    guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
    var size: Int64 = 0
    for case let fileURL as URL in enumerator {
        if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            size += Int64(fileSize)
        }
    }
    return size
}

func formatMB(_ bytes: Int64) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_048_576)
}

for model in ModelData.availableModels {
    var path: URL?
    switch model.engine {
    case .whisperKit:
        guard let wkName = model.whisperKitModelName else { continue }
        let p = AppPaths.whisperKitModelPath(for: wkName)
        if fm.fileExists(atPath: p.path) { path = p }
    case .parakeet:
        guard let version = model.parakeetVersion else { continue }
        let p = AppPaths.parakeetModelPath(for: version.coreMLDirectoryName)
        if fm.fileExists(atPath: p.path) { path = p }
    case .qwen3:
        guard let variant = model.qwen3Variant else { continue }
        let p = AppPaths.qwen3ModelPath(for: variant.coreMLDirectoryName)
        if fm.fileExists(atPath: p.path) { path = p }
    }

    if let path = path {
        let size = dirSize(path)
        totalSize += size
        print("  [\(model.name)] \(model.displayName) — \(formatMB(size))")
    }
}

if totalSize > 0 {
    print("\nTotal: \(formatMB(totalSize))")
} else {
    print("\nNo models downloaded.")
}

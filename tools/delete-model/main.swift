import Foundation
import SharedModels

print("Delete MOP Model")
print(String(repeating: "=", count: 40))

let arguments = CommandLine.arguments
if arguments.count < 2 {
    print("Usage: swift run DeleteModel <model-name>")
    print("\nAvailable models:")
    for model in ModelData.availableModels {
        print("  \(model.name) — \(model.displayName)")
    }
    exit(1)
}

let modelName = arguments[1]
guard let model = ModelData.availableModels.first(where: { $0.name == modelName }) else {
    print("Unknown model: \(modelName)")
    print("\nAvailable models:")
    for m in ModelData.availableModels {
        print("  \(m.name) — \(m.displayName)")
    }
    exit(1)
}

let fm = FileManager.default
var path: URL?

switch model.engine {
case .whisperKit:
    guard let wkName = model.whisperKitModelName else { exit(1) }
    let p = AppPaths.whisperKitModelPath(for: wkName)
    if fm.fileExists(atPath: p.path) { path = p }
    WhisperModelManager.shared.removeDownloadMetadata(for: wkName)
case .parakeet:
    guard let version = model.parakeetVersion else { exit(1) }
    let p = AppPaths.parakeetModelPath(for: version.coreMLDirectoryName)
    if fm.fileExists(atPath: p.path) { path = p }
case .qwen3:
    guard let variant = model.qwen3Variant else { exit(1) }
    let p = AppPaths.qwen3ModelPath(for: variant.coreMLDirectoryName)
    if fm.fileExists(atPath: p.path) { path = p }
    if #available(macOS 15, *) {
        Qwen3Transcriber.deleteCachedModel(variant: variant)
    }
}

guard let modelPath = path else {
    print("Model '\(model.displayName)' is not downloaded.")
    exit(0)
}

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

let sizeMB = Double(dirSize(modelPath)) / 1_048_576
print("Found: \(model.displayName) (\(String(format: "%.1f", sizeMB)) MB)")

print("Delete? (y/N): ", terminator: "")
guard let response = readLine()?.lowercased(), response == "y" else {
    print("Cancelled.")
    exit(0)
}

do {
    try fm.removeItem(at: modelPath)
    print("Deleted: \(model.displayName)")
} catch {
    print("Failed: \(error.localizedDescription)")
    exit(1)
}

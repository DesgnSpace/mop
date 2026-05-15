import Foundation
import SharedModels

print("Delete All MOP Models")
print(String(repeating: "=", count: 40))

let fm = FileManager.default

var models: [(name: String, displayName: String, path: URL)] = []

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
        models.append((model.name, model.displayName, path))
        if model.engine == .whisperKit, let wkName = model.whisperKitModelName {
            WhisperModelManager.shared.removeDownloadMetadata(for: wkName)
        }
    }
}

if models.isEmpty {
    print("No models found to delete.")
    exit(0)
}

print("Found \(models.count) model(s):")
for m in models {
    print("  \(m.displayName) (\(m.name))")
}

print("\nDelete all? (y/N): ", terminator: "")
guard let response = readLine()?.lowercased(), response == "y" else {
    print("Cancelled.")
    exit(0)
}

for m in models {
    print("  Deleting \(m.displayName)...", terminator: "")
    do {
        try fm.removeItem(at: m.path)
        print(" done")
    } catch {
        print(" failed: \(error.localizedDescription)")
    }
}

print("\nAll models deleted.")

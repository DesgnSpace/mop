import Foundation
import SharedModels

print("MOP Model Validation")
print(String(repeating: "=", count: 40))

let fm = FileManager.default

for model in ModelData.availableModels {
    var path: URL?

    switch model.engine {
    case .whisperKit:
        guard let wkName = model.whisperKitModelName else { continue }
        let p = AppPaths.whisperKitModelPath(for: wkName)
        path = p
        if fm.fileExists(atPath: p.path) {
            let isComplete = WhisperModelManager.shared.isModelDownloaded(wkName)
            print("\(model.displayName): \(isComplete ? "complete" : "incomplete (missing metadata)")")
        }
    case .parakeet:
        guard let version = model.parakeetVersion else { continue }
        let p = AppPaths.parakeetModelPath(for: version.coreMLDirectoryName)
        path = p
        if fm.fileExists(atPath: p.path) {
            let contents = (try? fm.contentsOfDirectory(atPath: p.path)) ?? []
            print("\(model.displayName): downloaded (\(contents.count) files)")
        }
    case .qwen3:
        guard let variant = model.qwen3Variant else { continue }
        let p = AppPaths.qwen3ModelPath(for: variant.coreMLDirectoryName)
        path = p
        if fm.fileExists(atPath: p.path) {
            let contents = (try? fm.contentsOfDirectory(atPath: p.path)) ?? []
            print("\(model.displayName): downloaded (\(contents.count) files)")
        }
    }

    if let path = path, !fm.fileExists(atPath: path.path) {
        print("\(model.displayName): not downloaded")
    }
}

print("\nDone.")

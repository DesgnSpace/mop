import Foundation
import AVFoundation
import FluidAudio

public enum Qwen3Variant: String, CaseIterable {
    case f32 = "qwen3-f32"
    case int8 = "qwen3-int8"

    public var displayName: String {
        switch self {
        case .f32: return "Qwen3 ASR (FP16)"
        case .int8: return "Qwen3 ASR (Int8)"
        }
    }

    public var description: String {
        switch self {
        case .f32: return "Full precision, best quality"
        case .int8: return "Quantized, half the RAM"
        }
    }

    public var size: String {
        switch self {
        case .f32: return "~1.75 GB"
        case .int8: return "~900 MB"
        }
    }

    public var asrVariant: Qwen3AsrVariant {
        switch self {
        case .f32: return .f32
        case .int8: return .int8
        }
    }

    public var coreMLDirectoryName: String {
        switch self {
        case .f32: return "qwen3-asr-0.6b-f32"
        case .int8: return "qwen3-asr-0.6b-int8"
        }
    }
}

public enum Qwen3LoadingState: Equatable {
    case notDownloaded
    case downloading
    case downloaded
    case loading
    case loaded
}

@available(macOS 15, *)
public class Qwen3Transcriber {
    public enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case transcriptionFailed(String)
        case loadingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "Qwen3 model not loaded"
            case .transcriptionFailed(let m): return "Transcription failed: \(m)"
            case .loadingFailed(let m): return "Model loading failed: \(m)"
            }
        }
    }

    private var manager: Qwen3AsrManager?
    private(set) public var loadedVariant: Qwen3Variant?
    private(set) public var loadingState: Qwen3LoadingState = .notDownloaded

    public init() {}

    public func loadModel(variant: Qwen3Variant) async throws {
        loadingState = .downloading
        print("Loading Qwen3 model: \(variant.displayName)")

        do {
            let fluidAudioDir = try await Qwen3AsrModels.download(variant: variant.asrVariant)

            let mopDir = AppPaths.qwen3ModelPath(for: variant.coreMLDirectoryName)
            AppPaths.ensureDirectoryExists(mopDir)
            try moveContentsIfNeeded(from: fluidAudioDir, to: mopDir)

            loadingState = .loading
            let m = Qwen3AsrManager()
            try await m.loadModels(from: mopDir)

            manager = m
            loadedVariant = variant
            loadingState = .loaded
            print("Qwen3 model loaded: \(variant.displayName)")
        } catch {
            loadingState = .notDownloaded
            loadedVariant = nil
            print("Failed to load Qwen3 model: \(error)")
            throw TranscriptionError.loadingFailed(error.localizedDescription)
        }
    }

    private func moveContentsIfNeeded(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }

        let contents = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for item in contents {
            let dest = destination.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
            try fm.moveItem(at: item, to: dest)
        }
    }

    public static func deleteCachedModel(variant: Qwen3Variant) {
        let fm = FileManager.default
        let mopDir = AppPaths.qwen3ModelPath(for: variant.coreMLDirectoryName)
        try? fm.removeItem(at: mopDir)

        let fluidAudioDir = Qwen3AsrModels.defaultCacheDirectory(variant: variant.asrVariant)
        try? fm.removeItem(at: fluidAudioDir)
    }

    public func transcribe(audioSamples: [Float]) async throws -> String {
        guard let m = manager else {
            throw TranscriptionError.modelNotLoaded
        }
        do {
            let result = try await m.transcribe(audioSamples: audioSamples)
            print("Qwen3 transcription complete: \(result)")
            return result
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    public var isReady: Bool {
        loadingState == .loaded && manager != nil
    }

    public func unloadModel() {
        manager = nil
        loadedVariant = nil
        loadingState = .notDownloaded
        print("Qwen3 model unloaded")
    }
}

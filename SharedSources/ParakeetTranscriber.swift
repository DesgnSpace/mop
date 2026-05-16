import Foundation
import AVFoundation
import FluidAudio

/// Available Parakeet model versions
public enum ParakeetVersion: String, CaseIterable {
    case v2 = "parakeet-v2"
    case v3 = "parakeet-v3"
    case tdtCtc110m = "parakeet-tdt-ctc-110m"
    case ctcZhCn = "parakeet-ctc-0.6b-zh-cn"
    case ctcJa = "parakeet-ctc-0.6b-ja"  // maps to tdtJa in FluidAudio 0.14+
    case tdtJa = "parakeet-tdt-0.6b-ja"

    public var displayName: String {
        switch self {
        case .v2:
            return "Parakeet v2"
        case .v3:
            return "Parakeet v3"
        case .tdtCtc110m:
            return "Parakeet TDT-CTC 110M"
        case .ctcZhCn:
            return "Parakeet CTC Chinese"
        case .ctcJa:
            return "Parakeet CTC Japanese"
        case .tdtJa:
            return "Parakeet TDT Japanese"
        }
    }

    public var description: String {
        switch self {
        case .v2:
            return "Fast and accurate, English-optimized"
        case .v3:
            return "Latest version, 25 European languages"
        case .tdtCtc110m:
            return "Small fast English model"
        case .ctcZhCn:
            return "Mandarin Chinese ASR"
        case .ctcJa:
            return "Japanese CTC ASR"
        case .tdtJa:
            return "Japanese TDT ASR"
        }
    }

    public var size: String {
        switch self {
        case .v2:
            return "~600MB"
        case .v3, .ctcZhCn, .ctcJa, .tdtJa:
            return "~600MB"
        case .tdtCtc110m:
            return "~110MB"
        }
    }

    public var speed: String {
        switch self {
        case .v2:
            return "~110x RTF"
        case .v3:
            return "~210x RTF"
        case .tdtCtc110m:
            return "Very fast"
        case .ctcZhCn, .ctcJa, .tdtJa:
            return "Fast"
        }
    }

    public var accuracy: String {
        switch self {
        case .v2:
            return "1.69% WER"
        case .v3:
            return "1.93% WER"
        case .tdtCtc110m, .ctcZhCn, .ctcJa, .tdtJa:
            return "See model card"
        }
    }

    /// Accuracy as percentage (100 - WER) for display in AccuracyBar
    public var accuracyPercent: String {
        switch self {
        case .v2:
            return "98.31%"  // 100 - 1.69
        case .v3:
            return "98.07%"  // 100 - 1.93
        case .tdtCtc110m, .ctcZhCn, .ctcJa, .tdtJa:
            return "~95%"
        }
    }

    public var languages: String {
        switch self {
        case .v2:
            return "English"
        case .v3:
            return "25 languages"
        case .tdtCtc110m:
            return "English"
        case .ctcZhCn:
            return "Chinese"
        case .ctcJa, .tdtJa:
            return "Japanese"
        }
    }

    /// Convert to FluidAudio's AsrModelVersion
    public var asrModelVersion: AsrModelVersion {
        switch self {
        case .v2:
            return .v2
        case .v3:
            return .v3
        case .tdtCtc110m:
            return .tdtCtc110m
        case .ctcZhCn:
            return .ctcZhCn
        case .ctcJa:
            return .tdtJa  // ctcJa removed in FluidAudio 0.14; both Japanese models use tdtJa
        case .tdtJa:
            return .tdtJa
        }
    }

    public var coreMLDirectoryName: String {
        switch self {
        case .v2:
            return "parakeet-tdt-0.6b-v2"
        case .v3:
            return "parakeet-tdt-0.6b-v3"
        case .tdtCtc110m:
            return "parakeet-tdt-ctc-110m"
        case .ctcZhCn:
            return "parakeet-ctc-0.6b-zh-cn"
        case .ctcJa:
            return "parakeet-0.6b-ja"
        case .tdtJa:
            return "parakeet-0.6b-ja"
        }
    }
}

/// Loading state for Parakeet models
public enum ParakeetLoadingState: Equatable {
    case notDownloaded
    case downloading
    case downloaded
    case loading
    case loaded
}

/// Wrapper for FluidAudio Parakeet transcription
public class ParakeetTranscriber {

    public enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case transcriptionFailed(String)
        case loadingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Parakeet model not loaded"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            case .loadingFailed(let message):
                return "Model loading failed: \(message)"
            }
        }
    }

    private var asrManager: AsrManager?
    private var decoderState: TdtDecoderState?
    private(set) public var loadedVersion: ParakeetVersion?
    private(set) public var loadingState: ParakeetLoadingState = .notDownloaded

    public init() {}

    /// Load a Parakeet model
    /// - Parameter version: The version of the model to load
    public func loadModel(version: ParakeetVersion) async throws {
        let modelDirectory = AppPaths.parakeetModelPath(for: version.coreMLDirectoryName)
        let alreadyDownloaded = ModelDownloadMetadata.isComplete(at: modelDirectory)
        loadingState = alreadyDownloaded ? .loading : .downloading
        print("Loading Parakeet model: \(version.displayName) (download needed: \(!alreadyDownloaded))")

        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        loadingState = .loading

        var lastError: Error?

        for attempt in 1...3 {
            do {
                let manager = AsrManager()
                let asrModels = try await AsrModels.load(from: modelDirectory, version: version.asrModelVersion)
                try await manager.loadModels(asrModels)

                asrManager = manager
                decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
                loadedVersion = version
                loadingState = .loaded
                ModelDownloadMetadata.write(to: modelDirectory, modelName: version.coreMLDirectoryName)
                print("Parakeet model loaded successfully: \(version.displayName)")
                return
            } catch {
                lastError = error
                print("Parakeet load attempt \(attempt) failed: \(error)")
                if attempt < 3 {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }

        loadingState = .notDownloaded
        loadedVersion = nil
        throw TranscriptionError.loadingFailed(lastError?.localizedDescription ?? "unknown error")
    }

    /// Transcribe audio samples
    /// - Parameter audioSamples: Float array of audio samples at 16kHz mono
    /// - Returns: Transcribed text
    public func transcribe(audioSamples: [Float]) async throws -> String {
        guard let manager = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }

        if decoderState == nil {
            decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        }

        do {
            print("Transcribing \(audioSamples.count) samples with Parakeet...")
            if audioSamples.count > ASRConfig.default.streamingThreshold {
                let audioURL = try writeTemporaryWAV(audioSamples)
                defer { try? FileManager.default.removeItem(at: audioURL) }

                let result = try await manager.transcribeDiskBacked(audioURL, decoderState: &decoderState!)
                print("Parakeet disk-backed transcription complete: \(result.text)")
                return result.text
            }

            let result = try await manager.transcribe(audioSamples, decoderState: &decoderState!)
            let text = result.text
            print("Parakeet transcription complete: \(text)")
            return text
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    private func writeTemporaryWAV(_ audioSamples: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioSamples.count)) else {
            throw TranscriptionError.transcriptionFailed("Failed to create temporary audio buffer")
        }

        buffer.frameLength = AVAudioFrameCount(audioSamples.count)
        audioSamples.withUnsafeBufferPointer { source in
            buffer.floatChannelData?[0].update(from: source.baseAddress!, count: audioSamples.count)
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    /// Check if a model is loaded and ready
    public var isReady: Bool {
        get async {
            (await asrManager?.isAvailable ?? false) && loadingState == .loaded
        }
    }

    /// Unload the current model to free memory
    public func unloadModel() {
        asrManager = nil
        decoderState = nil
        loadedVersion = nil
        loadingState = .notDownloaded
        print("Parakeet model unloaded")
    }
}

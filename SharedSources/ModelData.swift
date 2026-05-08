import Foundation

public enum ModelEngine: String, Codable {
    case whisperKit
    case parakeet
}

public enum ModelTier: String, CaseIterable {
    case `default`
    case highAccuracy
    case lowMemory
    case fast

    public var displayName: String {
        switch self {
        case .default:      return "Default"
        case .highAccuracy: return "High Accuracy"
        case .lowMemory:    return "Low Memory"
        case .fast:         return "Fast"
        }
    }

    public var icon: String {
        switch self {
        case .default:      return "star.fill"
        case .highAccuracy: return "chart.bar.fill"
        case .lowMemory:    return "memorychip"
        case .fast:         return "bolt.fill"
        }
    }
}

public struct ModelInfo {
    public let name: String
    public let engine: ModelEngine
    public let tier: ModelTier
    public let displayName: String
    public let whisperKitModelName: String?   // nil for Parakeet models
    public let parakeetVersion: ParakeetVersion?  // nil for WhisperKit models
    public let size: String
    public let speed: String
    public let accuracy: String
    public let accuracyNote: String
    public let languages: String
    public let description: String
    public let sourceURL: String

    public init(
        name: String,
        engine: ModelEngine,
        tier: ModelTier,
        displayName: String,
        whisperKitModelName: String? = nil,
        parakeetVersion: ParakeetVersion? = nil,
        size: String,
        speed: String,
        accuracy: String,
        accuracyNote: String,
        languages: String,
        description: String,
        sourceURL: String
    ) {
        self.name = name
        self.engine = engine
        self.tier = tier
        self.displayName = displayName
        self.whisperKitModelName = whisperKitModelName
        self.parakeetVersion = parakeetVersion
        self.size = size
        self.speed = speed
        self.accuracy = accuracy
        self.accuracyNote = accuracyNote
        self.languages = languages
        self.description = description
        self.sourceURL = sourceURL
    }
}

public struct ModelData {
    public static var availableModels: [ModelInfo] {
        var models: [ModelInfo] = [
            // MARK: - Default Tier

            // Whisper Large v3 Turbo
            // 809M parameters, 4 decoder layers, similar to large-v2 accuracy
            // WhisperKit: 107x real-time on M2 Ultra
            ModelInfo(
                name: "large-v3-turbo",
                engine: .whisperKit,
                tier: .default,
                displayName: "Large v3 Turbo",
                whisperKitModelName: "openai_whisper-large-v3-v20240930_turbo_632MB",
                size: "632 MB",
                speed: "8x faster",
                accuracy: "~96%",
                accuracyNote: "4 decoder layers, similar to large-v2 accuracy (OpenAI Oct 2024)",
                languages: "99 languages",
                description: "Fast multilingual transcription with minimal accuracy loss",
                sourceURL: "https://huggingface.co/openai/whisper-large-v3-turbo"
            ),

            ModelInfo(
                name: "large-v3-turbo-full",
                engine: .whisperKit,
                tier: .default,
                displayName: "Large v3 Turbo (Full)",
                whisperKitModelName: "openai_whisper-large-v3_turbo_954MB",
                size: "954 MB",
                speed: "8x faster",
                accuracy: "~96%",
                accuracyNote: "Largest current CoreML Large v3 Turbo artifact from argmaxinc/whisperkit-coreml",
                languages: "99 languages",
                description: "Largest Turbo CoreML build for best Turbo quality",
                sourceURL: "https://huggingface.co/openai/whisper-large-v3-turbo"
            ),

            // MARK: - High Accuracy Tier

            // Whisper Large v3
            // 1.54B parameters, 1.80% WER on LibriSpeech test-clean
            // 10-20% error reduction vs v2 across all languages
            ModelInfo(
                name: "large-v3",
                engine: .whisperKit,
                tier: .highAccuracy,
                displayName: "Large v3",
                whisperKitModelName: "openai_whisper-large-v3",
                size: "1.54 GB",
                speed: "Baseline",
                accuracy: "98.2%",
                accuracyNote: "State-of-the-art: 1.80% WER LibriSpeech test-clean (Aqua Voice Nov 2024)",
                languages: "99 languages",
                description: "Highest accuracy, best for professional transcription",
                sourceURL: "https://huggingface.co/openai/whisper-large-v3"
            ),

            ModelInfo(
                name: "large-v3-compact",
                engine: .whisperKit,
                tier: .highAccuracy,
                displayName: "Large v3 (Compact)",
                whisperKitModelName: "openai_whisper-large-v3_947MB",
                size: "947 MB",
                speed: "Baseline",
                accuracy: "98.2%",
                accuracyNote: "Smaller current CoreML Large v3 artifact from argmaxinc/whisperkit-coreml",
                languages: "99 languages",
                description: "High accuracy Large v3 with smaller disk footprint",
                sourceURL: "https://huggingface.co/openai/whisper-large-v3"
            ),

            // MARK: - Low Memory Tier

            // Distil-Whisper Large v3
            // 756M parameters, English-only, 6.3x faster than large-v3
            // 2.43% WER on LibriSpeech validation-clean
            ModelInfo(
                name: "distil-large-v3",
                engine: .whisperKit,
                tier: .lowMemory,
                displayName: "Distil Large v3",
                whisperKitModelName: "distil-whisper_distil-large-v3",
                size: "756 MB",
                speed: "6.3x faster",
                accuracy: "97.6%",
                accuracyNote: "English-only: 2.43% WER LibriSpeech validation-clean (HF model card Jan 2025)",
                languages: "English only",
                description: "Fastest high-accuracy option for English",
                sourceURL: "https://huggingface.co/distil-whisper/distil-large-v3"
            ),

            // Distil-Whisper Large v3 (Lite)
            // Same architecture as Distil Large v3, compressed to 594 MB
            ModelInfo(
                name: "distil-large-v3-lite",
                engine: .whisperKit,
                tier: .lowMemory,
                displayName: "Distil Large v3 (Lite)",
                whisperKitModelName: "distil-whisper_distil-large-v3_594MB",
                size: "594 MB",
                speed: "7x faster",
                accuracy: "97.4%",
                accuracyNote: "Quantized Distil Large v3 - slightly smaller footprint, minimal accuracy delta",
                languages: "English only",
                description: "Smallest high-accuracy English model",
                sourceURL: "https://huggingface.co/distil-whisper/distil-large-v3"
            ),

            // Distil-Whisper Large v3 Turbo
            ModelInfo(
                name: "distil-large-v3-turbo",
                engine: .whisperKit,
                tier: .lowMemory,
                displayName: "Distil Large v3 Turbo",
                whisperKitModelName: "distil-whisper_distil-large-v3_turbo_600MB",
                size: "600 MB",
                speed: "12x faster",
                accuracy: "97.0%",
                accuracyNote: "Turbo Distil Large v3 CoreML variant from argmaxinc/whisperkit-coreml",
                languages: "English only",
                description: "Fastest low-memory English Whisper option",
                sourceURL: "https://huggingface.co/distil-whisper/distil-large-v3"
            ),

            // MARK: - Fast Tier (Parakeet)

            // Parakeet v3 — 25 European languages, ~210x RTF
            ModelInfo(
                name: "parakeet-v3",
                engine: .parakeet,
                tier: .fast,
                displayName: "Parakeet v3",
                parakeetVersion: .v3,
                size: "~600 MB",
                speed: "~210x RTF",
                accuracy: "98.07%",
                accuracyNote: "1.93% WER on LibriSpeech test-clean (FluidAudio)",
                languages: "25 languages",
                description: "Latest Parakeet — multilingual, extremely fast",
                sourceURL: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml"
            ),

            // NVIDIA Parakeet v2 - English-optimized, ~110x RTF
            ModelInfo(
                name: "parakeet-v2",
                engine: .parakeet,
                tier: .fast,
                displayName: "NVIDIA Parakeet v2",
                parakeetVersion: .v2,
                size: "~600 MB",
                speed: "~110x RTF",
                accuracy: "98.31%",
                accuracyNote: "1.69% WER on LibriSpeech test-clean (NVIDIA model card)",
                languages: "English",
                description: "Highest accuracy Parakeet — English-optimized",
                sourceURL: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2"
            ),

            ModelInfo(
                name: "parakeet-tdt-ctc-110m",
                engine: .parakeet,
                tier: .fast,
                displayName: "Parakeet TDT-CTC 110M",
                parakeetVersion: .tdtCtc110m,
                size: "~110 MB",
                speed: "Very fast",
                accuracy: "~95%",
                accuracyNote: "Small FluidAudio CoreML Parakeet variant",
                languages: "English",
                description: "Smallest fast English Parakeet option",
                sourceURL: "https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml"
            ),

            ModelInfo(
                name: "parakeet-ctc-zh-cn",
                engine: .parakeet,
                tier: .fast,
                displayName: "Parakeet Chinese",
                parakeetVersion: .ctcZhCn,
                size: "~600 MB",
                speed: "Fast",
                accuracy: "~95%",
                accuracyNote: "Mandarin Chinese FluidAudio CoreML Parakeet CTC variant",
                languages: "Chinese",
                description: "Mandarin Chinese local transcription",
                sourceURL: "https://huggingface.co/FluidInference/parakeet-ctc-0.6b-zh-cn-coreml"
            ),

            ModelInfo(
                name: "parakeet-ctc-ja",
                engine: .parakeet,
                tier: .fast,
                displayName: "Parakeet Japanese CTC",
                parakeetVersion: .ctcJa,
                size: "~600 MB",
                speed: "Fast",
                accuracy: "~95%",
                accuracyNote: "Japanese FluidAudio CoreML Parakeet CTC variant",
                languages: "Japanese",
                description: "Japanese local transcription",
                sourceURL: "https://huggingface.co/FluidInference/parakeet-0.6b-ja-coreml"
            ),

            ModelInfo(
                name: "parakeet-tdt-ja",
                engine: .parakeet,
                tier: .fast,
                displayName: "Parakeet Japanese TDT",
                parakeetVersion: .tdtJa,
                size: "~600 MB",
                speed: "Fast",
                accuracy: "~95%",
                accuracyNote: "Japanese FluidAudio CoreML Parakeet TDT variant",
                languages: "Japanese",
                description: "Japanese local transcription with TDT decoder",
                sourceURL: "https://huggingface.co/FluidInference/parakeet-0.6b-ja-coreml"
            ),
        ]

        #if DEBUG
        models.append(
            ModelInfo(
                name: "tiny-test",
                engine: .whisperKit,
                tier: .default,
                displayName: "Tiny (Test Only)",
                whisperKitModelName: "openai_whisper-tiny",
                size: "39 MB",
                speed: "32x faster",
                accuracy: "~87%",
                accuracyNote: "Test model only — not for production use",
                languages: "99 languages",
                description: "DEV ONLY: Quick testing model with lower accuracy",
                sourceURL: "https://huggingface.co/openai/whisper-tiny"
            )
        )
        #endif

        return models
    }
}

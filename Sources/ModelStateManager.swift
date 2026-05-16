import Foundation
import SwiftUI
import WhisperKit
import SharedModels
import FluidAudio

/// Transcription engine selection
public enum TranscriptionEngine: String, CaseIterable {
    case whisperKit = "whisperKit"
    case parakeet = "parakeet"
    case qwen3 = "qwen3"

    public var displayName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .parakeet:   return "Parakeet"
        case .qwen3:      return "Qwen3 ASR"
        }
    }

    public var description: String {
        switch self {
        case .whisperKit: return "On-device transcription by Argmax"
        case .parakeet:   return "Fast & accurate by FluidAudio"
        case .qwen3:      return "Multilingual ASR by FluidAudio (macOS 15+)"
        }
    }
}

/// Unified loading state for any model — collapses WhisperKit and Parakeet state shapes
public enum UnifiedLoadingState: Equatable {
    case notDownloaded
    case downloading(progress: Double)  // progress == -1 → indeterminate
    case validating
    case downloaded
    case loading
    case loaded
}

@MainActor
class ModelStateManager: ObservableObject {
    static let shared = ModelStateManager()

    enum ModelLoadingState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case validating
        case downloaded
        case loading
        case loaded
    }

    // MARK: - Engine Selection
    @Published var selectedEngine: TranscriptionEngine = .whisperKit {
        didSet {
            UserDefaults.standard.set(selectedEngine.rawValue, forKey: "selectedTranscriptionEngine")
        }
    }

    // MARK: - Parakeet State
    @Published var loadedParakeetTranscriber: ParakeetTranscriber? = nil
    @Published var parakeetVersion: ParakeetVersion = .v2 {
        didSet {
            UserDefaults.standard.set(parakeetVersion.rawValue, forKey: "selectedParakeetVersion")
        }
    }
    @Published var parakeetLoadingState: ParakeetLoadingState = .notDownloaded
    private var currentParakeetLoadingTask: Task<Void, Never>? = nil

    // MARK: - Qwen3 State
    @Published var loadedQwen3Transcriber: AnyObject? = nil  // Qwen3Transcriber (macOS 15+)
    @Published var qwen3Variant: Qwen3Variant = .f32 {
        didSet {
            UserDefaults.standard.set(qwen3Variant.rawValue, forKey: "selectedQwen3Variant")
        }
    }
    @Published var qwen3LoadingState: Qwen3LoadingState = .notDownloaded
    private var currentQwen3LoadingTask: Task<Void, Never>? = nil

    // MARK: - Update checking
    @Published var availableUpdates: [String: String] = [:]  // modelName → newer whisperKitModelName
    @Published var isCheckingUpdates = false
    private let modelVariantOverridesKey = "modelVariantOverrides"
    private var modelVariantOverrides: [String: String] = [:]

    // MARK: - WhisperKit State
    @Published var downloadedModels: Set<String> = []
    @Published var isCheckingModels = true  // Start as true to prevent flash
    @Published var selectedModel: String? = nil {
        didSet {
            // Persist the selected model to UserDefaults
            if let model = selectedModel {
                UserDefaults.standard.set(model, forKey: "selectedWhisperModel")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedWhisperModel")
            }
        }
    }
    @Published var modelLoadingStates: [String: ModelLoadingState] = [:]
    @Published var loadedWhisperKit: WhisperKit? = nil
    private var currentLoadingTask: Task<WhisperKit?, Never>? = nil

    private init() {
        // Restore the selected engine from UserDefaults
        if let engineRaw = UserDefaults.standard.string(forKey: "selectedTranscriptionEngine"),
           let engine = TranscriptionEngine(rawValue: engineRaw) {
            self.selectedEngine = engine
        }

        // Restore the selected Parakeet version from UserDefaults
        if let versionRaw = UserDefaults.standard.string(forKey: "selectedParakeetVersion"),
           let version = ParakeetVersion(rawValue: versionRaw) {
            self.parakeetVersion = version
        }

        // Restore the selected Qwen3 variant from UserDefaults
        if let variantRaw = UserDefaults.standard.string(forKey: "selectedQwen3Variant"),
           let variant = Qwen3Variant(rawValue: variantRaw) {
            self.qwen3Variant = variant
        }

        // Restore the selected WhisperKit model from UserDefaults
        self.selectedModel = UserDefaults.standard.string(forKey: "selectedWhisperModel")
        self.modelVariantOverrides = UserDefaults.standard.dictionary(forKey: modelVariantOverridesKey) as? [String: String] ?? [:]
    }
    
    func checkDownloadedModels() async {
        // Don't reset to empty - keep existing state until check completes
        var newDownloadedModels: Set<String> = []
        let modelManager = WhisperModelManager.shared

        // Process each model in parallel for faster checking
        await withTaskGroup(of: (String, Bool).self) { group in
            for model in ModelData.availableModels where model.engine == .whisperKit {
                guard let whisperKitModelName = whisperKitModelName(for: model) else { continue }
                let modelPath = getModelPath(for: whisperKitModelName)
                
                group.addTask {
                    // First check if directory exists
                    if !FileManager.default.fileExists(atPath: modelPath.path) {
                        return (model.name, false)
                    }
                    
                    // Check if we have metadata marking it as complete
                    if modelManager.isModelDownloaded(whisperKitModelName) {
                        // Trust our metadata if it says complete
                        return (model.name, true)
                    }
                    
                    // Try to load the model with WhisperKit to validate it's complete
                    do {
                        let _ = try await WhisperKit(
                            modelFolder: modelPath.path,
                            verbose: false,
                            logLevel: .error,
                            load: true
                        )
                        
                        // If loading succeeded, mark it in our manager
                        modelManager.markModelAsDownloaded(whisperKitModelName)
                        return (model.name, true)
                    } catch {
                        // Model exists but is incomplete or corrupted
                        print("Model \(model.name) exists but is incomplete")
                        return (model.name, false)
                    }
                }
            }
            
            // Collect results
            for await (modelName, isComplete) in group {
                if isComplete {
                    newDownloadedModels.insert(modelName)
                }
            }
        }
        
        // Update the published properties
        await MainActor.run {
            self.downloadedModels = newDownloadedModels
            
            // Update loading states for downloaded models
            for model in ModelData.availableModels {
                if newDownloadedModels.contains(model.name) {
                    // Only set to downloaded if not already loaded
                    if modelLoadingStates[model.name] != .loaded {
                        setLoadingState(for: model.name, state: .downloaded)
                    }
                } else {
                    setLoadingState(for: model.name, state: .notDownloaded)
                }
            }
            
            // If no model is selected but we have downloaded models, select the first one
            // Or if the selected model is no longer available, select the first one
            if let selected = self.selectedModel, !newDownloadedModels.contains(selected) {
                // Previously selected model is no longer available
                self.selectedModel = newDownloadedModels.first
            } else if self.selectedModel == nil && !newDownloadedModels.isEmpty {
                self.selectedModel = newDownloadedModels.first
            }
            
            self.isCheckingModels = false
        }
    }
    
    func markModelAsDownloaded(_ modelName: String) {
        downloadedModels.insert(modelName)
        setLoadingState(for: modelName, state: .downloaded)
        
        // If this is the first downloaded model and no model is selected, select it
        if selectedModel == nil {
            selectedModel = modelName
        }
        
        // Also mark in persistent storage
        if let model = ModelData.availableModels.first(where: { $0.name == modelName }),
           let wkName = whisperKitModelName(for: model) {
            WhisperModelManager.shared.markModelAsDownloaded(wkName)
        }
    }
    
    func getModelPath(for whisperKitModelName: String) -> URL {
        return AppPaths.whisperKitModelPath(for: whisperKitModelName)
    }
    
    func getLoadingState(for modelName: String) -> ModelLoadingState {
        // First check if this model is actually loaded in memory
        if selectedModel == modelName && loadedWhisperKit != nil {
            return .loaded
        }

        // Check for in-progress states (downloading, loading, validating)
        if let state = modelLoadingStates[modelName] {
            switch state {
            case .downloading, .loading, .validating:
                return state
            case .loaded:
                // Only return loaded if WhisperKit is actually loaded (checked above)
                return .downloaded
            case .downloaded, .notDownloaded:
                break
            }
        }

        // Determine state based on download status
        if downloadedModels.contains(modelName) {
            return .downloaded
        }

        return .notDownloaded
    }
    
    func setLoadingState(for modelName: String, state: ModelLoadingState) {
        modelLoadingStates[modelName] = state
    }
    
    func loadModel(_ modelName: String) async -> WhisperKit? {
        // Cancel any existing loading task
        currentLoadingTask?.cancel()
        
        // Clear loading states for all models that were loading
        await MainActor.run {
            for model in ModelData.availableModels {
                if modelLoadingStates[model.name] == .loading {
                    setLoadingState(for: model.name, state: .downloaded)
                }
            }
        }
        
        // Create new loading task
        let task = Task { () -> WhisperKit? in
            guard let modelInfo = ModelData.availableModels.first(where: { $0.name == modelName }) else {
                print("Model info not found for: \(modelName)")
                return nil
            }
            
            guard let whisperKitModelName = whisperKitModelName(for: modelInfo) else {
                print("Model \(modelName) has no WhisperKit model name")
                return nil
            }
            let modelPath = getModelPath(for: whisperKitModelName)

            guard WhisperModelManager.shared.isModelDownloaded(whisperKitModelName) else {
                print("Model \(modelName) is not downloaded")
                return nil
            }
            
            // Check if cancelled before starting
            if Task.isCancelled {
                print("Model loading cancelled for: \(modelName)")
                return nil
            }
            
            // Update state to loading
            await MainActor.run {
                setLoadingState(for: modelName, state: .loading)
            }
            
            do {
                print("Loading WhisperKit with model: \(modelName)")
                let whisperKit = try await WhisperKit(
                    modelFolder: modelPath.path,
                    verbose: false,
                    logLevel: .error
                )
                
                // Check if cancelled after loading
                if Task.isCancelled {
                    print("Model loading cancelled after load for: \(modelName)")
                    await MainActor.run {
                        setLoadingState(for: modelName, state: .downloaded)
                    }
                    return nil
                }
                
                // Update state to loaded
                await MainActor.run {
                    self.loadedWhisperKit = whisperKit
                    setLoadingState(for: modelName, state: .loaded)
                    // Clear loading states for other models
                    for model in ModelData.availableModels where model.name != modelName {
                        if modelLoadingStates[model.name] == .loaded || modelLoadingStates[model.name] == .loading {
                            setLoadingState(for: model.name, state: .downloaded)
                        }
                    }
                }
                
                print("WhisperKit loaded successfully")
                return whisperKit
            } catch {
                // Check if error is due to cancellation
                if Task.isCancelled {
                    print("Model loading cancelled: \(modelName)")
                } else {
                    print("Failed to load WhisperKit: \(error)")
                }
                
                // Revert state to downloaded
                await MainActor.run {
                    setLoadingState(for: modelName, state: .downloaded)
                }
                
                return nil
            }
        }
        
        currentLoadingTask = task
        return await task.value
    }

    // MARK: - Parakeet Model Loading

    func loadParakeetModel() async {
        currentParakeetLoadingTask?.cancel()

        let version = parakeetVersion
        let modelPath = AppPaths.parakeetModelPath(for: version.coreMLDirectoryName)
        let isAlreadyDownloaded = modelDirectoryHasFiles(modelPath)

        parakeetLoadingState = isAlreadyDownloaded ? .loading : .downloading

        let task = Task { () -> Void in
            do {
                let transcriber = ParakeetTranscriber()
                try await transcriber.loadModel(version: version)

                guard !Task.isCancelled else {
                    print("Parakeet model loading cancelled after load")
                    await MainActor.run {
                        if self.parakeetVersion == version {
                            parakeetLoadingState = modelDirectoryHasFiles(modelPath) ? .downloaded : .notDownloaded
                        }
                    }
                    return
                }

                await MainActor.run {
                    guard self.parakeetVersion == version else { return }
                    self.loadedParakeetTranscriber = transcriber
                    self.parakeetLoadingState = .loaded
                }

                print("Parakeet model loaded successfully: \(version.displayName)")

            } catch is CancellationError {
                print("Parakeet model loading cancelled")
                await MainActor.run {
                    if self.parakeetVersion == version {
                        parakeetLoadingState = modelDirectoryHasFiles(modelPath) ? .downloaded : .notDownloaded
                    }
                }
            } catch {
                print("Failed to load Parakeet model: \(error)")
                await MainActor.run {
                    if self.parakeetVersion == version {
                        parakeetLoadingState = modelDirectoryHasFiles(modelPath) ? .downloaded : .notDownloaded
                        loadedParakeetTranscriber = nil
                    }
                }
            }
        }

        currentParakeetLoadingTask = task
        await task.value
    }

    // MARK: - Qwen3 Model Loading

    func loadQwen3Model() async {
        guard #available(macOS 15, *) else {
            print("Qwen3 requires macOS 15+")
            return
        }

        currentQwen3LoadingTask?.cancel()

        let variant = qwen3Variant
        let modelPath = AppPaths.qwen3ModelPath(for: variant.coreMLDirectoryName)
        qwen3LoadingState = modelDirectoryHasFiles(modelPath) ? .loading : .downloading

        let task = Task { () -> Void in
            do {
                let transcriber = Qwen3Transcriber()
                try await transcriber.loadModel(variant: variant)

                guard !Task.isCancelled else {
                    await MainActor.run { qwen3LoadingState = .notDownloaded }
                    return
                }

                await MainActor.run {
                    self.loadedQwen3Transcriber = transcriber
                    self.qwen3LoadingState = .loaded
                }
            } catch is CancellationError {
                await MainActor.run { qwen3LoadingState = .notDownloaded }
            } catch {
                print("Failed to load Qwen3 model: \(error)")
                await MainActor.run {
                    qwen3LoadingState = .notDownloaded
                    loadedQwen3Transcriber = nil
                }
            }
        }

        currentQwen3LoadingTask = task
        await task.value
    }

    func unloadQwen3Model() {
        if #available(macOS 15, *) {
            (loadedQwen3Transcriber as? Qwen3Transcriber)?.unloadModel()
        }
        loadedQwen3Transcriber = nil

        let modelPath = AppPaths.qwen3ModelPath(for: qwen3Variant.coreMLDirectoryName)
        qwen3LoadingState = modelDirectoryHasFiles(modelPath) ? .downloaded : .notDownloaded
        print("Qwen3 model unloaded")
    }

    /// Unload Parakeet model to free memory
    func unloadParakeetModel() {
        loadedParakeetTranscriber?.unloadModel()
        loadedParakeetTranscriber = nil

        // Check if model files exist on disk before setting state
        let modelPath = AppPaths.parakeetModelPath(for: parakeetVersion.coreMLDirectoryName)

        if modelDirectoryHasFiles(modelPath) {
            parakeetLoadingState = .downloaded
        } else {
            parakeetLoadingState = .notDownloaded
        }
        print("Parakeet model unloaded")
    }

    /// Unload WhisperKit model to free memory
    func unloadWhisperKitModel() {
        loadedWhisperKit = nil
        // Reset loading states to downloaded for all downloaded models
        for model in ModelData.availableModels where downloadedModels.contains(model.name) {
            setLoadingState(for: model.name, state: .downloaded)
        }
        print("WhisperKit model unloaded")
    }

    // MARK: - Unified Model API

    func whisperKitModelName(for model: SharedModels.ModelInfo) -> String? {
        return modelVariantOverrides[model.name] ?? model.whisperKitModelName
    }

    func setWhisperKitModelName(_ variant: String, for modelName: String) {
        modelVariantOverrides[modelName] = variant
        UserDefaults.standard.set(modelVariantOverrides, forKey: modelVariantOverridesKey)
    }

    func isSelected(_ modelName: String) -> Bool {
        guard let model = ModelData.availableModels.first(where: { $0.name == modelName }) else { return false }
        switch model.engine {
        case .whisperKit:
            return selectedEngine == .whisperKit && selectedModel == modelName
        case .parakeet:
            return selectedEngine == .parakeet && parakeetVersion == model.parakeetVersion
        case .qwen3:
            return selectedEngine == .qwen3 && qwen3Variant == model.qwen3Variant
        }
    }

    func isDownloaded(_ modelName: String) -> Bool {
        guard let model = ModelData.availableModels.first(where: { $0.name == modelName }) else { return false }
        switch model.engine {
        case .whisperKit:
            return downloadedModels.contains(modelName)
        case .parakeet:
            guard let version = model.parakeetVersion else { return false }
            return modelDirectoryHasFiles(AppPaths.parakeetModelPath(for: version.coreMLDirectoryName))
        case .qwen3:
            guard let variant = model.qwen3Variant else { return false }
            return modelDirectoryHasFiles(AppPaths.qwen3ModelPath(for: variant.coreMLDirectoryName))
        }
    }

    private func modelDirectoryHasFiles(_ url: URL) -> Bool {
        FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?.nextObject() != nil
    }

    func unifiedLoadingState(for modelName: String) -> UnifiedLoadingState {
        guard let model = ModelData.availableModels.first(where: { $0.name == modelName }) else {
            return .notDownloaded
        }
        switch model.engine {
        case .whisperKit:
            switch getLoadingState(for: modelName) {
            case .notDownloaded:           return .notDownloaded
            case .downloading(let p):      return .downloading(progress: p)
            case .validating:              return .validating
            case .downloaded:              return .downloaded
            case .loading:                 return .loading
            case .loaded:                  return .loaded
            }
        case .parakeet:
            guard let version = model.parakeetVersion else { return .notDownloaded }
            let isCurrentVersion = selectedEngine == .parakeet && parakeetVersion == version
            if isCurrentVersion {
                switch parakeetLoadingState {
                case .notDownloaded: return isDownloaded(modelName) ? .downloaded : .notDownloaded
                case .downloading:   return .downloading(progress: -1)
                case .downloaded:    return .downloaded
                case .loading:       return .loading
                case .loaded:        return .loaded
                }
            }
            return isDownloaded(modelName) ? .downloaded : .notDownloaded
        case .qwen3:
            guard let variant = model.qwen3Variant else { return .notDownloaded }
            let isCurrentVariant = selectedEngine == .qwen3 && qwen3Variant == variant
            if isCurrentVariant {
                switch qwen3LoadingState {
                case .notDownloaded: return isDownloaded(modelName) ? .downloaded : .notDownloaded
                case .downloading:   return .downloading(progress: -1)
                case .downloaded:    return .downloaded
                case .loading:       return .loading
                case .loaded:        return .loaded
                }
            }
            return isDownloaded(modelName) ? .downloaded : .notDownloaded
        }
    }

    @MainActor
    func selectModel(_ modelName: String) async {
        guard let model = ModelData.availableModels.first(where: { $0.name == modelName }) else { return }
        switch model.engine {
        case .whisperKit:
            selectedEngine = .whisperKit
            selectedModel = modelName
            if unifiedLoadingState(for: modelName) == .downloaded {
                _ = await loadModel(modelName)
            }
        case .parakeet:
            guard let version = model.parakeetVersion else { return }
            selectedEngine = .parakeet
            parakeetVersion = version
            if loadedParakeetTranscriber?.loadedVersion != version {
                await loadParakeetModel()
            }
        case .qwen3:
            guard let variant = model.qwen3Variant else { return }
            selectedEngine = .qwen3
            qwen3Variant = variant
            if qwen3LoadingState != .loaded {
                await loadQwen3Model()
            }
        }
    }

    // MARK: - Update checking

    func checkForUpdates() async {
        await MainActor.run { isCheckingUpdates = true }
        do {
            let remoteVariants = try await ModelUpdateChecker.shared.fetchRemoteVariants(forceRefresh: true)
            var updates: [String: String] = [:]
            for model in ModelData.availableModels where model.engine == .whisperKit {
                guard let currentVariant = whisperKitModelName(for: model),
                      let newerVariant = await ModelUpdateChecker.shared.newerVariant(
                        for: currentVariant,
                        in: remoteVariants
                      ) else { continue }
                updates[model.name] = newerVariant
            }
            await MainActor.run {
                availableUpdates = updates
                isCheckingUpdates = false
            }
        } catch {
            await MainActor.run { isCheckingUpdates = false }
            print("Update check failed: \(error)")
        }
    }
}

import Cocoa
import SwiftUI
import WhisperKit
import SharedModels
import AVFoundation
import ApplicationServices

struct SettingsView: View {
    @ObservedObject private var modelState = ModelStateManager.shared
    @State private var downloadingModels: Set<String> = []
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadErrors: [String: String] = [:]
    @State private var permissionRefresh = 0

    private static let recommendedModel = "large-v3-turbo"

    private var sortedModels: [SharedModels.ModelInfo] {
        ModelData.availableModels.sorted { $0.accuracyPercent > $1.accuracyPercent }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MOPDesign.Spacing.sectionGap) {
                if modelState.isCheckingModels {
                    checkingModels
                }

                setupStatusCard
                modelsSection
            }
            .padding(MOPDesign.Spacing.settings)
            .background(MOPDesign.Surface.content)
        }
        .navigationTitle("Models")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await modelState.checkForUpdates() } }) {
                    if modelState.isCheckingUpdates {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label("Check for model updates", systemImage: "arrow.clockwise.circle")
                    }
                }
                .help("Check HuggingFace for newer model versions")
                .disabled(modelState.isCheckingUpdates)
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(action: deleteAllModels) {
                    Label("Delete All Models", systemImage: "trash")
                }
                .help("Remove all downloaded models from disk")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if modelState.isCheckingModels {
                Task { await modelState.checkDownloadedModels() }
            }
            Task { await checkForIncompleteDownloads() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefresh += 1
        }
    }

    private var checkingModels: some View {
        HStack(spacing: MOPDesign.Spacing.output) {
            MOPStatusMarker(state: .pending)
            Text("Checking models")
                .font(MOPDesign.Typography.helper)
                .foregroundStyle(MOPDesign.Text.tertiary)
            Spacer()
        }
        .padding(.horizontal, MOPDesign.Spacing.panel)
    }

    private var modelsSection: some View {
        MOPCard {
            MOPSectionHeader(title: "Available models")

            if sortedModels.isEmpty {
                Text("No models are available.")
                    .font(MOPDesign.Typography.helper)
                    .foregroundStyle(MOPDesign.Text.tertiary)
                    .padding(.vertical, MOPDesign.Spacing.settingsRow)
            } else {
                LazyVStack(spacing: MOPDesign.Spacing.denseRow) {
                    ForEach(sortedModels, id: \.name) { model in
                        UnifiedModelCard(
                            model: model,
                            isSelected: modelState.isSelected(model.name),
                            loadingState: cardLoadingState(for: model),
                            updateAvailable: modelState.availableUpdates[model.name],
                            onSelect: {
                                Task { await modelState.selectModel(model.name) }
                            },
                            onDownload: {
                                downloadErrors.removeValue(forKey: model.name)
                                startDownload(model)
                            },
                            onUpdate: modelState.availableUpdates[model.name] != nil ? {
                                forceRedownload(model)
                            } : nil,
                            onDelete: { deleteModel(model) }
                        )

                        if let error = downloadErrors[model.name] {
                            HStack(spacing: MOPDesign.Spacing.denseRow) {
                                MOPStatusMarker(state: .failed, dense: true)
                                Text(error)
                                    .font(MOPDesign.Typography.helper)
                                    .foregroundStyle(MOPDesign.Semantic.failure)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, MOPDesign.Spacing.panel)
                        }

                        if model.name == Self.recommendedModel {
                            Text("Recommended for most people: a good balance of speed and accuracy.")
                                .font(MOPDesign.Typography.helper)
                                .foregroundStyle(MOPDesign.Text.tertiary)
                                .padding(.horizontal, MOPDesign.Spacing.panel)
                        }
                    }
                }
            }
        }
    }

    private var setupStatusCard: some View {
        MOPCard {
            MOPSectionHeader(title: "Setup Status")

            VStack(spacing: MOPDesign.Spacing.denseRow) {
                setupRow("Speech model", ready: selectedModelIsReady, detail: selectedModelIsReady ? "Ready" : "Download and select a model below")
                setupRow("Microphone", ready: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, detail: microphoneDetail, action: openMicrophoneSettings)
                setupRow("Text insertion", ready: AXIsProcessTrusted(), detail: AXIsProcessTrusted() ? "Ready" : "Allow MOP in Accessibility settings", action: openAccessibilitySettings)
            }
        }
    }

    private var selectedModelIsReady: Bool {
        _ = permissionRefresh
        switch modelState.selectedEngine {
        case .whisperKit:
            return modelState.selectedModel != nil && modelState.loadedWhisperKit != nil
        case .parakeet:
            return modelState.parakeetLoadingState == .loaded
        case .qwen3:
            return modelState.qwen3LoadingState == .loaded
        }
    }

    private var microphoneDetail: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "Ready"
        case .denied, .restricted: return "Allow MOP in Microphone settings"
        default: return "MOP will ask when you record"
        }
    }

    private func setupRow(_ title: String, ready: Bool, detail: String, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: MOPDesign.Spacing.output) {
            MOPStatusMarker(state: ready ? .completed : .needsInput)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MOPDesign.Typography.rowLabel)
                Text(detail)
                    .font(MOPDesign.Typography.helper)
                    .foregroundStyle(MOPDesign.Text.tertiary)
            }
            Spacer()
            if !ready, let action {
                Button("Open Settings", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, MOPDesign.Spacing.settingsRow)
    }

    private func openMicrophoneSettings() {
        openPrivacyPane("Privacy_Microphone")
    }

    private func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - State helpers

    private func cardLoadingState(for model: SharedModels.ModelInfo) -> UnifiedLoadingState {
        if model.engine == .whisperKit, let progress = downloadProgress[model.name] {
            let base = modelState.unifiedLoadingState(for: model.name)
            return base == .validating ? .validating : .downloading(progress: progress)
        }
        return modelState.unifiedLoadingState(for: model.name)
    }

    // MARK: - Download logic

    private func startDownload(_ model: SharedModels.ModelInfo) {
        switch model.engine {
        case .whisperKit:
            downloadWhisperModel(model)
        case .parakeet:
            guard let version = model.parakeetVersion else { return }
            modelState.selectedEngine = .parakeet
            modelState.parakeetVersion = version
            Task { await modelState.loadParakeetModel() }
        case .qwen3:
            guard let variant = model.qwen3Variant else { return }
            modelState.selectedEngine = .qwen3
            modelState.qwen3Variant = variant
            Task { await modelState.loadQwen3Model() }
        }
    }

    private func downloadWhisperModel(_ model: SharedModels.ModelInfo) {
        guard let whisperKitModelName = modelState.whisperKitModelName(for: model) else { return }
        guard !downloadingModels.contains(model.name) else { return }
        downloadingModels.insert(model.name)
        downloadProgress[model.name] = 0.0
        modelState.setLoadingState(for: model.name, state: .downloading(progress: 0.0))

        Task {
            do {
                let _ = try await WhisperModelDownloader.downloadModel(
                    modelName: whisperKitModelName,
                    progressCallback: { progress in
                        Task { @MainActor in
                            downloadProgress[model.name] = progress.fractionCompleted
                            modelState.setLoadingState(for: model.name, state: .downloading(progress: progress.fractionCompleted))
                            if progress.isFinished {
                                downloadProgress[model.name] = 1.0
                                modelState.setLoadingState(for: model.name, state: .validating)
                            }
                        }
                    }
                )
                await MainActor.run {
                    modelState.markModelAsDownloaded(model.name)
                }
                try await Task.sleep(for: .milliseconds(500))
                await MainActor.run {
                    downloadingModels.remove(model.name)
                    downloadProgress.removeValue(forKey: model.name)
                }
                let shouldAutoLoad = await MainActor.run { modelState.selectedModel == model.name }
                if shouldAutoLoad {
                    _ = await modelState.loadModel(model.name)
                }
            } catch {
                await MainActor.run {
                    downloadErrors[model.name] = error.localizedDescription
                    downloadingModels.remove(model.name)
                    downloadProgress.removeValue(forKey: model.name)
                    modelState.setLoadingState(for: model.name, state: .notDownloaded)
                }
            }
        }
    }

    private func forceRedownload(_ model: SharedModels.ModelInfo) {
        guard model.engine == .whisperKit,
              let currentVariant = modelState.whisperKitModelName(for: model) else { return }
        let nextVariant = modelState.availableUpdates[model.name] ?? currentVariant
        modelState.setWhisperKitModelName(nextVariant, for: model.name)
        try? FileManager.default.removeItem(at: AppPaths.whisperKitModelPath(for: currentVariant))
        WhisperModelManager.shared.removeDownloadMetadata(for: currentVariant)
        modelState.downloadedModels.remove(model.name)
        modelState.setLoadingState(for: model.name, state: .notDownloaded)
        modelState.availableUpdates.removeValue(forKey: model.name)
        downloadWhisperModel(model)
    }

    private func deleteModel(_ model: SharedModels.ModelInfo) {
        switch model.engine {
        case .whisperKit:
            guard let wkName = modelState.whisperKitModelName(for: model) else { return }
            if modelState.selectedEngine == .whisperKit && modelState.selectedModel == model.name {
                modelState.unloadWhisperKitModel()
                modelState.selectedModel = nil
            }
            try? FileManager.default.removeItem(at: AppPaths.whisperKitModelPath(for: wkName))
            WhisperModelManager.shared.removeDownloadMetadata(for: wkName)
            modelState.downloadedModels.remove(model.name)
            modelState.setLoadingState(for: model.name, state: .notDownloaded)
        case .parakeet:
            guard let version = model.parakeetVersion else { return }
            if modelState.selectedEngine == .parakeet && modelState.parakeetVersion == version {
                modelState.unloadParakeetModel()
            }
            try? FileManager.default.removeItem(at: AppPaths.parakeetModelPath(for: version.coreMLDirectoryName))
            if modelState.selectedEngine == .parakeet && modelState.parakeetVersion == version {
                modelState.parakeetLoadingState = .notDownloaded
            }
        case .qwen3:
            guard let variant = model.qwen3Variant else { return }
            if modelState.selectedEngine == .qwen3 && modelState.qwen3Variant == variant {
                modelState.unloadQwen3Model()
            }
            if #available(macOS 15, *) {
                Qwen3Transcriber.deleteCachedModel(variant: variant)
            }
            if modelState.selectedEngine == .qwen3 && modelState.qwen3Variant == variant {
                modelState.qwen3LoadingState = .notDownloaded
            }
        }
        downloadErrors.removeValue(forKey: model.name)
        downloadProgress.removeValue(forKey: model.name)
        downloadingModels.remove(model.name)
    }

    private func deleteAllModels() {
        for model in ModelData.availableModels {
            deleteModel(model)
        }
    }

    private func checkForIncompleteDownloads() async {
        let whisperModels = ModelData.availableModels.filter { $0.engine == .whisperKit }
        var partial: [SharedModels.ModelInfo] = []
        for model in whisperModels {
            guard let wkName = modelState.whisperKitModelName(for: model) else { continue }
            let path = AppPaths.whisperKitModelPath(for: wkName)
            if FileManager.default.fileExists(atPath: path.path),
               !WhisperModelManager.shared.isModelDownloaded(wkName) {
                partial.append(model)
            }
        }
        for model in partial {
            await MainActor.run { downloadWhisperModel(model) }
        }
    }
}

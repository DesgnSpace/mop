import Cocoa
import SwiftUI
import WhisperKit
import SharedModels

struct SettingsView: View {
    @ObservedObject private var modelState = ModelStateManager.shared
    @State private var downloadingModels: Set<String> = []
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadErrors: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(ModelTier.allCases, id: \.self) { tier in
                    let models = ModelData.availableModels.filter { $0.tier == tier }
                    if !models.isEmpty {
                        TierSection(tier: tier) {
                            ForEach(models, id: \.name) { model in
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
                                    onDelete: {
                                        deleteModel(model)
                                    }
                                )
                                if let error = downloadErrors[model.name] {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Models")
        .toolbar {
            ToolbarItem(placement: .status) {
                if modelState.isCheckingModels {
                    Label("Checking models...", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    currentModelStatusLabel
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await modelState.checkForUpdates() } }) {
                    if modelState.isCheckingUpdates {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label("Check for updates", systemImage: "arrow.clockwise.circle")
                    }
                }
                .help("Check HuggingFace for newer model versions")
                .disabled(modelState.isCheckingUpdates)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if modelState.isCheckingModels {
                Task { await modelState.checkDownloadedModels() }
            }
            Task { await checkForIncompleteDownloads() }
        }
    }

    // MARK: - Subviews

    private struct TierSection<Content: View>: View {
        let tier: ModelTier
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: tier.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                    Text(tier.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 4)
                content
            }
        }
    }

    @ViewBuilder
    private var currentModelStatusLabel: some View {
        switch modelState.selectedEngine {
        case .parakeet:
            switch modelState.parakeetLoadingState {
            case .loaded:
                Label("Current: \(modelState.parakeetVersion.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            case .loading, .downloading:
                Label("Loading Parakeet...", systemImage: "arrow.clockwise")
                    .font(.caption).foregroundStyle(.secondary)
            default:
                Label("Download a model to get started", systemImage: "arrow.down.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .whisperKit:
            let whisperModels = ModelData.availableModels.filter { $0.engine == .whisperKit }
            if let selected = modelState.selectedModel,
               let model = whisperModels.first(where: { $0.name == selected }) {
                Label("Current: \(model.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if modelState.downloadedModels.isEmpty {
                Label("Download a model to get started", systemImage: "arrow.down.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Select a downloaded model", systemImage: "cursorarrow.click")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - State helpers

    private func cardLoadingState(for model: SharedModels.ModelInfo) -> UnifiedLoadingState {
        switch model.engine {
        case .whisperKit:
            if let progress = downloadProgress[model.name] {
                return modelState.unifiedLoadingState(for: model.name) == .validating
                    ? .validating
                    : .downloading(progress: progress)
            }
            return modelState.unifiedLoadingState(for: model.name)
        case .parakeet:
            return modelState.unifiedLoadingState(for: model.name)
        }
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
        // Remove existing files + metadata so fresh download triggers
        let modelPath = AppPaths.whisperKitModelPath(for: currentVariant)
        try? FileManager.default.removeItem(at: modelPath)
        WhisperModelManager.shared.removeDownloadMetadata(for: currentVariant)
        modelState.downloadedModels.remove(model.name)
        modelState.setLoadingState(for: model.name, state: .notDownloaded)
        // Clear update badge
        modelState.availableUpdates.removeValue(forKey: model.name)
        // Start fresh download
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
        }
        downloadErrors.removeValue(forKey: model.name)
        downloadProgress.removeValue(forKey: model.name)
        downloadingModels.remove(model.name)
    }

    private func checkForIncompleteDownloads() async {
        let whisperModels = ModelData.availableModels.filter { $0.engine == .whisperKit }
        var partial: [SharedModels.ModelInfo] = []
        for model in whisperModels {
            guard let wkName = modelState.whisperKitModelName(for: model) else { continue }
            let path = AppPaths.whisperKitModelPath(for: wkName)
            if FileManager.default.fileExists(atPath: path.path) && !modelState.downloadedModels.contains(model.name) {
                partial.append(model)
            }
        }
        for model in partial {
            await MainActor.run { downloadWhisperModel(model) }
        }
    }
}

class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false

        let hostingController = NSHostingController(rootView: SettingsView())
        window.contentViewController = hostingController
        self.init(window: window)
    }

    func showWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

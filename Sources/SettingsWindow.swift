import Cocoa
import SwiftUI
import WhisperKit
import SharedModels

struct SettingsView: View {
    @ObservedObject private var modelState = ModelStateManager.shared
    @State private var downloadingModels: Set<String> = []
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadErrors: [String: String] = [:]

    private static let recommendedModel = "large-v3-turbo"

    private var sortedModels: [SharedModels.ModelInfo] {
        ModelData.availableModels.sorted { $0.accuracyPercent > $1.accuracyPercent }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Spacer()
                if modelState.isCheckingModels {
                    Label("Scanning...", systemImage: "arrow.clockwise")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
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
                            Text(error)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.red.opacity(0.8))
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if model.name == Self.recommendedModel {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8))
                                Text("recommended · best balance of speed and accuracy")
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            .foregroundStyle(Color.accentColor.opacity(0.5))
                            .padding(.leading, 30)
                            .padding(.bottom, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if model.name != sortedModels.last?.name {
                            Divider()
                                .padding(.leading, 30)
                                .opacity(0.4)
                        }
                    }

                    Spacer(minLength: 20)
                }
            }
        }
        .navigationTitle("Models")
        .toolbar {
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

private final class SettingsNSWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "w", "q":
                orderOut(nil)
                return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = SettingsNSWindow(
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

import Cocoa
import SwiftUI
import WhisperKit
import SharedModels

struct SettingsView: View {
    @ObservedObject private var modelState = ModelStateManager.shared
    @State private var downloadingModels: Set<String> = []
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadErrors: [String: String] = [:]

    let whisperModels = ModelData.availableModels


    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader(title: "Parakeet", subtitle: "by FluidAudio", icon: "antenna.radiowaves.left.and.right")
                    .padding(.horizontal, 4)

                ForEach(ParakeetVersion.allCases, id: \.self) { version in
                    ParakeetModelCard(
                        version: version,
                        isSelected: modelState.selectedEngine == .parakeet && modelState.parakeetVersion == version,
                        loadingState: parakeetLoadingState(for: version),
                        onSelect: {
                            modelState.selectedEngine = .parakeet
                            modelState.parakeetVersion = version
                            if modelState.parakeetLoadingState != .loaded {
                                Task { await modelState.loadParakeetModel() }
                            }
                        },
                        onDownload: {
                            modelState.selectedEngine = .parakeet
                            modelState.parakeetVersion = version
                            Task { await modelState.loadParakeetModel() }
                        }
                    )
                }

                SectionHeader(title: "WhisperKit", subtitle: "by Argmax", icon: "waveform")
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                ForEach(whisperModels, id: \.name) { model in
                    ModelCard(
                        model: model,
                        isSelected: modelState.selectedEngine == .whisperKit && modelState.selectedModel == model.name,
                        isDownloaded: modelState.downloadedModels.contains(model.name),
                        isDownloading: downloadingModels.contains(model.name),
                        downloadProgress: downloadProgress[model.name] ?? 0,
                        downloadError: downloadErrors[model.name],
                        loadingState: modelState.getLoadingState(for: model.name),
                        onSelect: {
                            if modelState.downloadedModels.contains(model.name) {
                                modelState.selectedEngine = .whisperKit
                                modelState.selectedModel = model.name
                            }
                        },
                        onDownload: {
                            downloadModel(model.name)
                            downloadErrors.removeValue(forKey: model.name)
                        }
                    )
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // If models haven't been checked yet (e.g., settings opened very quickly after app start)
            if modelState.isCheckingModels {
                Task {
                    await modelState.checkDownloadedModels()
                }
            }

            // Check for incomplete downloads that need auto-resume
            Task {
                await checkForIncompleteDownloads()
            }
        }
    }

    private struct SectionHeader: View {
        let title: String
        let subtitle: String
        let icon: String

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.1))
                    )

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .loading, .downloading:
                Label("Loading Parakeet...", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                Label("Download a model to get started", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .whisperKit:
            if let selected = modelState.selectedModel,
               let model = whisperModels.first(where: { $0.name == selected }) {
                Label("Current: \(model.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if modelState.downloadedModels.isEmpty {
                Label("Download a model to get started", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Select a downloaded model", systemImage: "cursorarrow.click")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Get loading state for a Parakeet version, checking filesystem for non-selected versions
    private func parakeetLoadingState(for version: ParakeetVersion) -> ParakeetLoadingState {
        // For the selected version when Parakeet is active, use the actual state
        if modelState.selectedEngine == .parakeet && modelState.parakeetVersion == version {
            return modelState.parakeetLoadingState
        }

        // For other versions or when WhisperKit is active, check if downloaded on disk
        let modelName = version == .v2 ? "parakeet-tdt-0.6b-v2-coreml" : "parakeet-tdt-0.6b-v3-coreml"
        let modelPath = AppPaths.parakeetModelPath(for: modelName)

        if FileManager.default.fileExists(atPath: modelPath.path) {
            return .downloaded
        }
        return .notDownloaded
    }

    func checkForIncompleteDownloads() async {
        // Only check for incomplete downloads that need auto-resume
        var partiallyDownloadedModels: [String] = []
        
        for model in whisperModels {
            let modelPath = getModelPath(for: model.whisperKitModelName)
            
            // Check if directory exists but model is not in downloaded set
            if FileManager.default.fileExists(atPath: modelPath.path) && 
               !modelState.downloadedModels.contains(model.name) {
                // This model exists on disk but isn't marked as complete
                print("Model \(model.name) exists but is incomplete, will auto-resume download...")
                partiallyDownloadedModels.append(model.name)
            }
        }
        
        // Auto-resume downloads for partially downloaded models
        for modelName in partiallyDownloadedModels {
            await MainActor.run {
                // Just call downloadModel - it handles all the state setup
                downloadModel(modelName)
            }
        }
    }
    
    func getModelPath(for whisperKitModelName: String) -> URL {
        return AppPaths.whisperKitModelPath(for: whisperKitModelName)
    }
    
    func downloadModel(_ modelName: String) {
        guard let model = whisperModels.first(where: { $0.name == modelName }) else {
            print("Model not found: \(modelName)")
            return
        }

        // Prevent concurrent downloads of the same model
        guard !downloadingModels.contains(modelName) else {
            print("Model \(modelName) is already downloading, skipping...")
            return
        }

        print("Starting download of \(model.displayName)...")
        downloadingModels.insert(modelName)
        downloadProgress[modelName] = 0.0
        modelState.setLoadingState(for: modelName, state: .downloading(progress: 0.0))
        
        Task {
            do {
                // Perform the actual download with real progress tracking
                let _ = try await WhisperModelDownloader.downloadModel(
                    from: model,
                    progressCallback: { progress in
                        Task { @MainActor in
                            // Update progress based on actual download progress
                            downloadProgress[modelName] = progress.fractionCompleted
                            modelState.setLoadingState(for: modelName, state: .downloading(progress: progress.fractionCompleted))
                            
                            // If download is complete, show validating state
                            if progress.isFinished {
                                downloadProgress[modelName] = 1.0
                                modelState.setLoadingState(for: modelName, state: .validating)
                            }
                        }
                    }
                )
                
                // When download finishes, mark it as complete in our manager
                await MainActor.run {
                    modelState.markModelAsDownloaded(modelName)
                }

                // Clean up after a short delay to show completion
                try await Task.sleep(for: .milliseconds(500))
                await MainActor.run {
                    downloadingModels.remove(modelName)
                    downloadProgress.removeValue(forKey: modelName)
                }

                // Auto-load the model after download if it's the selected one
                let shouldAutoLoad = await MainActor.run {
                    modelState.selectedModel == modelName
                }
                if shouldAutoLoad {
                    _ = await modelState.loadModel(modelName)
                }
                
                print("Successfully downloaded \(model.displayName)")
                
            } catch {
                print("Error downloading model: \(error)")
                await MainActor.run {
                    downloadErrors[modelName] = error.localizedDescription
                    downloadingModels.remove(modelName)
                    downloadProgress.removeValue(forKey: modelName)
                    modelState.setLoadingState(for: modelName, state: .notDownloaded)
                }
            }
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
        window.isReleasedWhenClosed = false  // Prevent window from being released when closed
        
        let hostingController = NSHostingController(rootView: SettingsView())
        window.contentViewController = hostingController
        
        self.init(window: window)
    }
    
    func showWindow() {
        // Ensure window operations happen on main thread with proper timing
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
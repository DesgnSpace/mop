import Cocoa
import SwiftUI
import WhisperKit
import SharedModels

@MainActor
struct SettingsView: View {
    @StateObject private var modelState = ModelStateManager.shared
    @State private var downloadingModels: Set<String> = []
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadErrors: [String: String] = [:]

    let whisperModels = ModelData.availableModels


    var body: some View {
        VStack(spacing: 0) {
            // Modern Header with icon and refined typography
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice Models")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Select a speech recognition engine")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                Color(nsColor: .controlBackgroundColor)
            )

            Divider()

            // All models in one list
            ScrollView {
                VStack(spacing: 16) {
                    // Gemini API Key section
                    GeminiAPIKeySection()
                        .padding(.horizontal, 4)

                    // Parakeet section header
                    SectionHeader(title: "Parakeet", subtitle: "by FluidAudio", icon: "antenna.radiowaves.left.and.right")
                        .padding(.horizontal, 4)

                    // Parakeet models
                    ForEach(ParakeetVersion.allCases, id: \.self) { version in
                        ParakeetModelCard(
                            version: version,
                            isSelected: modelState.selectedEngine == .parakeet && modelState.parakeetVersion == version,
                            loadingState: parakeetLoadingState(for: version),
                            onSelect: {
                                modelState.selectedEngine = .parakeet
                                modelState.parakeetVersion = version
                                // Load the model if not already loaded
                                if modelState.parakeetLoadingState != .loaded {
                                    Task {
                                        await modelState.loadParakeetModel()
                                    }
                                }
                            },
                            onDownload: {
                                modelState.selectedEngine = .parakeet
                                modelState.parakeetVersion = version
                                Task {
                                    await modelState.loadParakeetModel()
                                }
                            }
                        )
                    }

                    // WhisperKit section header
                    SectionHeader(title: "WhisperKit", subtitle: "by Argmax", icon: "waveform")
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                    // WhisperKit models
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

            Divider()

            // Modern Footer with refined status
            HStack {
                if modelState.isCheckingModels {
                    Label("Checking models...", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    currentModelStatusLabel
                }

                Spacer()

                Button("Done") {
                    NSApplication.shared.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Color(nsColor: .controlBackgroundColor)
            )
        }
        .frame(width: 600, height: 600)
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
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.1))
                    )

                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)

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
                    .foregroundColor(.secondary)
            case .loading, .downloading:
                Label("Loading Parakeet...", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
            default:
                Label("Download a model to get started", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .whisperKit:
            if let selected = modelState.selectedModel,
               let model = whisperModels.first(where: { $0.name == selected }) {
                Label("Current: \(model.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if modelState.downloadedModels.isEmpty {
                Label("Download a model to get started", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Label("Select a downloaded model", systemImage: "cursorarrow.click")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    
                    // Clean up after a short delay to show completion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        downloadingModels.remove(modelName)
                        downloadProgress.removeValue(forKey: modelName)
                    }
                    
                    // Auto-load the model after download if it's the selected one
                    if modelState.selectedModel == modelName {
                        Task {
                            _ = await modelState.loadModel(modelName)
                        }
                    }
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

@MainActor
struct GeminiAPIKeySection: View {
    @State private var apiKey: String = GeminiConfig.apiKey
    @State private var isKeyVisible: Bool = false
    @State private var showSaved: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: "key.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Gemini API Key")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(GeminiConfig.isConfigured ? "Connected to Gemini" : "Required for cloud features")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(GeminiConfig.isConfigured ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(GeminiConfig.isConfigured ? "Ready" : "Not Set")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(GeminiConfig.isConfigured ? .green : .secondary)
                }
            }

            HStack(spacing: 8) {
                Group {
                    if isKeyVisible {
                        TextField("Enter your Gemini API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Enter your Gemini API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Button(action: { isKeyVisible.toggle() }) {
                    Image(systemName: isKeyVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isKeyVisible ? "Hide API key" : "Show API key")

                Button(action: saveKey) {
                    if showSaved {
                        Label("Saved", systemImage: "checkmark")
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !GeminiConfig.isConfigured {
                Button(action: openGeminiDocs) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Get a free API key from ai.google.dev")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private func saveKey() {
        GeminiConfig.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        showSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSaved = false
        }
    }

    private func openGeminiDocs() {
        if let url = URL(string: "https://ai.google.dev") {
            NSWorkspace.shared.open(url)
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
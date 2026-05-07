import SwiftUI
import SharedModels

struct CleanupView: View {
    @State private var useCleanup = TranscriptionPreferences.useTextCleanup
    @State private var selectedDriver = CleanupConfig.selectedDriver
    @State private var cleanupPrompt = TranscriptionPreferences.cleanupPrompt
    @State private var cleanupTimeout = TranscriptionPreferences.cleanupTimeout

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                enableSection
                driverSection
                promptSection
                driverConfigSection
            }
            .padding(20)
        }
        .navigationTitle("Cleanup")
    }

    private var enableSection: some View {
        card {
            sectionLabel(title: "Text Cleanup", icon: "wand.and.sparkles", color: .purple)

            toggleRow(
                title: "Enable cleanup",
                description: "Run transcribed text through an LLM to fix grammar and punctuation",
                isOn: $useCleanup,
                color: .purple
            ) {
                TranscriptionPreferences.useTextCleanup = useCleanup
            }
        }
    }

    private var driverSection: some View {
        card {
            sectionLabel(title: "Driver", icon: "cpu", color: .orange)

            Picker("", selection: $selectedDriver) {
                ForEach(CleanupDriver.allCases, id: \.self) { driver in
                    Text(driver.displayName).tag(driver)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedDriver) { _, newValue in
                CleanupConfig.selectedDriver = newValue
            }
        }
        .disabled(!useCleanup)
        .opacity(useCleanup ? 1 : 0.5)
    }

    private var promptSection: some View {
        card {
            sectionLabel(title: "System Prompt", icon: "text.alignleft", color: .blue)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Cleanup prompt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        cleanupPrompt = TranscriptionPreferences.defaultCleanupPrompt
                        TranscriptionPreferences.cleanupPrompt = cleanupPrompt
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }

                TextEditor(text: $cleanupPrompt)
                    .font(.body)
                    .frame(minHeight: 72, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .onChange(of: cleanupPrompt) { _, newValue in
                        TranscriptionPreferences.cleanupPrompt = newValue
                    }
            }
        }
        .disabled(!useCleanup)
        .opacity(useCleanup ? 1 : 0.5)
    }

    @ViewBuilder
    private var driverConfigSection: some View {
        if useCleanup {
            switch selectedDriver {
            case .gemini:
                GeminiCleanupSection(cleanupTimeout: $cleanupTimeout)
            case .ollama:
                LocalLLMSection(
                    title: "Ollama",
                    icon: "server.rack",
                    color: .green,
                    endpointKey: \.ollamaEndpoint,
                    modelKey: \.ollamaModel,
                    cleanupTimeout: $cleanupTimeout
                )
            case .lmStudio:
                LocalLLMSection(
                    title: "LM Studio",
                    icon: "laptopcomputer",
                    color: .indigo,
                    endpointKey: \.lmStudioEndpoint,
                    modelKey: \.lmStudioModel,
                    cleanupTimeout: $cleanupTimeout
                )
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func sectionLabel(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(title).font(.headline)
        }
    }

    private func toggleRow(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        color: Color,
        disabled: Bool = false,
        onChange: @escaping () -> Void
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(disabled ? .secondary : .primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(color)
        .disabled(disabled)
        .onChange(of: isOn.wrappedValue) { _, _ in onChange() }
        .padding(.leading, 8)
    }
}

// MARK: - Gemini sub-section

@MainActor
private struct GeminiCleanupSection: View {
    @Binding var cleanupTimeout: Int
    @State private var apiKey: String = GeminiConfig.apiKey
    @State private var isKeyVisible: Bool = false
    @State private var showSaved: Bool = false
    @State private var selectedModel: String = GeminiConfig.selectedModel
    @State private var modelInfos: [GeminiConfig.ModelInfo] = GeminiConfig.effectiveModels
    @State private var isFetchingModels: Bool = false
    @ObservedObject private var callLog = GeminiCallLog.shared

    var body: some View {
        VStack(spacing: 16) {
            card {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "key.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gemini API Key").font(.headline)
                        Text(GeminiConfig.isConfigured ? "Connected" : "Required for Gemini cleanup")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(GeminiConfig.isConfigured ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(GeminiConfig.isConfigured ? "Ready" : "Not Set")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(GeminiConfig.isConfigured ? .green : .secondary)
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
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: saveKey) {
                        if showSaved { Label("Saved", systemImage: "checkmark") } else { Text("Save") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack(spacing: 8) {
                    Text("Model:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $selectedModel) {
                        ForEach(modelInfos) { info in
                            Text(info.displayName).tag(info.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: selectedModel) { _, newValue in
                        guard newValue != GeminiConfig.selectedModel else { return }
                        GeminiConfig.selectedModel = newValue
                    }
                    if isFetchingModels { ProgressView().controlSize(.small) }
                }
                .task { await refreshModels() }

                if !GeminiConfig.isConfigured {
                    Button(action: { NSWorkspace.shared.open(URL(string: "https://ai.google.dev")!) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Get a free API key from ai.google.dev")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }

                Stepper(value: $cleanupTimeout, in: 5...60, step: 1) {
                    Text("Request timeout: \(cleanupTimeout)s")
                        .font(.subheadline)
                }
                .onChange(of: cleanupTimeout) { _, newValue in
                    TranscriptionPreferences.cleanupTimeout = newValue
                }
            }

            if !callLog.entries.isEmpty {
                activityLog
            }
        }
    }

    private var activityLog: some View {
        card {
            HStack {
                Text("Recent Activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { GeminiCallLog.shared.clear() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 3) {
                ForEach(callLog.entries as [GeminiCallLog.Entry], id: \.id) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(entry.success ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(relativeTime(entry.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(entry.success ? .primary : Color.red)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    private func refreshModels() async {
        guard GeminiConfig.isCacheStale else { return }
        isFetchingModels = true
        if let fetched = await GeminiConfig.fetchModels() {
            GeminiConfig.cachedModels = fetched
            modelInfos = fetched
        }
        isFetchingModels = false
    }

    private func saveKey() {
        GeminiConfig.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        showSaved = true
        Task {
            try await Task.sleep(for: .seconds(1.5))
            showSaved = false
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Local LLM sub-section (Ollama / LM Studio)

private struct LocalLLMSection: View {
    let title: String
    let icon: String
    let color: Color
    let endpointKey: WritableKeyPath<CleanupConfigValues, String>
    let modelKey: WritableKeyPath<CleanupConfigValues, String>
    @Binding var cleanupTimeout: Int

    @State private var endpoint: String = ""
    @State private var model: String = ""
    @State private var availableModels: [String] = []
    @State private var isFetching = false
    @State private var fetchFailed = false

    var body: some View {
        VStack(spacing: 16) {
            card {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(color)
                    }
                    Text(title).font(.headline)
                    Spacer()
                    statusBadge
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Endpoint")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        TextField("http://localhost:…", text: $endpoint)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: endpoint) { _, newValue in
                                saveEndpoint(newValue)
                            }
                        Button(action: { Task { await fetchModels() } }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isFetching)
                        if isFetching { ProgressView().controlSize(.small) }
                    }

                    HStack {
                        Text("Model")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        if !availableModels.isEmpty && !fetchFailed {
                            Picker("", selection: $model) {
                                ForEach(availableModels, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .onChange(of: model) { _, newValue in saveModel(newValue) }
                        } else {
                            TextField("model name", text: $model)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: model) { _, newValue in saveModel(newValue) }
                        }
                    }
                }

                Stepper(value: $cleanupTimeout, in: 5...60, step: 1) {
                    Text("Request timeout: \(cleanupTimeout)s")
                        .font(.subheadline)
                }
                .onChange(of: cleanupTimeout) { _, newValue in
                    TranscriptionPreferences.cleanupTimeout = newValue
                }

                if fetchFailed {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("\(title) not reachable — enter model name manually")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            loadState()
            Task { await fetchModels() }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(availableModels.isEmpty ? Color.secondary : Color.green)
                .frame(width: 8, height: 8)
            Text(availableModels.isEmpty ? "Offline" : "Connected")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(availableModels.isEmpty ? Color.secondary : Color.green)
        }
    }

    private func loadState() {
        var vals = CleanupConfigValues()
        endpoint = vals[keyPath: endpointKey]
        model = vals[keyPath: modelKey]
    }

    private func saveEndpoint(_ value: String) {
        var vals = CleanupConfigValues()
        vals[keyPath: endpointKey] = value
    }

    private func saveModel(_ value: String) {
        var vals = CleanupConfigValues()
        vals[keyPath: modelKey] = value
    }

    private func fetchModels() async {
        guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isFetching = true
        fetchFailed = false
        if let models = await CleanupConfig.fetchModels(from: endpoint) {
            availableModels = models
            if !models.isEmpty && (model.isEmpty || !models.contains(model)) {
                model = models[0]
                saveModel(model)
            }
            fetchFailed = false
        } else {
            fetchFailed = true
            availableModels = []
        }
        isFetching = false
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - KeyPath bridge for CleanupConfig

private struct CleanupConfigValues {
    var ollamaEndpoint: String {
        get { CleanupConfig.ollamaEndpoint }
        set { CleanupConfig.ollamaEndpoint = newValue }
    }
    var ollamaModel: String {
        get { CleanupConfig.ollamaModel }
        set { CleanupConfig.ollamaModel = newValue }
    }
    var lmStudioEndpoint: String {
        get { CleanupConfig.lmStudioEndpoint }
        set { CleanupConfig.lmStudioEndpoint = newValue }
    }
    var lmStudioModel: String {
        get { CleanupConfig.lmStudioModel }
        set { CleanupConfig.lmStudioModel = newValue }
    }
}

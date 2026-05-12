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
                CleanupProfilesSection()
                driverSection
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
            case .openai:
                APIKeyCleanupSection(
                    title: "OpenAI",
                    icon: "sparkles",
                    color: .cyan,
                    apiKeyGet: { CleanupConfig.openAIAPIKey },
                    apiKeySet: { CleanupConfig.openAIAPIKey = $0 },
                    modelGet: { CleanupConfig.openAIModel },
                    modelSet: { CleanupConfig.openAIModel = $0 },
                    defaultModel: "gpt-4o-mini",
                    modelOptions: ["gpt-4o-mini", "gpt-4o", "gpt-4-turbo"],
                    cleanupTimeout: $cleanupTimeout
                )
            case .anthropic:
                APIKeyCleanupSection(
                    title: "Anthropic",
                    icon: "brain",
                    color: .orange,
                    apiKeyGet: { CleanupConfig.anthropicAPIKey },
                    apiKeySet: { CleanupConfig.anthropicAPIKey = $0 },
                    modelGet: { CleanupConfig.anthropicModel },
                    modelSet: { CleanupConfig.anthropicModel = $0 },
                    defaultModel: "claude-haiku-4-5-20251001",
                    modelOptions: ["claude-haiku-4-5-20251001", "claude-sonnet-4-6", "claude-opus-4-7"],
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

// MARK: - Cleanup Profiles Section

@MainActor
private struct CleanupProfilesSection: View {
    @ObservedObject private var store = CleanupProfileStore.shared
    @State private var selectedID: UUID?
    @State private var isAddingNew = false
    @State private var newProfileName = ""

    private var selectedProfile: CleanupProfile? {
        guard let id = selectedID else { return nil }
        return store.profiles.first { $0.id == id }
    }

    var body: some View {
        outerCard {
            sectionHeader

            Divider()

            if store.profiles.isEmpty {
                Text("No profiles. Tap + to add one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                profileList
            }

            if isAddingNew {
                newProfileRow
            }

            if let profile = selectedProfile {
                Divider()
                ProfileEditor(profile: profile) { updated in
                    store.update(updated)
                }
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.purple)
            }
            Text("Cleanup Profiles").font(.headline)
            Spacer()
            Button(action: { isAddingNew = true }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
        }
    }

    private var profileList: some View {
        VStack(spacing: 2) {
            ForEach(store.profiles) { profile in
                profileRow(profile)
            }
        }
    }

    private func profileRow(_ profile: CleanupProfile) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                selectedID = selectedID == profile.id ? nil : profile.id
            }) {
                HStack(spacing: 8) {
                    if profile.isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(profile.name)
                        .font(.subheadline)
                        .foregroundStyle(selectedID == profile.id ? Color.accentColor : .primary)
                    Spacer()
                    if store.manualOverrideID == profile.id {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            .foregroundStyle(Color.accentColor)
                    }
                    Image(systemName: selectedID == profile.id ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                if selectedID == profile.id { selectedID = nil }
                store.delete(id: profile.id)
            }) {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(store.profiles.count > 1 ? 1 : 0.3)
            .disabled(store.profiles.count <= 1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectedID == profile.id ? Color.accentColor.opacity(0.06) : Color.clear)
        )
    }

    private var newProfileRow: some View {
        HStack(spacing: 8) {
            TextField("Profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
                .onSubmit { commitNewProfile() }
            Button("Add") { commitNewProfile() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel") {
                isAddingNew = false
                newProfileName = ""
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func commitNewProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let profile = CleanupProfile(
            name: name,
            prompt: TranscriptionPreferences.defaultCleanupPrompt
        )
        store.add(profile)
        selectedID = profile.id
        isAddingNew = false
        newProfileName = ""
    }

    private func outerCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

// MARK: - Profile editor (inline)

@MainActor
private struct ProfileEditor: View {
    @State private var profile: CleanupProfile
    let onSave: (CleanupProfile) -> Void

    @ObservedObject private var store = CleanupProfileStore.shared
    @State private var newBundleID = ""

    init(profile: CleanupProfile, onSave: @escaping (CleanupProfile) -> Void) {
        _profile = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name
            HStack {
                Text("Name").font(.subheadline).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                TextField("Profile name", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: profile.name) { _, _ in onSave(profile) }
            }

            // Default toggle
            Toggle(isOn: $profile.isDefault) {
                Text("Default profile (used when no app rule matches)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .tint(.purple)
            .onChange(of: profile.isDefault) { _, val in
                if val { store.setDefault(id: profile.id) }
                else { onSave(profile) }
            }

            // Driver override
            HStack {
                Text("Driver").font(.subheadline).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Picker("", selection: $profile.driverOverride) {
                    Text("Global default").tag(Optional<CleanupDriver>.none)
                    ForEach(CleanupDriver.allCases, id: \.self) { d in
                        Text(d.displayName).tag(Optional(d))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: profile.driverOverride) { _, _ in onSave(profile) }
            }

            // Prompt
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $profile.prompt)
                    .font(.system(.body))
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .onChange(of: profile.prompt) { _, _ in onSave(profile) }
            }

            // App rules
            VStack(alignment: .leading, spacing: 6) {
                Text("Auto-activate for apps").font(.subheadline).foregroundStyle(.secondary)

                if profile.appBundleIDs.isEmpty {
                    Text("No app rules — add an app to auto-activate this profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.appBundleIDs, id: \.self) { bid in
                        HStack(spacing: 6) {
                            Image(systemName: "app.badge")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(bid)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer()
                            Button(action: {
                                profile.appBundleIDs.removeAll { $0 == bid }
                                onSave(profile)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("com.example.App", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .onSubmit { addBundleID() }
                    Button("Add") { addBundleID() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(action: pickApp) {
                        Label("Pick app…", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Conflict warning
                let conflicts = profile.appBundleIDs.filter { bid in
                    store.profiles.contains { p in p.id != profile.id && p.appBundleIDs.contains(bid) }
                }
                if !conflicts.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                        Text("Conflict: \(conflicts.joined(separator: ", ")) also in another profile — first match wins")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.top, 8)
        .onChange(of: store.profiles) { _, updated in
            if let fresh = updated.first(where: { $0.id == profile.id }) {
                profile = fresh
            }
        }
    }

    private func addBundleID() {
        let bid = newBundleID.trimmingCharacters(in: .whitespaces)
        guard !bid.isEmpty, !profile.appBundleIDs.contains(bid) else { return }
        profile.appBundleIDs.append(bid)
        onSave(profile)
        newBundleID = ""
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let bundle = Bundle(url: url),
               let bid = bundle.bundleIdentifier {
                DispatchQueue.main.async {
                    if !self.profile.appBundleIDs.contains(bid) {
                        self.profile.appBundleIDs.append(bid)
                        self.onSave(self.profile)
                    }
                }
            }
        }
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

// MARK: - API Key cleanup section (OpenAI / Anthropic)

private struct APIKeyCleanupSection: View {
    let title: String
    let icon: String
    let color: Color
    let apiKeyGet: () -> String
    let apiKeySet: (String) -> Void
    let modelGet: () -> String
    let modelSet: (String) -> Void
    let defaultModel: String
    let modelOptions: [String]
    @Binding var cleanupTimeout: Int

    @State private var apiKey: String = ""
    @State private var isKeyVisible = false
    @State private var showSaved = false
    @State private var selectedModel: String = ""

    var body: some View {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title) API Key").font(.headline)
                    Text(isConfigured ? "Connected" : "Required for \(title) cleanup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConfigured ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(isConfigured ? "Ready" : "Not Set")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isConfigured ? .green : .secondary)
                }
            }

            HStack(spacing: 8) {
                Group {
                    if isKeyVisible {
                        TextField("Enter your \(title) API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Enter your \(title) API key", text: $apiKey)
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
                    ForEach(modelOptions, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: selectedModel) { _, newValue in
                    modelSet(newValue)
                }
            }

            Stepper(value: $cleanupTimeout, in: 5...60, step: 1) {
                Text("Request timeout: \(cleanupTimeout)s")
                    .font(.subheadline)
            }
            .onChange(of: cleanupTimeout) { _, newValue in
                TranscriptionPreferences.cleanupTimeout = newValue
            }
        }
        .onAppear {
            apiKey = apiKeyGet()
            selectedModel = modelGet().isEmpty ? defaultModel : modelGet()
        }
    }

    private var isConfigured: Bool {
        !apiKeyGet().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKeySet(trimmed)
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

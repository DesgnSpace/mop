import SwiftUI
import SharedModels

struct CleanupView: View {
    @ObservedObject private var callLog = CleanupCallLog.shared
    @State private var useCleanup = TranscriptionPreferences.useTextCleanup
    @State private var selectedDriver = CleanupConfig.selectedDriver
    @State private var cleanupTimeout = TranscriptionPreferences.cleanupTimeout

    var body: some View {
        ScrollView {
            VStack(spacing: MOPDesign.Spacing.sectionGap) {
                enableSection
                CleanupProfilesSection()
                serviceSection
            }
            .padding(MOPDesign.Spacing.settings)
            .background(MOPDesign.Surface.content)
        }
        .navigationTitle("Cleanup")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Reset Profiles") {
                    CleanupProfileStore.shared.resetToDefaults()
                }
            }
        }
    }

    private var enableSection: some View {
        MOPCard {
            MOPSectionHeader(title: "Text Cleanup")

            MOPToggleRow(
                title: "Enable cleanup",
                description: "Fix grammar and punctuation after transcription.",
                isOn: $useCleanup,
                onChange: { TranscriptionPreferences.useTextCleanup = useCleanup }
            )

            if !providerIsReady {
                Label("Set up the selected cleanup service below before using cleanup.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(MOPDesign.Semantic.warning)
            }
        }
    }

    @ViewBuilder
    private var serviceSection: some View {
        MOPCard {
            MOPSectionHeader(title: "Cleanup service")

            MOPSettingsRow(title: "Service") {
                Picker("Service", selection: $selectedDriver) {
                    ForEach(CleanupDriver.allCases, id: \.self) { driver in
                        Text(driver.displayName).tag(driver)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: selectedDriver) { _, newValue in
                    CleanupConfig.selectedDriver = newValue
                }
            }

            if useCleanup {
                switch selectedDriver {
                case .gemini:
                    GeminiCleanupSection(cleanupTimeout: $cleanupTimeout, isInline: true)
                case .openai:
                    APIKeyCleanupSection(
                        title: "OpenAI",
                        icon: "sparkles",
                        apiKeyGet: { CleanupConfig.openAIAPIKey },
                        apiKeySet: { CleanupConfig.openAIAPIKey = $0 },
                        modelGet: { CleanupConfig.openAIModel },
                        modelSet: { CleanupConfig.openAIModel = $0 },
                        defaultModel: "gpt-4o-mini",
                        fallbackModels: CleanupConfig.openAIFallbackModels,
                        fetchModels: CleanupConfig.fetchOpenAIModels,
                        cleanupTimeout: $cleanupTimeout,
                        isInline: true
                    )
                case .anthropic:
                    APIKeyCleanupSection(
                        title: "Anthropic",
                        icon: "brain",
                        apiKeyGet: { CleanupConfig.anthropicAPIKey },
                        apiKeySet: { CleanupConfig.anthropicAPIKey = $0 },
                        modelGet: { CleanupConfig.anthropicModel },
                        modelSet: { CleanupConfig.anthropicModel = $0 },
                        defaultModel: "claude-haiku-4-5-20251001",
                        fallbackModels: ["claude-haiku-4-5-20251001", "claude-sonnet-4-6", "claude-opus-4-7"],
                        fetchModels: { _ in nil },
                        cleanupTimeout: $cleanupTimeout,
                        isInline: true
                    )
                case .ollama:
                    LocalLLMSection(
                        title: "Ollama",
                        icon: "server.rack",
                        endpointKey: \.ollamaEndpoint,
                        modelKey: \.ollamaModel,
                        cleanupTimeout: $cleanupTimeout,
                        isInline: true
                    )
                case .lmStudio:
                    LocalLLMSection(
                        title: "LM Studio",
                        icon: "laptopcomputer",
                        endpointKey: \.lmStudioEndpoint,
                        modelKey: \.lmStudioModel,
                        cleanupTimeout: $cleanupTimeout,
                        isInline: true
                    )
                }
            }
        }
        .disabled(!useCleanup)

        if useCleanup && !callLog.entries.isEmpty {
            cleanupActivityLog
        }
    }

    private var providerIsReady: Bool {
        switch selectedDriver {
        case .gemini:
            return GeminiConfig.isConfigured
        case .openai:
            return !CleanupConfig.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .anthropic:
            return !CleanupConfig.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .ollama:
            return !CleanupConfig.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .lmStudio:
            return !CleanupConfig.lmStudioModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var cleanupActivityLog: some View {
        MOPCard {
            HStack {
                Text("Recent Activity")
                    .font(MOPDesign.Typography.sectionHeader)
                Spacer()
                Button("Clear Activity") { CleanupCallLog.shared.clear() }
                    .buttonStyle(.borderless)
                    .font(MOPDesign.Typography.helper)
                    .foregroundStyle(MOPDesign.Text.tertiary)
            }
            VStack(spacing: MOPDesign.Spacing.denseRow) {
                ForEach(callLog.entries) { (entry: CleanupCallLog.Entry) in
                    HStack(spacing: 8) {
                        MOPStatusMarker(state: entry.success ? .completed : .failed, dense: true)
                        Text(relativeTime(entry.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)
                        if let profile = entry.profileName {
                            Text(profile)
                                .font(MOPDesign.Typography.technicalEmphasis)
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(entry.success ? Color.primary : MOPDesign.Semantic.failure)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }
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
}

// MARK: - Cleanup Profiles Section

@MainActor
private struct CleanupProfilesSection: View {
    @ObservedObject private var store = CleanupProfileStore.shared
    @State private var editingProfile: CleanupProfile?
    @State private var isAddingNew = false
    @State private var newProfileName = ""
    @State private var profileToDelete: CleanupProfile?

    var body: some View {
        MOPCard {
            sectionHeader

            modeSelector

            if store.profiles.isEmpty {
                Text("No profiles yet. Add a profile to customize cleanup.")
                    .font(MOPDesign.Typography.helper)
                    .foregroundStyle(MOPDesign.Text.tertiary)
                    .padding(.vertical, 8)
            } else {
                profileList
            }

            if isAddingNew {
                newProfileRow
            }
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(profile: profile, store: store)
        }
        .confirmationDialog(
            "Delete profile \u{201C}\(profileToDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    if editingProfile?.id == profile.id { editingProfile = nil }
                    store.delete(id: profile.id)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var modeSelector: some View {
        MOPSettingsRow(title: "Profile selection", description: selectionDescription) {
            Picker("Profile selection", selection: Binding(
                get: { store.manualOverrideID != nil },
                set: { fixed in
                    if fixed {
                        if let first = store.profiles.first(where: { $0.isDefault }) ?? store.profiles.first {
                            store.setManualOverride(first.id)
                        }
                    } else {
                        store.clearManualOverride()
                    }
                }
            )) {
                Text("Automatic").tag(false)
                Text("Always use").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)
        }
    }

    private var selectionDescription: String {
        guard let id = store.manualOverrideID,
              let name = store.profiles.first(where: { $0.id == id })?.name else {
            return "Choose a profile automatically for each app and site."
        }
        return "Always use \(name)."
    }

    private var sectionHeader: some View {
        HStack {
            Text("Profiles")
                .font(MOPDesign.Typography.sectionHeader)
            Spacer()
            Button(action: { isAddingNew = true }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Add profile")
            .accessibilityLabel("Add profile")
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
        HStack(spacing: 10) {
            Button(action: {
                if store.manualOverrideID == profile.id {
                    store.clearManualOverride()
                } else {
                    store.setManualOverride(profile.id)
                }
            }) {
                Image(systemName: store.manualOverrideID == profile.id ? "checkmark.circle.fill" : "circle")
                    .font(MOPDesign.Typography.controlLabel)
                    .foregroundStyle(store.manualOverrideID == profile.id ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(store.manualOverrideID == profile.id ? "Use automatic selection" : "Always use this profile")

            Button(action: {
                editingProfile = profile
            }) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(MOPDesign.Typography.rowLabel)
                        .foregroundStyle(.primary)
                    if profile.isDefault {
                        Text("Default")
                            .font(MOPDesign.Typography.helper)
                            .foregroundStyle(MOPDesign.Text.tertiary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                profileToDelete = profile
            }) {
                Image(systemName: "trash")
                    .font(MOPDesign.Typography.controlLabel)
            }
            .buttonStyle(.plain)
            .foregroundStyle(MOPDesign.Text.tertiary)
            .help("Delete profile")
            .accessibilityLabel("Delete profile")
            .opacity(store.profiles.count > 1 ? 1 : 0.3)
            .disabled(store.profiles.count <= 1)
        }
        .padding(.vertical, MOPDesign.Spacing.settingsRow)
        .background(editingProfile?.id == profile.id ? MOPDesign.Surface.selection : .clear)
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
        editingProfile = profile
        isAddingNew = false
        newProfileName = ""
    }
}

// MARK: - Profile Editor Sheet

@MainActor
private struct ProfileEditorSheet: View {
    @State private var profile: CleanupProfile
    let store: CleanupProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var newBundleID = ""
    @State private var newURLHost = ""

    init(profile: CleanupProfile, store: CleanupProfileStore) {
        _profile = State(initialValue: profile)
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MOPDesign.Spacing.sectionGap) {
                HStack {
                    Text("Edit Profile")
                        .font(MOPDesign.Typography.screenTitle)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: MOPDesign.Spacing.output) {
                    Text("Name")
                        .font(MOPDesign.Typography.rowLabel)
                        .foregroundStyle(MOPDesign.Text.tertiary)
                    TextField("Profile name", text: $profile.name)
                        .textFieldStyle(.roundedBorder)
                }
                .onChange(of: profile.name) { _, _ in save() }

                VStack(alignment: .leading, spacing: MOPDesign.Spacing.output) {
                    HStack {
                        Text("Prompt")
                            .font(MOPDesign.Typography.rowLabel)
                            .foregroundStyle(MOPDesign.Text.tertiary)
                        Spacer()
                        Button("Reset") {
                            profile.prompt = TranscriptionPreferences.defaultCleanupPrompt
                            save()
                        }
                        .buttonStyle(.plain)
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(Color.accentColor)
                    }
                    TextEditor(text: $profile.prompt)
                        .font(MOPDesign.Typography.rowLabel)
                        .frame(minHeight: 100, maxHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                }
                .onChange(of: profile.prompt) { _, _ in save() }

                VStack(alignment: .leading, spacing: MOPDesign.Spacing.output) {
                    Text("Cleanup service")
                        .font(MOPDesign.Typography.rowLabel)
                        .foregroundStyle(MOPDesign.Text.tertiary)
                    Picker("", selection: $profile.driverOverride) {
                        Text("Use selected service").tag(Optional<CleanupDriver>.none)
                        ForEach(CleanupDriver.allCases, id: \.self) { d in
                            Text(d.displayName).tag(Optional(d))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .onChange(of: profile.driverOverride) { _, _ in save() }

                MOPToggleRow(
                    title: "Default profile",
                    description: "Used when no app or site rule matches.",
                    isOn: $profile.isDefault,
                    onChange: {
                        if profile.isDefault { store.setDefault(id: profile.id) } else { save() }
                    }
                )

                MOPToggleRow(
                    title: "Use surrounding document text",
                    description: "Include text around the cursor as context.",
                    isOn: $profile.carryContext,
                    onChange: save
                )

                VStack(alignment: .leading, spacing: MOPDesign.Spacing.block) {
                    Text("Apps")
                        .font(MOPDesign.Typography.sectionHeader)

                    if profile.appBundleIDs.isEmpty {
                        Text("No app rules. Add an app to use this profile there.")
                            .font(MOPDesign.Typography.helper)
                            .foregroundStyle(MOPDesign.Text.tertiary)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(profile.appBundleIDs, id: \.self) { bid in
                                HStack(spacing: 6) {
                                    AppIconNameView(bundleID: bid)
                                    Spacer()
                                    Button(action: {
                                        profile.appBundleIDs.removeAll { $0 == bid }
                                        save()
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("com.example.App", text: $newBundleID)
                            .textFieldStyle(.roundedBorder)
                            .font(MOPDesign.Typography.technical)
                            .onSubmit { addBundleID() }
                        Button("Add") { addBundleID() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button(action: pickApp) {
                            Label("Pick…", systemImage: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    let conflicts = profile.appBundleIDs.filter { bid in
                        store.profiles.contains { p in p.id != profile.id && p.appBundleIDs.contains(bid) }
                    }
                    if !conflicts.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MOPDesign.Semantic.warning)
                                .font(MOPDesign.Typography.helper)
                            Text("Conflict: \(conflicts.joined(separator: ", ")) also in another profile")
                                .font(MOPDesign.Typography.helper)
                                .foregroundStyle(MOPDesign.Text.tertiary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: MOPDesign.Spacing.block) {
                    Text("Websites")
                        .font(MOPDesign.Typography.sectionHeader)

                    Text("Matches the active browser tab. MOP may ask for Automation access.")
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(MOPDesign.Text.tertiary)

                    if profile.urlHostPatterns.isEmpty {
                        Text("No website rules. Add a host to use this profile on specific sites.")
                            .font(MOPDesign.Typography.helper)
                            .foregroundStyle(MOPDesign.Text.tertiary)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(profile.urlHostPatterns, id: \.self) { pattern in
                                HStack(spacing: 6) {
                                    Text(pattern)
                                        .font(MOPDesign.Typography.technical)
                                    Spacer()
                                    Button(action: {
                                        profile.urlHostPatterns.removeAll { $0 == pattern }
                                        save()
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("example.com", text: $newURLHost)
                            .textFieldStyle(.roundedBorder)
                            .font(MOPDesign.Typography.technical)
                            .onSubmit { addURLHost() }
                        Button("Add") { addURLHost() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(newURLHost.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    let hostConflicts = profile.urlHostPatterns.filter { pattern in
                        store.profiles.contains { p in p.id != profile.id && p.urlHostPatterns.contains(pattern) }
                    }
                    if !hostConflicts.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MOPDesign.Semantic.warning)
                                .font(MOPDesign.Typography.helper)
                            Text("Conflict: \(hostConflicts.joined(separator: ", ")) also in another profile")
                                .font(MOPDesign.Typography.helper)
                                .foregroundStyle(MOPDesign.Text.tertiary)
                        }
                    }
                }
            }
            .padding(MOPDesign.Spacing.settings)
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    private func save() {
        store.update(profile)
    }

    private func addBundleID() {
        let bid = newBundleID.trimmingCharacters(in: .whitespaces)
        guard !bid.isEmpty, !profile.appBundleIDs.contains(bid) else { return }
        profile.appBundleIDs.append(bid)
        save()
        newBundleID = ""
    }

    private func addURLHost() {
        let host = newURLHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !profile.urlHostPatterns.contains(host) else { return }
        profile.urlHostPatterns.append(host)
        save()
        newURLHost = ""
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier {
                DispatchQueue.main.async {
                    if !self.profile.appBundleIDs.contains(bid) {
                        self.profile.appBundleIDs.append(bid)
                        self.save()
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
    var isInline: Bool = false
    @State private var apiKey: String = GeminiConfig.apiKey
    @State private var isKeyVisible: Bool = false
    @State private var showSaved: Bool = false
    @State private var selectedModel: String = GeminiConfig.selectedModel
    @State private var modelInfos: [GeminiConfig.ModelInfo] = GeminiConfig.effectiveModels
    @State private var isFetchingModels: Bool = false

    var body: some View {
        if isInline {
            inlineStatusHeader

            HStack(spacing: 8) {
                Group {
                    if isKeyVisible {
                        TextField("Enter your Gemini API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(MOPDesign.Typography.code)
                    } else {
                        SecureField("Enter your Gemini API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(MOPDesign.Typography.code)
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
                Text("Model")
                    .font(MOPDesign.Typography.controlLabel)
                    .foregroundStyle(MOPDesign.Text.tertiary)
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
                        Text("Get an API key from ai.google.dev")
                    }
                    .font(MOPDesign.Typography.helper)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            Stepper(value: $cleanupTimeout, in: 5...60, step: 1) {
                Text("Request timeout: \(cleanupTimeout)s")
                    .font(MOPDesign.Typography.controlLabel)
            }
            .onChange(of: cleanupTimeout) { _, newValue in
                TranscriptionPreferences.cleanupTimeout = newValue
            }
        } else {
            VStack(spacing: 16) {
                MOPCard {
                    sectionHeader

                    HStack(spacing: 8) {
                        Group {
                            if isKeyVisible {
                                TextField("Enter your Gemini API key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(MOPDesign.Typography.code)
                            } else {
                                SecureField("Enter your Gemini API key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(MOPDesign.Typography.code)
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
            }
        }
    }

    private var inlineStatusHeader: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(GeminiConfig.isConfigured ? MOPDesign.Semantic.success : MOPDesign.Text.tertiary)
                    .frame(width: 8, height: 8)
                Text(GeminiConfig.isConfigured ? "Ready" : "Not configured")
                    .font(MOPDesign.Typography.helper)
                    .foregroundStyle(GeminiConfig.isConfigured ? MOPDesign.Semantic.success : MOPDesign.Text.tertiary)
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "key.fill")
                    .font(MOPDesign.Typography.controlLabel)
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
                    .fill(GeminiConfig.isConfigured ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(GeminiConfig.isConfigured ? "Ready" : "Not Set")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(GeminiConfig.isConfigured ? .green : .secondary)
            }
        }
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
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            showSaved = false
        }
    }
}

// MARK: - Local LLM sub-section (Ollama / LM Studio)

private struct LocalLLMSection: View {
    let title: String
    let icon: String
    let endpointKey: WritableKeyPath<CleanupConfigValues, String>
    let modelKey: WritableKeyPath<CleanupConfigValues, String>
    @Binding var cleanupTimeout: Int
    var isInline: Bool = false

    @State private var endpoint: String = ""
    @State private var model: String = ""
    @State private var availableModels: [String] = []
    @State private var isFetching = false
    @State private var fetchFailed = false

    var body: some View {
        if isInline {
            inlineContent
        } else {
            VStack(spacing: 16) {
                MOPCard {
                    sectionHeader

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Endpoint")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)
                            TextField("http://localhost:…", text: $endpoint)
                                .textFieldStyle(.roundedBorder)
                                .font(MOPDesign.Typography.code)
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
    }

    private var inlineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Endpoint")
                    .font(MOPDesign.Typography.controlLabel)
                    .foregroundStyle(MOPDesign.Text.tertiary)
                    .frame(width: 70, alignment: .leading)
                TextField("http://localhost:…", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                     .font(MOPDesign.Typography.code)
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
                    .font(MOPDesign.Typography.controlLabel)
                    .foregroundStyle(MOPDesign.Text.tertiary)
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

            Stepper(value: $cleanupTimeout, in: 5...60, step: 1) {
                Text("Request timeout: \(cleanupTimeout)s")
                    .font(MOPDesign.Typography.controlLabel)
            }
            .onChange(of: cleanupTimeout) { _, newValue in
                TranscriptionPreferences.cleanupTimeout = newValue
            }

            if fetchFailed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(MOPDesign.Semantic.warning)
                    Text("\(title) not reachable — enter model name manually")
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(MOPDesign.Text.tertiary)
                }
            }
        }
        .onAppear {
            loadState()
            Task { await fetchModels() }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                     .font(MOPDesign.Typography.controlLabel)
                    .foregroundStyle(Color.accentColor)
            }
            Text(title).font(.headline)
            Spacer()
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
    }

    private func loadState() {
        let vals = CleanupConfigValues()
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
}

// MARK: - API Key cleanup section (OpenAI / Anthropic)

private struct APIKeyCleanupSection: View {
    let title: String
    let icon: String
    let apiKeyGet: () -> String
    let apiKeySet: (String) -> Void
    let modelGet: () -> String
    let modelSet: (String) -> Void
    let defaultModel: String
    let fallbackModels: [String]
    let fetchModels: (String) async -> [String]?
    @Binding var cleanupTimeout: Int
    var isInline: Bool = false

    @State private var apiKey: String = ""
    @State private var isKeyVisible = false
    @State private var showSaved = false
    @State private var selectedModel: String = ""
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var fetchFailed = false

    var body: some View {
        if isInline {
            inlineContent
        } else {
            MOPCard {
                sectionHeader

                HStack(spacing: 8) {
                    Text("Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Group {
                        if isKeyVisible {
                            TextField("Enter your \(title) API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(MOPDesign.Typography.code)
                        } else {
                            SecureField("Enter your \(title) API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                 .font(MOPDesign.Typography.code)
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
                    Text("Model")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    if !availableModels.isEmpty {
                        Picker("", selection: $selectedModel) {
                            ForEach(availableModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: selectedModel) { _, newValue in
                            modelSet(newValue)
                        }
                    } else if fetchFailed || apiKey.isEmpty {
                        TextField("model name", text: $selectedModel)
                            .textFieldStyle(.roundedBorder)
                            .font(MOPDesign.Typography.code)
                            .onChange(of: selectedModel) { _, newValue in
                                modelSet(newValue)
                            }
                    } else {
                        Text("No models fetched")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(action: { Task { await doFetchModels() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isFetchingModels)
                    if isFetchingModels { ProgressView().controlSize(.small) }
                }

                if fetchFailed {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Could not fetch models — enter name manually")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .task {
                await doFetchModels()
            }
        }
    }

    private var inlineContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            inlineStatusHeader

            HStack(spacing: 8) {
                Text("API key")
                    .font(MOPDesign.Typography.controlLabel)
                    .foregroundStyle(MOPDesign.Text.tertiary)
                    .frame(width: 70, alignment: .leading)
                Group {
                    if isKeyVisible {
                        TextField("Enter your \(title) API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(MOPDesign.Typography.code)
                    } else {
                        SecureField("Enter your \(title) API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                             .font(MOPDesign.Typography.code)
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
                Text("Model")
                    .font(MOPDesign.Typography.controlLabel)
                    .foregroundStyle(MOPDesign.Text.tertiary)
                    .frame(width: 70, alignment: .leading)
                if !availableModels.isEmpty {
                    Picker("", selection: $selectedModel) {
                        ForEach(availableModels, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: selectedModel) { _, newValue in
                        modelSet(newValue)
                    }
                } else if fetchFailed || apiKey.isEmpty {
                    TextField("model name", text: $selectedModel)
                        .textFieldStyle(.roundedBorder)
                         .font(MOPDesign.Typography.code)
                        .onChange(of: selectedModel) { _, newValue in
                            modelSet(newValue)
                        }
                } else {
                    Text("No models fetched")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: { Task { await doFetchModels() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isFetchingModels)
                if isFetchingModels { ProgressView().controlSize(.small) }
            }

            if fetchFailed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(MOPDesign.Semantic.warning)
                    Text("Could not fetch models — enter name manually")
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(MOPDesign.Text.tertiary)
                }
            }

            Stepper(value: $cleanupTimeout, in: 5...60, step: 1) {
                Text("Request timeout: \(cleanupTimeout)s")
                    .font(MOPDesign.Typography.controlLabel)
            }
            .onChange(of: cleanupTimeout) { _, newValue in
                TranscriptionPreferences.cleanupTimeout = newValue
            }
        }
        .onAppear {
            apiKey = apiKeyGet()
            selectedModel = modelGet().isEmpty ? defaultModel : modelGet()
        }
        .task {
            await doFetchModels()
        }
    }

    private var inlineStatusHeader: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(isConfigured ? MOPDesign.Semantic.success : MOPDesign.Text.tertiary)
                    .frame(width: 8, height: 8)
                Text(isConfigured ? "Ready" : "Not configured")
                    .font(MOPDesign.Typography.helper)
                    .foregroundStyle(isConfigured ? MOPDesign.Semantic.success : MOPDesign.Text.tertiary)
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                     .font(MOPDesign.Typography.controlLabel)
                    .foregroundStyle(Color.accentColor)
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
                    .fill(isConfigured ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(isConfigured ? "Ready" : "Not Set")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isConfigured ? .green : .secondary)
            }
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
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            showSaved = false
        }
        Task { await doFetchModels() }
    }

    private func doFetchModels() async {
        let key = apiKeyGet()
        guard !key.isEmpty else { return }
        isFetchingModels = true
        fetchFailed = false
        if let models = await fetchModels(key) {
            availableModels = models
            if !models.contains(selectedModel) {
                selectedModel = defaultModel
                modelSet(defaultModel)
            }
            fetchFailed = false
        } else {
            fetchFailed = true
            availableModels = []
        }
        isFetchingModels = false
    }
}

// MARK: - App Icon + Name Resolver

private struct AppIconNameView: View {
    let bundleID: String

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private var appName: String? {
        appURL?.deletingPathExtension().lastPathComponent
    }

    private var icon: NSImage? {
        guard let url = appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.badge")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(appName ?? bundleID)
                 .font(MOPDesign.Typography.technical)
                .foregroundStyle(.primary)
        }
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

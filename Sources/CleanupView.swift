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
                driverCard
            }
            .padding(20)
        }
        .navigationTitle("Cleanup")
    }

    private var enableSection: some View {
        MOPCard {
            MOPSectionHeader(title: "Text Cleanup", icon: "wand.and.sparkles")

            MOPToggleRow(
                title: "Enable cleanup",
                description: "Run transcribed text through an LLM to fix grammar and punctuation",
                isOn: $useCleanup,
                onChange: { TranscriptionPreferences.useTextCleanup = useCleanup }
            )
        }
    }

    @ViewBuilder
    private var driverCard: some View {
        MOPCard {
            MOPSectionHeader(title: "Driver", icon: "cpu")

            Picker("", selection: $selectedDriver) {
                ForEach(CleanupDriver.allCases, id: \.self) { driver in
                    Text(driver.displayName).tag(driver)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedDriver) { _, newValue in
                CleanupConfig.selectedDriver = newValue
            }

            if useCleanup {
                Divider()

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
        .opacity(useCleanup ? 1 : 0.5)

        if useCleanup && !CleanupCallLog.shared.entries.isEmpty {
            cleanupActivityLog
        }
    }

    private var cleanupActivityLog: some View {
        MOPCard {
            HStack {
                Text("Recent Activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { CleanupCallLog.shared.clear() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 3) {
                ForEach(CleanupCallLog.shared.entries) { (entry: CleanupCallLog.Entry) in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(entry.success ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(relativeTime(entry.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)
                        if let profile = entry.profileName {
                            Text(profile)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(.rect(cornerRadius: 4))
                        }
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(entry.success ? Color.primary : Color.red)
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
}

// MARK: - Cleanup Profiles Section

@MainActor
private struct CleanupProfilesSection: View {
    @ObservedObject private var store = CleanupProfileStore.shared
    @State private var editingProfile: CleanupProfile?
    @State private var isAddingNew = false
    @State private var newProfileName = ""

    var body: some View {
        MOPCard {
            sectionHeader

            Divider()

            modeSelector

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
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(profile: profile, store: store)
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 8) {
            Text("Selection")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Picker("", selection: Binding(
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
                Text("Fixed").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if store.manualOverrideID != nil,
               let name = store.profiles.first(where: { $0.id == store.manualOverrideID })?.name {
                Text("→ \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("→ picks by app/site rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Text("Cleanup Profiles")
                .font(.headline)
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
            // Pin button — sets/clears manual override for this profile
            Button(action: {
                if store.manualOverrideID == profile.id {
                    store.clearManualOverride()
                } else {
                    store.setManualOverride(profile.id)
                }
            }) {
                Image(systemName: store.manualOverrideID == profile.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(store.manualOverrideID == profile.id ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(store.manualOverrideID == profile.id ? "Unpin — switch back to automatic" : "Pin as fixed profile")

            Button(action: {
                editingProfile = profile
            }) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if profile.isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                if editingProfile?.id == profile.id { editingProfile = nil }
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
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(editingProfile?.id == profile.id ? Color.accentColor.opacity(0.06) : Color.clear)
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
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Edit Profile")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                // Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Profile name", text: $profile.name)
                        .textFieldStyle(.roundedBorder)
                }
                .onChange(of: profile.name) { _, _ in save() }

                Divider()

                // Prompt
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Prompt")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") {
                            profile.prompt = TranscriptionPreferences.defaultCleanupPrompt
                            save()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    }
                    TextEditor(text: $profile.prompt)
                        .font(.body)
                        .frame(minHeight: 100, maxHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                }
                .onChange(of: profile.prompt) { _, _ in save() }

                Divider()

                // Driver override
                VStack(alignment: .leading, spacing: 6) {
                    Text("Driver")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $profile.driverOverride) {
                        Text("Global default").tag(Optional<CleanupDriver>.none)
                        ForEach(CleanupDriver.allCases, id: \.self) { d in
                            Text(d.displayName).tag(Optional(d))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .onChange(of: profile.driverOverride) { _, _ in save() }

                // Default toggle
                Toggle(isOn: $profile.isDefault) {
                    Text("Default profile (used when no app rule matches)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .tint(Color.accentColor)
                .onChange(of: profile.isDefault) { _, val in
                    if val { store.setDefault(id: profile.id) }
                    else { save() }
                }

                Divider()

                // App rules
                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto-activate for apps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if profile.appBundleIDs.isEmpty {
                        Text("No app rules — add an app to auto-activate this profile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            .font(.system(.caption, design: .monospaced))
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
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Conflict: \(conflicts.joined(separator: ", ")) also in another profile")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // URL host rules
                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto-activate for sites")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Matches when the active browser tab URL contains any of these strings. Requires Automation permission for each browser on first use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if profile.urlHostPatterns.isEmpty {
                        Text("No site rules — add a host to auto-activate on specific websites")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(profile.urlHostPatterns, id: \.self) { pattern in
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(pattern)
                                        .font(.system(.caption, design: .monospaced))
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
                        TextField("twitter.com", text: $newURLHost)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
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
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Conflict: \(hostConflicts.joined(separator: ", ")) also in another profile")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
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
        } else {
            VStack(spacing: 16) {
                MOPCard {
                    sectionHeader

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
            }
        }
    }

    private var inlineStatusHeader: some View {
        HStack {
            Text("Gemini API Key").font(.headline)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(GeminiConfig.isConfigured ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(GeminiConfig.isConfigured ? "Ready" : "Not Set")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GeminiConfig.isConfigured ? .green : .secondary)
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
            try await Task.sleep(for: .seconds(1.5))
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
    }

    private var inlineContent: some View {
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
                    .font(.system(size: 14, weight: .medium))
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
                            .font(.system(.body, design: .monospaced))
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
                Text("Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
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
                        .font(.system(.body, design: .monospaced))
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

    private var inlineStatusHeader: some View {
        HStack {
            Text("\(title) API Key").font(.headline)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(isConfigured ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(isConfigured ? "Ready" : "Not Set")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isConfigured ? .green : .secondary)
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
                    .font(.system(size: 14, weight: .medium))
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
            try await Task.sleep(for: .seconds(1.5))
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
                .font(.system(.caption, design: .monospaced))
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

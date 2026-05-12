import Foundation

@MainActor
public final class CleanupProfileStore: ObservableObject {
    public static let shared = CleanupProfileStore()

    @Published public var profiles: [CleanupProfile] = []
    @Published public var manualOverrideID: UUID?

    private let profilesKey = "cleanupProfiles"
    private let overrideKey = "cleanupProfileManualOverride"

    private init() {
        load()
        if profiles.isEmpty { seedDefaults() }
    }

    // MARK: - Resolution

    public func resolveActive(forFrontmostBundleID bundleID: String?) -> CleanupProfile {
        if let overrideID = manualOverrideID,
           let profile = profiles.first(where: { $0.id == overrideID }) {
            return profile
        }
        if let bundleID, !bundleID.isEmpty,
           let match = profiles.first(where: { $0.appBundleIDs.contains(bundleID) }) {
            return match
        }
        if let defaultProfile = profiles.first(where: { $0.isDefault }) {
            return defaultProfile
        }
        return profiles.first ?? fallbackProfile()
    }

    public func setManualOverride(_ id: UUID) {
        manualOverrideID = id
        UserDefaults.standard.set(id.uuidString, forKey: overrideKey)
    }

    public func clearManualOverride() {
        manualOverrideID = nil
        UserDefaults.standard.removeObject(forKey: overrideKey)
    }

    // MARK: - CRUD

    public func add(_ profile: CleanupProfile) {
        profiles.append(profile)
        save()
    }

    public func update(_ profile: CleanupProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    public func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        if manualOverrideID == id { clearManualOverride() }
        if !profiles.contains(where: { $0.isDefault }), let first = profiles.first {
            var updated = first
            updated.isDefault = true
            update(updated)
        }
        save()
    }

    public func setDefault(id: UUID) {
        for i in profiles.indices {
            profiles[i].isDefault = profiles[i].id == id
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([CleanupProfile].self, from: data) {
            profiles = decoded
        }
        if let raw = UserDefaults.standard.string(forKey: overrideKey),
           let id = UUID(uuidString: raw) {
            manualOverrideID = id
        }
    }

    // MARK: - Seeded defaults

    private func seedDefaults() {
        let base = TranscriptionPreferences.defaultCleanupPrompt
        profiles = [
            CleanupProfile(
                name: "Formal Email",
                prompt: "You are a text cleanup tool for formal email composition. Fix grammar, punctuation, and capitalization. Use complete sentences, proper capitalization, and professional tone. Remove filler words. Output ONLY the corrected text, no explanations, no markdown.",
                appBundleIDs: ["com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac"]
            ),
            CleanupProfile(
                name: "Slack / Chat",
                prompt: "You are a text cleanup tool for chat messages. Fix obvious errors but keep the casual tone. Lowercase is fine. Keep it concise. Output ONLY the corrected text, no explanations, no markdown.",
                appBundleIDs: ["com.tinyspeck.slackmacgap", "com.hnc.Discord"]
            ),
            CleanupProfile(
                name: "iMessage",
                prompt: "You are a text cleanup tool for iMessage. Fix obvious errors, keep it short and conversational. Emoji are fine. Output ONLY the corrected text, no explanations, no markdown.",
                appBundleIDs: ["com.apple.MobileSMS"]
            ),
            CleanupProfile(
                name: "Code Comments",
                prompt: "You are a text cleanup tool for code comments and documentation. Preserve all technical terms, variable names, and identifiers exactly. Use terse imperative style. Fix grammar only. Output ONLY the corrected text, no explanations, no markdown.",
                appBundleIDs: ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode"]
            ),
            CleanupProfile(
                name: "Casual",
                prompt: base,
                isDefault: true
            )
        ]
        save()
    }

    private func fallbackProfile() -> CleanupProfile {
        CleanupProfile(name: "Default", prompt: TranscriptionPreferences.defaultCleanupPrompt, isDefault: true)
    }
}

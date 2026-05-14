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

    public func resolveActive(forFrontmostBundleID bundleID: String?, urlHost: String? = nil) -> CleanupProfile {
        if let overrideID = manualOverrideID,
           let profile = profiles.first(where: { $0.id == overrideID }) {
            return profile
        }
        // URL host match (most specific): prefer profiles that also match the bundle ID
        if let host = urlHost, !host.isEmpty {
            let hostMatches = profiles.filter { profile in
                profile.urlHostPatterns.contains { pattern in
                    host.localizedCaseInsensitiveContains(pattern)
                }
            }
            if let bundleID, let best = hostMatches.first(where: { $0.appBundleIDs.contains(bundleID) }) {
                return best
            }
            if let first = hostMatches.first { return first }
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
                name: "Format",
                prompt: """
Fix grammar, punctuation, and capitalization. Never rephrase or change the user's intended message.

Example: "hey wanted to send over the docs let me know if you need any changes" -> "Hey, wanted to send over the docs. Let me know if you need any changes."

Output ONLY the corrected text, no explanations, no markdown.
""",
                appBundleIDs: []
            ),
            CleanupProfile(
                name: "Casual",
                prompt: base,
                isDefault: true
            ),
            CleanupProfile(
                name: "Code Comments",
                prompt: """
Fix grammar only. Preserve technical terms, variable names, and identifiers exactly. Terse imperative style.

Example: "this function calculate the total" -> "This function calculates the total."

Output ONLY the corrected text, no explanations, no markdown.
""",
                appBundleIDs: ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode"]
            )
        ]
        save()
    }

    private func fallbackProfile() -> CleanupProfile {
        CleanupProfile(name: "Default", prompt: TranscriptionPreferences.defaultCleanupPrompt, isDefault: true)
    }
}

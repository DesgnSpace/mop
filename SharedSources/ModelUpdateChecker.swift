import Foundation
import WhisperKit

/// Checks for newer model variants on HuggingFace and tracks installed versions.
public actor ModelUpdateChecker {
    public static let shared = ModelUpdateChecker()

    private var cachedRemoteVariants: [String]?
    private var lastFetch: Date?
    private let cacheTTL: TimeInterval = 3600  // 1 hour

    private init() {}

    // MARK: - Remote variant fetching

    public func fetchRemoteVariants(forceRefresh: Bool = false) async throws -> [String] {
        if !forceRefresh, let cached = cachedRemoteVariants, let last = lastFetch,
           Date().timeIntervalSince(last) < cacheTTL {
            return cached
        }
        let variants = try await WhisperKit.fetchAvailableModels(from: "argmaxinc/whisperkit-coreml")
        cachedRemoteVariants = variants
        lastFetch = Date()
        return variants
    }

    // MARK: - Version parsing

    /// Extract the date component from a whisperKitModelName, e.g. "v20240930" → Date
    public static func modelDate(from variantName: String) -> Date? {
        // Match "v20240930" or "v20240930" embedded anywhere in the name
        let pattern = #"v(\d{8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: variantName, range: NSRange(variantName.startIndex..., in: variantName)),
              let range = Range(match.range(at: 1), in: variantName) else {
            return nil
        }
        let dateStr = String(variantName[range])
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateStr)
    }

    /// Human-readable version label from variant name, e.g. "Sep 2024"
    public static func versionLabel(from variantName: String) -> String? {
        guard let date = modelDate(from: variantName) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Update detection

    /// Model base key: strips the date and size suffix to get a comparable family string.
    /// e.g. "openai_whisper-large-v3-v20240930_turbo" → "openai_whisper-large-v3-_turbo"
    /// e.g. "openai_whisper-large-v3-v20240930_turbo_632MB" → ignored (size variant of same)
    private static func modelFamilyKey(from variantName: String) -> String? {
        // Remove size suffix (e.g. _632MB, _947MB)
        let sizeSuffixPattern = #"_\d+MB$"#
        var name = variantName
        if let range = name.range(of: sizeSuffixPattern, options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        }
        // Strip the date component
        let datePattern = #"-v\d{8}"#
        guard let range = name.range(of: datePattern, options: .regularExpression) else {
            return nil  // no date → not a versioned variant
        }
        return name.replacingCharacters(in: range, with: "")
    }

    /// Returns the name of a newer remote variant for the given installed whisperKitModelName,
    /// or nil if the installed version is current.
    public func newerVariant(for installedVariant: String, in remoteVariants: [String]) -> String? {
        guard let installedDate = Self.modelDate(from: installedVariant),
              let familyKey = Self.modelFamilyKey(from: installedVariant) else { return nil }

        // Filter remote variants to the same family (excluding size-compressed ones for simplicity)
        let candidates = remoteVariants.filter { remote in
            guard let remoteFamilyKey = Self.modelFamilyKey(from: remote),
                  let remoteDate = Self.modelDate(from: remote) else { return false }
            return remoteFamilyKey == familyKey && remoteDate > installedDate
        }

        // Return the most recent candidate
        return candidates.max(by: { a, b in
            let aDate = Self.modelDate(from: a) ?? .distantPast
            let bDate = Self.modelDate(from: b) ?? .distantPast
            return aDate < bDate
        })
    }

    /// Check all models in the provided list and return a dict of modelName → newer variant name.
    public func checkUpdates(
        for models: [ModelInfo],
        remoteVariants: [String]
    ) -> [String: String] {
        var updates: [String: String] = [:]
        for model in models {
            guard model.engine == .whisperKit,
                  let wkName = model.whisperKitModelName,
                  let newer = newerVariant(for: wkName, in: remoteVariants) else { continue }
            updates[model.name] = newer
        }
        return updates
    }
}

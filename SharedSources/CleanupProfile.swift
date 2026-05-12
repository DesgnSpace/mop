import Foundation

public struct CleanupProfile: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var driverOverride: CleanupDriver?
    public var modelOverride: String?
    public var appBundleIDs: [String]
    public var isDefault: Bool

    public init(id: UUID = UUID(), name: String, prompt: String, driverOverride: CleanupDriver? = nil, modelOverride: String? = nil, appBundleIDs: [String] = [], isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.driverOverride = driverOverride
        self.modelOverride = modelOverride
        self.appBundleIDs = appBundleIDs
        self.isDefault = isDefault
    }
}

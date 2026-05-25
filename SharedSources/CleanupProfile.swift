import Foundation

public struct CleanupProfile: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var driverOverride: CleanupDriver?
    public var modelOverride: String?
    public var appBundleIDs: [String]
    public var urlHostPatterns: [String]
    public var isDefault: Bool
    public var carryContext: Bool

    public init(id: UUID = UUID(), name: String, prompt: String, driverOverride: CleanupDriver? = nil, modelOverride: String? = nil, appBundleIDs: [String] = [], urlHostPatterns: [String] = [], isDefault: Bool = false, carryContext: Bool = false) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.driverOverride = driverOverride
        self.modelOverride = modelOverride
        self.appBundleIDs = appBundleIDs
        self.urlHostPatterns = urlHostPatterns
        self.isDefault = isDefault
        self.carryContext = carryContext
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        prompt = try c.decode(String.self, forKey: .prompt)
        driverOverride = try c.decodeIfPresent(CleanupDriver.self, forKey: .driverOverride)
        modelOverride = try c.decodeIfPresent(String.self, forKey: .modelOverride)
        appBundleIDs = (try? c.decode([String].self, forKey: .appBundleIDs)) ?? []
        urlHostPatterns = (try? c.decode([String].self, forKey: .urlHostPatterns)) ?? []
        isDefault = (try? c.decode(Bool.self, forKey: .isDefault)) ?? false
        carryContext = (try? c.decode(Bool.self, forKey: .carryContext)) ?? false
    }
}

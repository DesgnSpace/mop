import Foundation

public struct CleanupResult {
    public let text: String
    public let model: String?
    public var profileName: String?

    public init(text: String, model: String? = nil) {
        self.text = text
        self.model = model
    }
}

public protocol TextCleanupDriver {
    var driverID: CleanupDriver { get }
    func cleanup(_ text: String, prompt: String) async throws -> CleanupResult
}

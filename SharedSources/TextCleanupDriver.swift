import Foundation

public protocol TextCleanupDriver {
    var driverID: CleanupDriver { get }
    func cleanup(_ text: String, prompt: String) async throws -> String
}

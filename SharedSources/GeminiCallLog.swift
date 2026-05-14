import Foundation
import Combine

public final class CleanupCallLog: ObservableObject {
    public static let shared = CleanupCallLog()

    public struct Entry: Identifiable {
        public let id: UUID
        public let date: Date
        public let success: Bool
        public let detail: String
        public let profileName: String?

        public init(id: UUID = UUID(), date: Date, success: Bool, detail: String, profileName: String? = nil) {
            self.id = id
            self.date = date
            self.success = success
            self.detail = detail
            self.profileName = profileName
        }
    }

    @Published public private(set) var entries: [Entry] = []

    private init() {}

    public func append(success: Bool, detail: String, profileName: String? = nil) {
        let entry = Entry(date: Date(), success: success, detail: detail, profileName: profileName)
        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > 8 {
                self.entries = Array(self.entries.prefix(8))
            }
        }
    }

    public func setLastProfileName(_ name: String) {
        DispatchQueue.main.async {
            guard !self.entries.isEmpty else { return }
            let old = self.entries[0]
            self.entries[0] = Entry(date: old.date, success: old.success, detail: old.detail, profileName: name)
        }
    }

    public func clear() {
        DispatchQueue.main.async { self.entries = [] }
    }
}

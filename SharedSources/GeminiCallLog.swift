import Foundation
import Combine

public final class GeminiCallLog: ObservableObject {
    public static let shared = GeminiCallLog()

    public struct Entry: Identifiable {
        public let id = UUID()
        public let date: Date
        public let success: Bool
        public let detail: String
    }

    @Published public private(set) var entries: [Entry] = []

    private init() {}

    public func append(success: Bool, detail: String) {
        let entry = Entry(date: Date(), success: success, detail: detail)
        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > 8 {
                self.entries = Array(self.entries.prefix(8))
            }
        }
    }

    public func clear() {
        DispatchQueue.main.async { self.entries = [] }
    }
}

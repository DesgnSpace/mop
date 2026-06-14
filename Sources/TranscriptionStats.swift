import Foundation
import SharedModels

@MainActor
class TranscriptionStats: ObservableObject {
    static let shared = TranscriptionStats()
    @Published private(set) var totalTranscriptions: Int = 0
    
    private var statsFileURL: URL {
        return AppPaths.transcriptionStatsFile
    }
    
    private init() {
        loadStats()
    }
    
    private func loadStats() {
        guard FileManager.default.fileExists(atPath: statsFileURL.path) else {
            print("No stats file found, starting fresh")
            return
        }
        
        do {
            let data = try Data(contentsOf: statsFileURL)
            if let stats = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let count = stats["totalTranscriptions"] as? Int {
                totalTranscriptions = count
                print("Loaded stats: \(totalTranscriptions) total transcriptions")
            }
        } catch {
            print("Failed to load stats: \(error)")
        }
    }
    
    private func saveStats() {
        do {
            let stats: [String: Any] = ["totalTranscriptions": totalTranscriptions]
            let data = try JSONSerialization.data(withJSONObject: stats, options: .prettyPrinted)
            try data.write(to: statsFileURL, options: .atomic)
        } catch {
            print("Failed to save stats: \(error)")
        }
    }
    
    func incrementTranscriptionCount() {
        totalTranscriptions += 1
        saveStats()
        print("Total transcriptions: \(totalTranscriptions)")
    }

    func getTotalTranscriptions() -> Int {
        return totalTranscriptions
    }
}
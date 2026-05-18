import Foundation

public enum CleanupConnectionWarmer {
    private static let remoteHosts: [CleanupDriver: String] = [
        .gemini: "https://generativelanguage.googleapis.com",
        .openai: "https://api.openai.com",
        .anthropic: "https://api.anthropic.com"
    ]

    public static func warmActiveDriver() {
        let driver = CleanupConfig.selectedDriver
        guard let hostString = remoteHosts[driver],
              let url = URL(string: hostString) else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        Task.detached(priority: .background) {
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}

import Foundation

public enum LemonSqueezyError: LocalizedError {
    case network(Error)
    case invalidResponse(Int)
    case licenseInvalid(String)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .network(let e): return "Network error: \(e.localizedDescription)"
        case .invalidResponse(let code): return "Server returned \(code)"
        case .licenseInvalid(let msg): return msg
        case .decodingFailed: return "Unexpected response format"
        }
    }
}

public struct ActivationResult {
    public let licenseKey: String
    public let instanceID: String
    public let customerEmail: String
}

public final class LemonSqueezyClient {
    public static let shared = LemonSqueezyClient()
    private init() {}

    private let baseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!

    // Unique instance name per machine
    private var instanceName: String {
        Host.current().localizedName ?? "Mac"
    }

    // MARK: - Activate

    public func activate(licenseKey: String) async throws -> ActivationResult {
        let url = baseURL.appendingPathComponent("activate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode([
            "license_key": licenseKey,
            "instance_name": instanceName
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lk = json["license_key"] as? [String: Any],
              let status = lk["status"] as? String else { throw LemonSqueezyError.decodingFailed }

        guard status == "active" else {
            throw LemonSqueezyError.licenseInvalid("License status: \(status)")
        }

        guard let instance = json["instance"] as? [String: Any],
              let instanceID = instance["id"] as? String else { throw LemonSqueezyError.decodingFailed }

        let email = (lk["customer_email"] as? String) ?? ""
        return ActivationResult(licenseKey: licenseKey, instanceID: instanceID, customerEmail: email)
    }

    // MARK: - Validate

    public func validate(licenseKey: String, instanceID: String) async throws {
        let url = baseURL.appendingPathComponent("validate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode([
            "license_key": licenseKey,
            "instance_id": instanceID
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lk = json["license_key"] as? [String: Any],
              let status = lk["status"] as? String,
              status == "active" else {
            throw LemonSqueezyError.licenseInvalid("License is no longer active")
        }
        _ = data // suppress warning
    }

    // MARK: - Deactivate

    public func deactivate(licenseKey: String, instanceID: String) async throws {
        let url = baseURL.appendingPathComponent("deactivate")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode([
            "license_key": licenseKey,
            "instance_id": instanceID
        ])
        let (_, response) = try await URLSession.shared.data(for: req)
        try validate(response: response)
    }

    // MARK: - Helpers

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw LemonSqueezyError.decodingFailed }
        guard (200..<300).contains(http.statusCode) else {
            throw LemonSqueezyError.invalidResponse(http.statusCode)
        }
    }
}

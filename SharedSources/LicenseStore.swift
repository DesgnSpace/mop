import Foundation

public enum LicenseState: Equatable {
    case trial(daysLeft: Int)
    case licensed(email: String)
    case expired
}

public final class LicenseStore {
    public static let shared = LicenseStore()

    private let defaults = UserDefaults.standard
    private let firstLaunchKey = "sv_firstLaunchDate"
    private let trialDays = 7

    // Keychain keys
    private let kcService = "com.desgnspace.mop"
    private let kcKeyActivatedKey   = "license_key"
    private let kcKeyInstanceID     = "instance_id"
    private let kcKeyCustomerEmail  = "customer_email"

    private init() {
        ensureFirstLaunchDate()
        mirrorTrialFileToDisk()
    }

    // MARK: - Public API

    public var state: LicenseState {
        if let email = keychainString(kcKeyCustomerEmail), !email.isEmpty,
           keychainString(kcKeyActivatedKey) != nil {
            return .licensed(email: email)
        }
        let days = trialDaysRemaining
        return days > 0 ? .trial(daysLeft: days) : .expired
    }

    public var isAllowed: Bool {
        switch state {
        case .trial, .licensed: return true
        case .expired: return false
        }
    }

    public var trialDaysRemaining: Int {
        guard let start = defaults.object(forKey: firstLaunchKey) as? Date else { return trialDays }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, trialDays - elapsed)
    }

    public func activateLicense(key: String, instanceID: String, email: String) {
        setKeychain(kcKeyActivatedKey, value: key)
        setKeychain(kcKeyInstanceID, value: instanceID)
        setKeychain(kcKeyCustomerEmail, value: email)
    }

    public func deactivateLicense() {
        deleteKeychain(kcKeyActivatedKey)
        deleteKeychain(kcKeyInstanceID)
        deleteKeychain(kcKeyCustomerEmail)
    }

    public var activatedLicenseKey: String? { keychainString(kcKeyActivatedKey) }
    public var instanceID: String? { keychainString(kcKeyInstanceID) }

    // MARK: - Trial persistence

    private func ensureFirstLaunchDate() {
        if defaults.object(forKey: firstLaunchKey) == nil {
            let date = diskTrialDate() ?? Date()
            defaults.set(date, forKey: firstLaunchKey)
        }
    }

    private func mirrorTrialFileToDisk() {
        guard let date = defaults.object(forKey: firstLaunchKey) as? Date else { return }
        let url = trialFileURL()
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? date.timeIntervalSinceReferenceDate.description.write(to: url, atomically: true, encoding: .utf8)
    }

    private func diskTrialDate() -> Date? {
        let url = trialFileURL()
        guard let str = try? String(contentsOf: url, encoding: .utf8),
              let ti = TimeInterval(str.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSinceReferenceDate: ti)
    }

    private func trialFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("MOP/.trial")
    }

    // MARK: - Keychain

    private func keychainString(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func setKeychain(_ key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: key
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func deleteKeychain(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

import Foundation

enum BrowserURLDetector {
    private static let bundleToScript: [String: String] = [
        "com.apple.Safari":                  "tell application \"Safari\" to get URL of current tab of front window",
        "com.apple.SafariTechnologyPreview": "tell application \"Safari Technology Preview\" to get URL of current tab of front window",
        "com.google.Chrome":                 "tell application \"Google Chrome\" to get URL of active tab of front window",
        "com.google.Chrome.canary":          "tell application \"Google Chrome Canary\" to get URL of active tab of front window",
        "company.thebrowser.Browser":        "tell application \"Arc\" to get URL of active tab of front window",
        "com.brave.Browser":                 "tell application \"Brave Browser\" to get URL of active tab of front window",
        "com.microsoft.edgemac":             "tell application \"Microsoft Edge\" to get URL of active tab of front window",
        "org.mozilla.firefox":               "tell application \"Firefox\" to get URL of active tab of front window",
    ]

    static func host(forBundleID bundleID: String?) -> String? {
        guard let bundleID,
              let script = bundleToScript[bundleID] else { return nil }
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        guard let descriptor = appleScript?.executeAndReturnError(&error),
              let urlString = descriptor.stringValue,
              let url = URL(string: urlString) else { return nil }
        return url.host
    }
}

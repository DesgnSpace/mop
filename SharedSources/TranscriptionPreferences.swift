import Foundation

public struct TranscriptionPreferences {
    public static var autoPaste: Bool {
        get { UserDefaults.standard.object(forKey: "autoPasteAfterTranscription") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoPasteAfterTranscription") }
    }

    public static var copyToClipboard: Bool {
        get { UserDefaults.standard.object(forKey: "copyToClipboardAfterTranscription") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "copyToClipboardAfterTranscription") }
    }

    public static var useTextCleanup: Bool {
        get { UserDefaults.standard.object(forKey: "useTextCleanup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useTextCleanup") }
    }

    public static var cleanupPrompt: String {
        get { UserDefaults.standard.string(forKey: "cleanupPrompt") ?? defaultCleanupPrompt }
        set { UserDefaults.standard.set(newValue, forKey: "cleanupPrompt") }
    }

    public static var cleanupTimeout: Int {
        get { UserDefaults.standard.object(forKey: "geminiCleanupTimeout") as? Int ?? 10 }
        set { UserDefaults.standard.set(newValue, forKey: "geminiCleanupTimeout") }
    }

    public static let defaultCleanupPrompt = """
You are a text cleanup tool. Fix grammar, punctuation, and capitalization only. NEVER rephrase, rewrite, or change the user's intended message.

Example: "hello how are you i didn't be fine through" -> "Hello, how are you? I'm fine, though."

RULES:
- Output ONLY the corrected text.
- NO explanations, NO reasoning, NO commentary.
- NO quotes, NO markdown.
- If already correct, return unchanged.
"""
}
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

    public static var useGeminiTextCleanup: Bool {
        get { UserDefaults.standard.object(forKey: "useGeminiTextCleanup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useGeminiTextCleanup") }
    }

    public static var cleanupPrompt: String {
        get { UserDefaults.standard.string(forKey: "cleanupPrompt") ?? defaultCleanupPrompt }
        set { UserDefaults.standard.set(newValue, forKey: "cleanupPrompt") }
    }

    public static var geminiCleanupTimeout: Int {
        get { UserDefaults.standard.object(forKey: "geminiCleanupTimeout") as? Int ?? 10 }
        set { UserDefaults.standard.set(newValue, forKey: "geminiCleanupTimeout") }
    }

    public static let defaultCleanupPrompt = """
You are a text cleanup tool. Your ONLY job is to fix grammar, punctuation, and capitalization of transcribed speech. Do NOT change the meaning, wording, or content in any way.

RULES:
- Output ONLY the corrected text.
- NO explanations, NO reasoning, NO thinking steps, NO commentary.
- NO quotes around the output.
- NO markdown formatting.
- If the text is already correct, return it unchanged.
"""
}
import Foundation

public enum TextInsertionMode: String, CaseIterable, Identifiable {
    case typing
    case paste

    public var id: String { rawValue }
}

public enum ClipboardBehavior: String, CaseIterable, Identifiable {
    case restoreOriginal
    case keepTranscription

    public var id: String { rawValue }
}

public struct TranscriptionPreferences {
    public static var autoPaste: Bool {
        get { UserDefaults.standard.object(forKey: "autoPasteAfterTranscription") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoPasteAfterTranscription") }
    }

    public static var clipboardBehavior: ClipboardBehavior {
        get {
            let raw = UserDefaults.standard.string(forKey: "clipboardBehaviorAfterInsertion")
            return ClipboardBehavior(rawValue: raw ?? "") ?? .restoreOriginal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "clipboardBehaviorAfterInsertion") }
    }

    public static var insertionMode: TextInsertionMode {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "transcriptionInsertionMode")
            return TextInsertionMode(rawValue: rawValue ?? "") ?? .typing
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "transcriptionInsertionMode") }
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

    public static var singleClickToRecord: Bool {
        get { UserDefaults.standard.object(forKey: "singleClickToRecord") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "singleClickToRecord") }
    }

    public static var useLiveTranscription: Bool {
        get { UserDefaults.standard.object(forKey: "useLiveTranscription") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "useLiveTranscription") }
    }

    public static var cleanupLiveTranscription: Bool {
        get { UserDefaults.standard.object(forKey: "cleanupLiveTranscription") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "cleanupLiveTranscription") }
    }

    public static let defaultCleanupPrompt = "Fix grammar and punctuation. Output only the corrected text."

    public static let casualCleanupPrompt = """
Clean this transcript while keeping it conversational and natural.

Rules:

* Remove filler words such as "um," "uh," "hmm," and similar verbal tics.
* Remove unnecessary pauses, stutters, false starts, and repeated words.
* Preserve the speaker's personality, tone, and intent.
* Keep the flow relaxed and human, not formal or scripted.
* Retain stories, examples, side notes, and casual phrasing when they add meaning.
* Improve clarity and readability without changing the message.
* Make the speaker sound articulate and confident, but still approachable.
* Avoid corporate, academic, or overly polished language.
* Keep transitions smooth so the transcript reads like natural speech.

Output only the cleaned transcript.
"""

    public static let formatCleanupPrompt = """
Clean this transcript for sharp, concise readability.

Rules:

* Remove filler words: "um," "uh," "hmm," "like," etc.
* Remove pauses, false starts, repeated words, and conversational noise.
* Preserve speaker's original tone, intent, and viewpoint.
* Keep explanations and examples natural and easy to follow.
* Make phrasing concise, confident, and polished.
* Keep tone like someone privately sharing clear opinions, insights, or practical advice.
* Do not over-formalize. Do not rewrite into corporate language.
* Keep examples explicit when speaker gives one.

Output only cleaned transcript.
"""
}

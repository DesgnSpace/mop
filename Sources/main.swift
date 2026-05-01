import Cocoa
import SwiftUI
import KeyboardShortcuts
import AVFoundation
import WhisperKit
import SharedModels
import Combine
import ApplicationServices
import Foundation

struct TranscriptionPreferences {
    static var autoPaste: Bool {
        get { UserDefaults.standard.object(forKey: "autoPasteAfterTranscription") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoPasteAfterTranscription") }
    }

    static var copyToClipboard: Bool {
        get { UserDefaults.standard.object(forKey: "copyToClipboardAfterTranscription") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "copyToClipboardAfterTranscription") }
    }

    static var useGeminiTextCleanup: Bool {
        get { UserDefaults.standard.object(forKey: "useGeminiTextCleanup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useGeminiTextCleanup") }
    }

    static var cleanupPrompt: String {
        get { UserDefaults.standard.string(forKey: "cleanupPrompt") ?? defaultCleanupPrompt }
        set { UserDefaults.standard.set(newValue, forKey: "cleanupPrompt") }
    }

    static let defaultCleanupPrompt = """
You are a text cleanup tool. Your ONLY job is to fix grammar, punctuation, and capitalization of transcribed speech. Do NOT change the meaning, wording, or content in any way.

RULES:
- Output ONLY the corrected text.
- NO explanations, NO reasoning, NO thinking steps, NO commentary.
- NO quotes around the output.
- NO markdown formatting.
- If the text is already correct, return it unchanged.
"""
}

extension KeyboardShortcuts.Name {
    static let startRecording = Self("startRecording")
    static let showHistory = Self("showHistory")
    static let readSelectedText = Self("readSelectedText")
    static let pasteLastTranscription = Self("pasteLastTranscription")
}

class AppDelegate: NSObject, NSApplicationDelegate, AudioTranscriptionManagerDelegate {
    var statusItem: NSStatusItem!
    private var unifiedWindow: UnifiedManagerWindow?
    private var modelCancellable: AnyCancellable?
    private var engineCancellable: AnyCancellable?
    private var parakeetVersionCancellable: AnyCancellable?
    private var transcriptionTimer: Timer?
    private var audioManager: AudioTranscriptionManager!
    private var streamingPlayer: GeminiStreamingPlayer?
    private var audioCollector: GeminiAudioCollector?
    private var isCurrentlyPlaying = false
    private var currentStreamingTask: Task<Void, Never>?
    private let mediaPlaybackController = MediaPlaybackController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        GeminiConfig.migrateFromEnvFile()
        initializeTTS()
        setupStatusBar()
        setupKeyboardShortcuts()
        setupAudioManager()
        setupModelObservers()
        loadModelsInBackground()
    }

    private func initializeTTS() {
        guard GeminiConfig.isConfigured, #available(macOS 14.0, *) else {
            print("⚠️ GEMINI_API_KEY not configured — use Settings to add your API key")
            return
        }

        streamingPlayer = GeminiStreamingPlayer(playbackSpeed: 1.15)
        audioCollector = GeminiAudioCollector(apiKey: GeminiConfig.apiKey)
        print("✅ Streaming TTS components initialized")
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Assistant")
        statusItem.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Read Selected Text", action: #selector(handleReadSelectedTextToggle), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show History", action: #selector(showTranscriptionHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Paste Last Transcription", action: #selector(pasteLastTranscription), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Statistics...", action: #selector(showStats), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.control]), for: .startRecording)
        KeyboardShortcuts.setShortcut(.init(.a, modifiers: [.command, .option]), for: .showHistory)
        KeyboardShortcuts.setShortcut(.init(.s, modifiers: [.command, .option]), for: .readSelectedText)
        KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .option]), for: .pasteLastTranscription)

        KeyboardShortcuts.onKeyDown(for: .startRecording) { [weak self] in
            self?.toggleRecording()
        }

        KeyboardShortcuts.onKeyDown(for: .showHistory) { [weak self] in
            self?.showTranscriptionHistory()
        }

        KeyboardShortcuts.onKeyDown(for: .readSelectedText) { [weak self] in
            self?.handleReadSelectedTextToggle()
        }

        KeyboardShortcuts.onKeyDown(for: .pasteLastTranscription) { [weak self] in
            self?.pasteLastTranscription()
        }
    }

    @objc func toggleRecording() {
        guard !audioManager.isRecording else {
            audioManager.toggleRecording()
            return
        }

        let controller = mediaPlaybackController
        DispatchQueue.global(qos: .userInitiated).async {
            controller.pauseActiveMediaApps()
        }
        stopTranscriptionIndicator()
        NSSound(named: "Tink")?.play()
        audioManager.toggleRecording()
    }

    private func setupAudioManager() {
        audioManager = AudioTranscriptionManager()
        audioManager.delegate = self
    }

    @MainActor
    private func loadModelsInBackground() {
        Task {
            await ModelStateManager.shared.checkDownloadedModels()
            print("Model check completed at startup")

            switch ModelStateManager.shared.selectedEngine {
            case .whisperKit:
                if let selectedModel = ModelStateManager.shared.selectedModel {
                    _ = await ModelStateManager.shared.loadModel(selectedModel)
                }
            case .parakeet:
                await ModelStateManager.shared.loadParakeetModel()
            }
        }
    }

    @MainActor
    private func setupModelObservers() {
        modelCancellable = ModelStateManager.shared.$selectedModel
            .dropFirst()
            .sink { selectedModel in
                guard let selectedModel = selectedModel,
                      ModelStateManager.shared.selectedEngine == .whisperKit else { return }
                Task {
                    _ = await ModelStateManager.shared.loadModel(selectedModel)
                }
            }

        engineCancellable = ModelStateManager.shared.$selectedEngine
            .dropFirst()
            .sink { engine in
                switch engine {
                case .whisperKit:
                    ModelStateManager.shared.unloadParakeetModel()
                case .parakeet:
                    ModelStateManager.shared.unloadWhisperKitModel()
                }
            }
    }

    @objc func openSettings() {
        openUnifiedWindow(tab: .models)
    }

    @objc func showTranscriptionHistory() {
        openUnifiedWindow(tab: .history)
    }

    @objc func showStats() {
        openUnifiedWindow(tab: .statistics)
    }

    private func openUnifiedWindow(tab: SidebarItem) {
        if unifiedWindow == nil {
            unifiedWindow = UnifiedManagerWindow()
        }
        unifiedWindow?.showWindow(tab: tab)
    }

    @objc func handleReadSelectedTextToggle() {
        if isCurrentlyPlaying {
            stopCurrentPlayback()
            return
        }

        readSelectedText()
    }

    @objc func pasteLastTranscription() {
        guard let lastEntry = TranscriptionHistory.shared.getEntries().first else {
            showNotification(title: "No Transcription Available", text: "No transcription history found")
            return
        }

        typeTextAtCursor(lastEntry.text)
        showNotification(title: "Inserted Last Transcription", text: lastEntry.text.prefix(100) + (lastEntry.text.count > 100 ? "..." : ""))
    }

    func stopCurrentPlayback() {
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
        streamingPlayer?.stopAudioEngine()
        isCurrentlyPlaying = false
        showNotification(title: "Audio Stopped", text: "Text-to-speech playback stopped")
    }

    func readSelectedText() {
        let clipboard = ClipboardManager()
        clipboard.save()
        simulateCommand(keyCode: 0x08)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }

            let copiedText = NSPasteboard.general.string(forType: .string) ?? ""

            if copiedText.isEmpty {
                self.handleEmptySelection(clipboard: clipboard)
                return
            }

            self.streamTextToSpeech(copiedText, clipboard: clipboard)
        }
    }

    private func handleEmptySelection(clipboard: ClipboardManager) {
        showNotification(title: "No Text Selected", text: "Please select some text first before using TTS")
        clipboard.restore()
    }

    private func streamTextToSpeech(_ text: String, clipboard: ClipboardManager) {
        guard let audioCollector = audioCollector, let streamingPlayer = streamingPlayer else {
            showNotification(title: "Selected Text Copied", text: text.prefix(100) + (text.count > 100 ? "..." : ""))
            return
        }

        isCurrentlyPlaying = true

        currentStreamingTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            defer {
                self.isCurrentlyPlaying = false
                self.currentStreamingTask = nil
            }

            defer {
                clipboard.restore()
            }

            showNotification(title: "Streaming TTS", text: text.prefix(50) + (text.count > 50 ? "..." : ""))

            do {
                try await streamingPlayer.playText(text, audioCollector: audioCollector)
                guard !Task.isCancelled else { return }
                showNotification(title: "Streaming TTS Complete", text: "Finished streaming selected text")
            } catch is CancellationError {
                print("🛑 Audio streaming was cancelled")
            } catch {
                print("❌ Streaming TTS Error: \(error)")
                showNotification(title: "Streaming TTS Error", text: error.localizedDescription)
            }
        }
    }

    func updateStatusBarWithLevel(db: Float) {
        guard let button = statusItem.button else { return }

        let normalizedLevel = max(0, min(1, (db + 55) / 35))
        let barLength = 8
        let filledLength = Int(normalizedLevel * Float(barLength))
        let bar = (0..<barLength).map { $0 < filledLength ? "█" : "▁" }.joined()

        button.image = nil
        button.title = "● " + bar
    }

    func startTranscriptionIndicator() {
        statusItem.button?.image = nil
        statusItem.button?.title = "⚙️ Processing..."

        var dotCount = 0
        transcriptionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            dotCount = (dotCount + 1) % 4
            let dots = String(repeating: ".", count: dotCount)
            let spaces = String(repeating: " ", count: 3 - dotCount)
            self.statusItem.button?.title = "⚙️ Processing" + dots + spaces
        }
    }

    func stopTranscriptionIndicator() {
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil

        guard audioManager?.isRecording != true else { return }
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Assistant")
        statusItem.button?.title = ""
    }

    func showTranscriptionNotification(_ text: String) {
        showNotification(title: "Transcription Complete", text: text, subtitle: "Inserted at cursor", sound: true)
    }

    func showTranscriptionError(_ message: String) {
        showNotification(title: "Transcription Error", text: message, sound: true)
    }

    private var didPromptAX = false

    @discardableResult
    func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !didPromptAX {
            didPromptAX = true
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            showNotification(
                title: "Accessibility Permission Needed",
                text: "Grant Accessibility access in System Settings → Privacy & Security so transcribed text can be inserted.",
                sound: true
            )
        }
        return false
    }

    func typeTextAtCursor(_ text: String) {
        guard ensureAccessibilityPermission() else { return }
        guard !text.isEmpty else { return }

        print("📝 Inserting '\(text.prefix(30))...' at cursor")

        if insertViaAXAPI(text) {
            print("✅ Inserted via AX API")
            return
        }

        insertViaUnicodeEvents(text)
        print("✅ Inserted via CGEvent unicode")
    }

    private func insertViaAXAPI(_ text: String) -> Bool {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }

        let element = focused as! AXUIElement
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return result == .success
    }

    private func insertViaUnicodeEvents(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(text.utf16)
        let chunkSize = 20
        var offset = 0

        while offset < utf16.count {
            let end = min(offset + chunkSize, utf16.count)
            let chunk = Array(utf16[offset..<end])

            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.flags = []
                chunk.withUnsafeBufferPointer { buf in
                    down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                down.post(tap: .cgAnnotatedSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.flags = []
                chunk.withUnsafeBufferPointer { buf in
                    up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                up.post(tap: .cgAnnotatedSessionEventTap)
            }

            offset = end
        }
    }

    // MARK: - AudioTranscriptionManagerDelegate

    func audioLevelDidUpdate(db: Float) {
        updateStatusBarWithLevel(db: db)
    }

    func transcriptionDidStart() {
        NSSound(named: "Glass")?.play()
        startTranscriptionIndicator()
    }

    func transcriptionDidComplete(text: String) {
        NSSound(named: "Glass")?.play()
        stopTranscriptionIndicator()

        let cleanupActive = TranscriptionPreferences.useGeminiTextCleanup && GeminiConfig.isConfigured

        if cleanupActive {
            if TranscriptionPreferences.copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                print("📋 Raw transcription copied to clipboard (awaiting cleanup)")
            }
            return
        }

        if TranscriptionPreferences.autoPaste {
            typeTextAtCursor(text)
        } else if TranscriptionPreferences.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            print("📋 Raw transcription copied to clipboard")
        }

        showTranscriptionNotification(text)
    }

    func transcriptionDidCleanUp(text: String) {
        if TranscriptionPreferences.autoPaste {
            typeTextAtCursor(text)
        }
        if TranscriptionPreferences.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            print("📋 Cleaned transcription copied to clipboard")
        }

        showNotification(title: "Transcription Complete", text: text, subtitle: "Inserted at cursor", sound: true)
    }

    func transcriptionDidFail(error: String) {
        stopTranscriptionIndicator()
        showTranscriptionError(error)
    }

    func recordingWasCancelled() {
        stopTranscriptionIndicator()
        resetStatusBarIcon()
        showNotification(title: "Recording Cancelled", text: "Recording was cancelled")
    }

    func recordingWasSkippedDueToSilence() {
        stopTranscriptionIndicator()
        resetStatusBarIcon()
        showNotification(title: "Recording Skipped", text: "Audio was too quiet to transcribe")
    }

    private func resetStatusBarIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Assistant")
        statusItem.button?.title = ""
    }

    // MARK: - Helpers

    private func showNotification(title: String, text: String, subtitle: String? = nil, sound: Bool = false) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = text
        notification.subtitle = subtitle
        if sound {
            notification.soundName = NSUserNotificationDefaultSoundName
        }
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func simulateCommand(keyCode: CGKeyCode, modifiers: CGEventFlags = .maskCommand) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = modifiers
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            if modifiers != .maskCommand {
                keyUp.flags = modifiers
            }
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

private final class MediaPlaybackController {
    private struct PauseCommand {
        let bundleIdentifier: String
        let appName: String
        let script: String
    }

    private let pauseCommands = [
        PauseCommand(
            bundleIdentifier: "com.apple.Music",
            appName: "Music",
            script: "if player state is playing then pause"
        ),
        PauseCommand(
            bundleIdentifier: "com.spotify.client",
            appName: "Spotify",
            script: "if player state is playing then pause"
        ),
        PauseCommand(
            bundleIdentifier: "org.videolan.vlc",
            appName: "VLC",
            script: "if playing then pause"
        ),
        PauseCommand(
            bundleIdentifier: "com.colliderli.iina",
            appName: "IINA",
            script: "if playing then pause"
        ),
        PauseCommand(
            bundleIdentifier: "com.apple.QuickTimePlayerX",
            appName: "QuickTime Player",
            script: "if playing then pause document 1"
        )
    ]

    func pauseActiveMediaApps() {
        let runningBundleIdentifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )

        for command in pauseCommands where runningBundleIdentifiers.contains(command.bundleIdentifier) {
            pauseIfPlaying(command)
        }
    }

    private func pauseIfPlaying(_ command: PauseCommand) {
        let source = """
        tell application \"\(command.appName)\"
            \(command.script)
        end tell
        """

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)

        if let error {
            print("⚠️ Failed to pause \(command.appName): \(error)")
            return
        }

        print("⏸ Paused media in \(command.appName)")
    }
}

// MARK: - ClipboardManager

private final class ClipboardManager: @unchecked Sendable {
    private var savedItems: [NSPasteboard.PasteboardType: Data] = [:]

    func save() {
        let pasteboard = NSPasteboard.general
        savedItems.removeAll()
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                savedItems[type] = data
            }
        }
        print("📋 Saved \(savedItems.count) clipboard types")
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for (type, data) in savedItems {
            pasteboard.setData(data, forType: type)
        }
        print("♻️ Restored clipboard")
    }
}

// MARK: - App Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
   let iconImage = NSImage(contentsOf: iconURL) {
    app.applicationIconImage = iconImage
}

app.run()

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
You are a text cleanup tool. Your ONLY job is to fix grammar, punctuation, and capitalization of transcribed speech. You must NOT change the meaning, wording, or content in any way.

RULES:
- Output ONLY the corrected text.
- NO explanations, NO reasoning, NO thinking steps, NO commentary.
- NO quotes around the output.
- NO markdown formatting.
- If the text is already correct, return it unchanged.

Input:
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
        menu.addItem(NSMenuItem(title: "Start Recording", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Read Selected Text", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show History", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Paste Last Transcription", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "View History...", action: #selector(showTranscriptionHistory), keyEquivalent: "h"))
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

        KeyboardShortcuts.onKeyUp(for: .startRecording) { [weak self] in
            self?.toggleRecording()
        }

        KeyboardShortcuts.onKeyUp(for: .showHistory) { [weak self] in
            self?.showTranscriptionHistory()
        }

        KeyboardShortcuts.onKeyUp(for: .readSelectedText) { [weak self] in
            self?.handleReadSelectedTextToggle()
        }

        KeyboardShortcuts.onKeyUp(for: .pasteLastTranscription) { [weak self] in
            self?.pasteLastTranscription()
        }
    }

    private func toggleRecording() {
        guard !audioManager.isRecording else {
            audioManager.toggleRecording()
            return
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

    func handleReadSelectedTextToggle() {
        if isCurrentlyPlaying {
            stopCurrentPlayback()
            return
        }

        readSelectedText()
    }

    func pasteLastTranscription() {
        guard let lastEntry = TranscriptionHistory.shared.getEntries().first else {
            showNotification(title: "No Transcription Available", text: "No transcription history found")
            return
        }

        pasteTextAtCursor(lastEntry.text)
        showNotification(title: "Pasted Last Transcription", text: lastEntry.text.prefix(100) + (lastEntry.text.count > 100 ? "..." : ""))
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
        showNotification(title: "Transcription Complete", text: text, subtitle: "Pasted at cursor", sound: true)
    }

    func showTranscriptionError(_ message: String) {
        showNotification(title: "Transcription Error", text: message, sound: true)
    }

    func pasteTextAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        print("📝 Attempting to paste '\(text.prefix(30))...' at cursor")

        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }

        print("✅ Paste command sent")
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

        let autoPaste = TranscriptionPreferences.autoPaste
        let copyToClipboard = TranscriptionPreferences.copyToClipboard

        if autoPaste {
            pasteTextAtCursor(text)
        } else if copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            print("📋 Raw transcription copied to clipboard")
        }

        showTranscriptionNotification(text)
    }

    func transcriptionDidCleanUp(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        print("📋 Cleaned transcription copied to clipboard")

        showNotification(title: "Transcription Cleaned", text: text, subtitle: "Updated in clipboard", sound: true)
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
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

    static let defaultCleanupPrompt = "Fix grammar and punctuation of this transcribed speech without changing its meaning or content. Return only the corrected text, no commentary, no quotes:"
}

// Environment variable loading
extension KeyboardShortcuts.Name {
    static let startRecording = Self("startRecording")
    static let showHistory = Self("showHistory")
    static let readSelectedText = Self("readSelectedText")
    static let pasteLastTranscription = Self("pasteLastTranscription")
}

class AppDelegate: NSObject, NSApplicationDelegate, AudioTranscriptionManagerDelegate {
    var statusItem: NSStatusItem!
    private var unifiedWindow: UnifiedManagerWindow?

    private var displayTimer: Timer?
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
        // Migrate API key from .env file to UserDefaults if present
        GeminiConfig.migrateFromEnvFile()
        
        // Initialize streaming TTS components if API key is available
        if GeminiConfig.isConfigured, #available(macOS 14.0, *) {
            streamingPlayer = GeminiStreamingPlayer(playbackSpeed: 1.15)
            audioCollector = GeminiAudioCollector(apiKey: GeminiConfig.apiKey)
            print("✅ Streaming TTS components initialized")
        } else {
            print("⚠️ GEMINI_API_KEY not configured — use Settings to add your API key")
        }
        
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set the waveform icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Assistant")
        }
        
        // Create menu
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
        statusItem.menu = menu
        
        // Set default keyboard shortcuts
        KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.control]), for: .startRecording)
        KeyboardShortcuts.setShortcut(.init(.a, modifiers: [.command, .option]), for: .showHistory)
        KeyboardShortcuts.setShortcut(.init(.s, modifiers: [.command, .option]), for: .readSelectedText)
        KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .option]), for: .pasteLastTranscription)
        
        // Set up keyboard shortcut handlers
        KeyboardShortcuts.onKeyUp(for: .startRecording) { [weak self] in
            guard let self = self else { return }

// If about to start a fresh recording, make sure any previous
            // processing indicator is stopped and UI is reset.
            if !self.audioManager.isRecording {
                self.stopTranscriptionIndicator()
            }
            self.audioManager.toggleRecording()
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

        // Set up audio manager
        audioManager = AudioTranscriptionManager()
        audioManager.delegate = self

// Check downloaded models at startup (in background)
        Task {
            await ModelStateManager.shared.checkDownloadedModels()
            print("Model check completed at startup")

            // Load the initially selected model based on engine
            switch ModelStateManager.shared.selectedEngine {
            case .whisperKit:
                if let selectedModel = ModelStateManager.shared.selectedModel {
                    _ = await ModelStateManager.shared.loadModel(selectedModel)
                }
            case .parakeet:
                await ModelStateManager.shared.loadParakeetModel()
            }
        }

        // Observe WhisperKit model selection changes
        modelCancellable = ModelStateManager.shared.$selectedModel
            .dropFirst() // Skip the initial value
            .sink { selectedModel in
                guard let selectedModel = selectedModel else { return }
                // Only load if WhisperKit is the selected engine
                guard ModelStateManager.shared.selectedEngine == .whisperKit else { return }
                Task {
                    // Load the new model
                    _ = await ModelStateManager.shared.loadModel(selectedModel)
                }
            }

        // Observe engine changes - only handle memory management, not loading
        // Loading is triggered by user actions (selecting/downloading models)
        engineCancellable = ModelStateManager.shared.$selectedEngine
            .dropFirst() // Skip the initial value
            .sink { engine in
                switch engine {
                case .whisperKit:
                    // Unload Parakeet to free memory
                    ModelStateManager.shared.unloadParakeetModel()
                case .parakeet:
                    // Unload WhisperKit to free memory
                    ModelStateManager.shared.unloadWhisperKitModel()
                }
            }

        // Note: Parakeet version changes don't auto-load
        // User must click to download/select a specific version
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
        // If currently playing, stop the audio
        if isCurrentlyPlaying {
            stopCurrentPlayback()
            return
        }

        // Otherwise, start reading selected text
        readSelectedText()
    }

    func pasteLastTranscription() {
        // Get the most recent transcription from history
        guard let lastEntry = TranscriptionHistory.shared.getEntries().first else {
            let notification = NSUserNotification()
            notification.title = "No Transcription Available"
            notification.informativeText = "No transcription history found"
            NSUserNotificationCenter.default.deliver(notification)
            print("⚠️ No transcription history to paste")
            return
        }

        // Paste the last transcription at cursor
        pasteTextAtCursor(lastEntry.text)

        let notification = NSUserNotification()
        notification.title = "Pasted Last Transcription"
        notification.informativeText = lastEntry.text.prefix(100) + (lastEntry.text.count > 100 ? "..." : "")
        NSUserNotificationCenter.default.deliver(notification)
        print("📋 Pasted last transcription: \(lastEntry.text.prefix(50))...")
    }

    func stopCurrentPlayback() {
        print("🛑 Stopping audio playback")
        
        // Cancel the current streaming task
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
        
        // Stop the audio player
        streamingPlayer?.stopAudioEngine()
        
        // Reset playing state
        isCurrentlyPlaying = false
        
        let notification = NSUserNotification()
        notification.title = "Audio Stopped"
        notification.informativeText = "Text-to-speech playback stopped"
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func readSelectedText() {
        // Save current clipboard contents first
        let pasteboard = NSPasteboard.general
        let savedTypes = pasteboard.types ?? []
        var savedItems: [NSPasteboard.PasteboardType: Data] = [:]
        
        for type in savedTypes {
            if let data = pasteboard.data(forType: type) {
                savedItems[type] = data
            }
        }
        
        print("📋 Saved \(savedItems.count) clipboard types before reading selection")
        
        // Simulate Cmd+C to copy selected text
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDownC = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 'c' key
        let keyUpC = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        
        // Set Cmd modifier
        keyDownC?.flags = .maskCommand
        keyUpC?.flags = .maskCommand
        
        // Post the events
        keyDownC?.post(tap: .cghidEventTap)
        keyUpC?.post(tap: .cghidEventTap)
        
        // Give system a moment to process the copy command
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            // Read from clipboard
            let copiedText = pasteboard.string(forType: .string) ?? ""
            
            if !copiedText.isEmpty {
                print("📖 Selected text for streaming TTS: \(copiedText)")
                
                // Try to stream speech with our streaming components
                if let audioCollector = self?.audioCollector, let streamingPlayer = self?.streamingPlayer {
                    self?.isCurrentlyPlaying = true
                    
                    self?.currentStreamingTask = Task {
                        do {
                            let notification = NSUserNotification()
                            notification.title = "Streaming TTS"
                            notification.informativeText = "Starting streaming synthesis: \(copiedText.prefix(50))\(copiedText.count > 50 ? "..." : "")"
                            NSUserNotificationCenter.default.deliver(notification)
                            
                            // Stream audio using single API call for all text at once
                            try await streamingPlayer.playText(copiedText, audioCollector: audioCollector)
                            
                            // Check if task was cancelled
                            if Task.isCancelled {
                                return
                            }
                            
                            let completionNotification = NSUserNotification()
                            completionNotification.title = "Streaming TTS Complete"
                            completionNotification.informativeText = "Finished streaming selected text"
                            NSUserNotificationCenter.default.deliver(completionNotification)
                            
                        } catch is CancellationError {
                            print("🛑 Audio streaming was cancelled")
                        } catch {
                            print("❌ Streaming TTS Error: \(error)")
                            
                            let errorNotification = NSUserNotification()
                            errorNotification.title = "Streaming TTS Error"
                            errorNotification.informativeText = "Failed to stream text: \(error.localizedDescription)"
                            NSUserNotificationCenter.default.deliver(errorNotification)
                            
                            // Note: Text is already in clipboard from Cmd+C, no need to copy again
                            let fallbackNotification = NSUserNotification()
                            fallbackNotification.title = "Text Ready in Clipboard"
                            fallbackNotification.informativeText = "Streaming failed, selected text copied via Cmd+C"
                            NSUserNotificationCenter.default.deliver(fallbackNotification)
                        }
                        
                        // Reset playing state when task completes (normally or via cancellation)
                        DispatchQueue.main.async {
                            self?.isCurrentlyPlaying = false
                            self?.currentStreamingTask = nil
                        }
                        
                        // Restore original clipboard contents after streaming
                        DispatchQueue.main.async {
                            pasteboard.clearContents()
                            for (type, data) in savedItems {
                                pasteboard.setData(data, forType: type)
                            }
                            print("♻️ Restored original clipboard contents")
                        }
                    }
                } else {
                    let notification = NSUserNotification()
                    notification.title = "Selected Text Copied"
                    notification.informativeText = "Streaming TTS not available, text copied to clipboard: \(copiedText.prefix(100))\(copiedText.count > 100 ? "..." : "")"
                    NSUserNotificationCenter.default.deliver(notification)
                    
                    // Don't restore clipboard in this case since user might want the copied text
                }
            } else {
                print("⚠️ No text was copied - nothing selected or copy failed")
                
                let notification = NSUserNotification()
                notification.title = "No Text Selected"
                notification.informativeText = "Please select some text first before using TTS"
                NSUserNotificationCenter.default.deliver(notification)
                
                // Restore clipboard since copy attempt failed
                pasteboard.clearContents()
                for (type, data) in savedItems {
                    pasteboard.setData(data, forType: type)
                }
                print("♻️ Restored clipboard after failed copy")
            }
        }
    }
    
    func updateStatusBarWithLevel(db: Float) {
        if let button = statusItem.button {
            button.image = nil

            // Convert dB to a 0-1 range (assuming -55dB to -20dB for normal speech)
            let normalizedLevel = max(0, min(1, (db + 55) / 35))

            // Create a visual bar using Unicode block characters
            let barLength = 8
            let filledLength = Int(normalizedLevel * Float(barLength))

            var bar = ""
            for i in 0..<barLength {
                if i < filledLength {
                    bar += "█"
                } else {
                    bar += "▁"
                }
            }

            button.title = "● " + bar
        }
    }
    
    func startTranscriptionIndicator() {
        // Show initial indicator
        if let button = statusItem.button {
            button.image = nil
            button.title = "⚙️ Processing..."
        }

        // Animate the indicator
        var dotCount = 0
        transcriptionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else {
                self?.transcriptionTimer?.invalidate()
                return
            }

            if let button = self.statusItem.button {
                dotCount = (dotCount + 1) % 4
                let dots = String(repeating: ".", count: dotCount)
                let spaces = String(repeating: " ", count: 3 - dotCount)
                button.title = "⚙️ Processing" + dots + spaces
            }
        }
    }
    
func stopTranscriptionIndicator() {
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil

        // If not currently recording, reset to default icon.
        // When recording, the live level updates will take over UI shortly.
        if audioManager?.isRecording != true {
            if let button = statusItem.button {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Assistant")
                button.title = ""
            }
        }
    }
    
    func showTranscriptionNotification(_ text: String) {
        let notification = NSUserNotification()
        notification.title = "Transcription Complete"
        notification.informativeText = text
        notification.subtitle = "Pasted at cursor"
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func showTranscriptionError(_ message: String) {
        let notification = NSUserNotification()
        notification.title = "Transcription Error"
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func pasteTextAtCursor(_ text: String, preserveInClipboard: Bool = false) {
        let pasteboard = NSPasteboard.general
        let savedTypes = pasteboard.types ?? []
        var savedItems: [NSPasteboard.PasteboardType: Data] = [:]

        if !preserveInClipboard {
            for type in savedTypes {
                if let data = pasteboard.data(forType: type) {
                    savedItems[type] = data
                }
            }
            print("📋 Saved \(savedItems.count) clipboard types")
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }

        print("✅ Paste command sent")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            let bundleId = frontmostApp?.bundleIdentifier ?? ""

            let problematicApps = [
                "com.apple.finder",
                "com.apple.dock",
                "com.apple.systempreferences"
            ]

            if problematicApps.contains(bundleId) {
                print("⚠️ Detected potential paste failure - showing history window")
                self?.showHistoryForPasteFailure()
            }

            if !preserveInClipboard {
                pasteboard.clearContents()
                for (type, data) in savedItems {
                    pasteboard.setData(data, forType: type)
                }
                print("♻️ Restored clipboard")
            }
        }
    }
    
    func showHistoryForPasteFailure() {
        // When paste fails in certain apps, show the history window
        // by simulating the Command+Option+A keyboard shortcut
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key code for 'A' is 0x00
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true) {
            keyDown.flags = [.maskCommand, .maskAlternate]
            keyDown.post(tap: .cghidEventTap)
        }
        
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false) {
            keyUp.flags = [.maskCommand, .maskAlternate]
            keyUp.post(tap: .cghidEventTap)
        }
        
        print("📚 Showing history window for paste failure recovery")
    }
    
    // MARK: - AudioTranscriptionManagerDelegate
    
    func audioLevelDidUpdate(db: Float) {
        updateStatusBarWithLevel(db: db)
    }
    
    func transcriptionDidStart() {
        startTranscriptionIndicator()
    }
    
    func transcriptionDidComplete(text: String) {
        stopTranscriptionIndicator()

        let autoPaste = TranscriptionPreferences.autoPaste
        let copyToClipboard = TranscriptionPreferences.copyToClipboard

        if autoPaste {
            pasteTextAtCursor(text, preserveInClipboard: copyToClipboard)
        } else if copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            print("📋 Copied transcription to clipboard")
        }

        showTranscriptionNotification(text)
    }
    
    func transcriptionDidFail(error: String) {
        stopTranscriptionIndicator()
        showTranscriptionError(error)
    }
    
    func recordingWasCancelled() {
        // Ensure any processing indicator is stopped
        stopTranscriptionIndicator()
        // Reset the status bar icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Assistant")
            button.title = ""
        }
        
        // Show notification
        let notification = NSUserNotification()
        notification.title = "Recording Cancelled"
        notification.informativeText = "Recording was cancelled"
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func recordingWasSkippedDueToSilence() {
        // Ensure any processing indicator is stopped
        stopTranscriptionIndicator()
        // Reset the status bar icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Assistant")
            button.title = ""
        }
        
        // Optionally show a subtle notification
        let notification = NSUserNotification()
        notification.title = "Recording Skipped"
        notification.informativeText = "Audio was too quiet to transcribe"
        NSUserNotificationCenter.default.deliver(notification)
    }
    
}

// Create and run the app
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular) // Show in dock and cmd+tab

// Set the app icon from our custom ICNS file
if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
   let iconImage = NSImage(contentsOf: iconURL) {
    app.applicationIconImage = iconImage
}

app.run()

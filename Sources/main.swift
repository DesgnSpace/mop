import Cocoa
import SwiftUI
import KeyboardShortcuts
import AVFoundation
import WhisperKit
import SharedModels
import Combine
import ApplicationServices
import UserNotifications
import Foundation
import os

private let logger = Logger(subsystem: "com.desgnspace.mop", category: "AppDelegate")

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
    private var recordingTimer: Timer?
    private var audioManager: AudioTranscriptionManager!
    private var streamingPlayer: GeminiStreamingPlayer?
    private var audioCollector: GeminiAudioCollector?
    private var isCurrentlyPlaying = false
    private var currentStreamingTask: Task<Void, Never>?
    private let updater = UpdaterController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        GeminiConfig.migrateFromEnvFile()
        initializeTTS()
        setupStatusBar()
        setupKeyboardShortcuts()
        setupAudioManager()
        setupModelObservers()
        loadModelsInBackground()
        requestAccessibilityPermission()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func requestAccessibilityPermission() {
        guard !AXIsProcessTrusted() else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private func initializeTTS() {
        guard GeminiConfig.isConfigured, #available(macOS 14.0, *) else {
            logger.warning("GEMINI_API_KEY not configured — use Settings to add your API key")
            return
        }

        streamingPlayer = GeminiStreamingPlayer(playbackSpeed: 1.15)
        audioCollector = GeminiAudioCollector(apiKey: GeminiConfig.apiKey)
        logger.info("Streaming TTS components initialized")
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MOP")
        statusItem.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Read Selected Text", action: #selector(handleReadSelectedTextToggle), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show History", action: #selector(showTranscriptionHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Paste Last Transcription", action: #selector(pasteLastTranscription), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let profileItem = NSMenuItem(title: "Cleanup Profile", action: nil, keyEquivalent: "")
        profileItem.submenu = buildProfileSubmenu()
        menu.addItem(profileItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About MOP", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Statistics...", action: #selector(showStats), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "License...", action: #selector(showLicense), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func buildProfileSubmenu() -> NSMenu {
        let submenu = NSMenu()
        MainActor.assumeIsolated {
            let store = CleanupProfileStore.shared
            let automaticItem = NSMenuItem(title: "Automatic", action: #selector(clearProfileOverride), keyEquivalent: "")
            automaticItem.state = store.manualOverrideID == nil ? .on : .off
            submenu.addItem(automaticItem)
            submenu.addItem(NSMenuItem.separator())
            for profile in store.profiles {
                let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.representedObject = profile.id.uuidString
                item.state = store.manualOverrideID == profile.id ? .on : .off
                submenu.addItem(item)
            }
        }
        return submenu
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString) else { return }
        MainActor.assumeIsolated { CleanupProfileStore.shared.setManualOverride(id) }
        statusItem.menu = createMenu()
    }

    @objc private func clearProfileOverride() {
        MainActor.assumeIsolated { CleanupProfileStore.shared.clearManualOverride() }
        statusItem.menu = createMenu()
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
        // Allow stopping a recording in progress regardless of license
        guard !audioManager.isRecording else {
            audioManager.toggleRecording()
            return
        }

        guard LicenseStore.shared.isAllowed else {
            openUnifiedWindow(tab: .license)
            return
        }

        stopTranscriptionIndicator()
        NSSound(named: "Tink")?.play()
        audioManager.toggleRecording()
    }

    private func setupAudioManager() {
        audioManager = AudioTranscriptionManager()
        audioManager.delegate = self
        NotificationCenter.default.addObserver(forName: .hudCancelTapped, object: nil, queue: .main) { [weak self] _ in
            self?.audioManager.cancelRecording()
        }
    }

    @MainActor
    private func loadModelsInBackground() {
        Task {
            await ModelStateManager.shared.checkDownloadedModels()
            logger.info("Model check completed at startup")

            switch ModelStateManager.shared.selectedEngine {
            case .whisperKit:
                if let selectedModel = ModelStateManager.shared.selectedModel {
                    _ = await ModelStateManager.shared.loadModel(selectedModel)
                }
            case .parakeet:
                await ModelStateManager.shared.loadParakeetModel()
            case .qwen3:
                await ModelStateManager.shared.loadQwen3Model()
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
                    ModelStateManager.shared.unloadQwen3Model()
                case .parakeet:
                    ModelStateManager.shared.unloadWhisperKitModel()
                    ModelStateManager.shared.unloadQwen3Model()
                case .qwen3:
                    ModelStateManager.shared.unloadWhisperKitModel()
                    ModelStateManager.shared.unloadParakeetModel()
                }
            }
    }

    @objc func openSettings() {
        openUnifiedWindow(tab: .models)
    }

    @objc func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc func showAbout() {
        AboutWindow.shared.show()
    }

    @objc func showLicense() {
        openUnifiedWindow(tab: .license)
    }

    @objc func showTranscriptionHistory() {
        openUnifiedWindow(tab: .history)
    }

    @objc func showStats() {
        openUnifiedWindow(tab: .statistics)
    }

    func applicationWillTerminate(_ notification: Notification) {
        currentStreamingTask?.cancel()
        streamingPlayer?.stopAudioEngine()
        audioManager?.cancelRecording()
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
                logger.info("Audio streaming cancelled")
            } catch {
                logger.error("Streaming TTS error: \(error)")
                showNotification(title: "Streaming TTS Error", text: error.localizedDescription)
            }
        }
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
        recordingTimer?.invalidate()
        recordingTimer = nil

        guard audioManager?.isRecording != true else { return }
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MOP")
        statusItem.button?.title = ""
    }

    func showTranscriptionNotification(_ text: String) {
        showNotification(title: "Transcription Complete", text: text, subtitle: "Inserted at cursor", sound: true)
    }

    func showTranscriptionError(_ message: String) {
        showNotification(title: "Transcription Error", text: message, sound: true)
    }

    @discardableResult
    func ensureAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func typeTextAtCursor(_ text: String) {
        guard !text.isEmpty else { return }

        func writeClipboard() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        guard ensureAccessibilityPermission() else {
            writeClipboard()
            showNotification(
                title: "Paste Blocked",
                text: "Accessibility not granted — text on clipboard, ⌘V to paste manually.",
                sound: true
            )
            return
        }

        logger.debug("Inserting '\(text.prefix(30))…' at cursor")

        if shouldPasteViaClipboard(text) {
            writeClipboard()
            simulateCommand(keyCode: 0x09, modifiers: .maskCommand)
            logger.debug("Inserted via Cmd+V")
            return
        }

        if insertViaAXAPI(text) {
            logger.debug("Inserted via AX API")
            return
        }

        insertViaUnicodeEvents(text)
        logger.debug("Inserted via CGEvent unicode")
    }

    private func isFrontmostAppTerminal() -> Bool {
        let terminalBundleIDs: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "org.alacritty",
            "io.alacritty",
            "net.kovidgoyal.kitty",
            "dev.warp.Warp-Stable",
            "co.zeit.hyper"
        ]
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return terminalBundleIDs.contains(bundleID)
    }

    private func shouldPasteViaClipboard(_ text: String) -> Bool {
        text.count > 500 || text.contains("\n") || isFrontmostAppTerminal()
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
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.flags = []
                chunk.withUnsafeBufferPointer { buf in
                    up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                up.post(tap: .cghidEventTap)
            }

            offset = end
        }
    }

    // MARK: - AudioTranscriptionManagerDelegate

    func recordingDidStart() {
        recordingTimer?.invalidate()
        var visible = true
        statusItem.button?.image = nil
        statusItem.button?.title = "● REC"
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            visible.toggle()
            self?.statusItem.button?.title = visible ? "● REC" : "  REC"
        }
        RecordingHUDController.shared.show()
    }

    func audioLevelDidUpdate(db: Float) {
        RecordingHUDController.shared.updateLevel(db)
    }

    func transcriptionDidStart() {
        NSSound(named: "Glass")?.play()
        startTranscriptionIndicator()
        RecordingHUDController.shared.updateState(.processing)
    }

    func transcriptionDidComplete(text: String) {
        NSSound(named: "Glass")?.play()
        stopTranscriptionIndicator()

        let cleanupActive = TranscriptionPreferences.useTextCleanup
        if !cleanupActive { RecordingHUDController.shared.hide() }

        if cleanupActive {
            if TranscriptionPreferences.copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                logger.debug("Raw transcription copied to clipboard (awaiting cleanup)")
            }
            return
        }

        if TranscriptionPreferences.autoPaste {
            typeTextAtCursor(text)
        }
        if TranscriptionPreferences.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            logger.debug("Transcription copied to clipboard")
        }

        showTranscriptionNotification(text)
    }

    func transcriptionDidCleanUp(text: String) {
        RecordingHUDController.shared.hide()
        if TranscriptionPreferences.autoPaste {
            typeTextAtCursor(text)
        }
        if TranscriptionPreferences.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            logger.debug("Cleaned transcription copied to clipboard")
        }

        showNotification(title: "Transcription Complete", text: text, subtitle: "Inserted at cursor", sound: true)
    }

    func transcriptionDidFail(error: String) {
        RecordingHUDController.shared.hide()
        stopTranscriptionIndicator()
        showTranscriptionError(error)
    }

    func recordingWasCancelled() {
        RecordingHUDController.shared.hide()
        stopTranscriptionIndicator()
        resetStatusBarIcon()
        showNotification(title: "Recording Cancelled", text: "Recording was cancelled")
    }

    func recordingWasSkippedDueToSilence() {
        RecordingHUDController.shared.hide()
        stopTranscriptionIndicator()
        resetStatusBarIcon()
        showNotification(title: "Recording Skipped", text: "Audio was too quiet to transcribe")
    }

    private func resetStatusBarIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MOP")
        statusItem.button?.title = ""
    }

    // MARK: - Helpers

    private func showNotification(title: String, text: String, subtitle: String? = nil, sound: Bool = false) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        if let subtitle { content.subtitle = subtitle }
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
        logger.debug("Saved \(self.savedItems.count) clipboard types")
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for (type, data) in savedItems {
            pasteboard.setData(data, forType: type)
        }
        logger.debug("Restored clipboard")
    }
}

// MARK: - App Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
   let iconImage = NSImage(contentsOf: iconURL) {
    app.applicationIconImage = iconImage
}

app.run()

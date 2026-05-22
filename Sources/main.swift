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
    static let pasteLastTranscription = Self("pasteLastTranscription")
    static let cleanupSelectedText = Self("cleanupSelectedText")
}

class AppDelegate: NSObject, NSApplicationDelegate, AudioTranscriptionManagerDelegate {
    var statusItem: NSStatusItem!
    private var unifiedWindow: UnifiedManagerWindow?
    private var modelCancellable: AnyCancellable?
    private var engineCancellable: AnyCancellable?
    private var parakeetVersionCancellable: AnyCancellable?
    private var transcriptionTimer: Timer?
    private var recordingTimer: Timer?
    private var windowWasVisibleBeforeRecording = false
    private var audioManager: AudioTranscriptionManager!
    private var liveTranscriptCommitted = ""
    private var liveInsertedText = ""
    private var lastOutputText: String?
    private let updater = UpdaterController()
    private var topLevelMenu: NSMenu!
    private var lastClickTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GeminiConfig.migrateFromEnvFile()
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

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MOP")
        topLevelMenu = createMenu()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc private func statusItemClicked() {
        let currentEvent = NSApp.currentEvent
        if currentEvent?.type == .rightMouseDown {
            showMenu()
            return
        }

        guard TranscriptionPreferences.singleClickToRecord else {
            showMenu()
            return
        }

        let now = Date()
        if let last = lastClickTime, now.timeIntervalSince(last) < 0.3 {
            lastClickTime = nil
            openSettings()
            return
        }
        lastClickTime = now
        toggleRecording()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.lastClickTime = nil
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        topLevelMenu.appearance = NSApp.effectiveAppearance
        topLevelMenu.popUp(positioning: nil, at: .zero, in: button)
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show History", action: #selector(showTranscriptionHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Paste Last Transcription", action: #selector(pasteLastTranscription), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let profileItem = NSMenuItem(title: "Cleanup Profile", action: nil, keyEquivalent: "")
        profileItem.submenu = buildProfileSubmenu()
        menu.addItem(profileItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About MOP", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.appearance = NSApp.effectiveAppearance
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
        topLevelMenu = createMenu()
    }

    @objc private func clearProfileOverride() {
        MainActor.assumeIsolated { CleanupProfileStore.shared.clearManualOverride() }
        topLevelMenu = createMenu()
    }

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.control]), for: .startRecording)
        KeyboardShortcuts.setShortcut(.init(.a, modifiers: [.command, .option]), for: .showHistory)
        KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .option]), for: .pasteLastTranscription)
        KeyboardShortcuts.setShortcut(.init(.c, modifiers: [.command, .option]), for: .cleanupSelectedText)

        KeyboardShortcuts.onKeyDown(for: .startRecording) { [weak self] in
            self?.toggleRecording()
        }

        KeyboardShortcuts.onKeyDown(for: .showHistory) { [weak self] in
            self?.showTranscriptionHistory()
        }

        KeyboardShortcuts.onKeyDown(for: .pasteLastTranscription) { [weak self] in
            self?.pasteLastTranscription()
        }

        KeyboardShortcuts.onKeyDown(for: .cleanupSelectedText) { [weak self] in
            self?.cleanupSelectedText()
        }
    }

    @objc func toggleRecording() {
        guard !audioManager.isRecording else {
            audioManager.toggleRecording()
            return
        }

        stopTranscriptionIndicator()
        NSSound(named: "Tink")?.play()
        if TranscriptionPreferences.useTextCleanup {
            CleanupConnectionWarmer.warmActiveDriver()
        }
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
                guard !TranscriptionPreferences.useLiveTranscription else {
                    logger.info("Skipping batch Parakeet preload because live transcription is enabled")
                    return
                }
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


    @objc func showTranscriptionHistory() {
        openUnifiedWindow(tab: .history)
    }

    @objc func showStats() {
        openUnifiedWindow(tab: .statistics)
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioManager?.cancelRecording()
    }

    private func openUnifiedWindow(tab: SidebarItem) {
        if unifiedWindow == nil {
            unifiedWindow = UnifiedManagerWindow()
        }
        unifiedWindow?.showWindow(tab: tab)
    }

    @objc func pasteLastTranscription() {
        let text = lastOutputText ?? TranscriptionHistory.shared.getEntries().first(where: { $0.tag == "cleaned" })?.text ?? TranscriptionHistory.shared.getEntries().first?.text
        guard let text else {
            showNotification(title: "No Transcription Available", text: "No transcription history found")
            return
        }

        typeTextAtCursor(text)
        showNotification(title: "Inserted Last Transcription", text: text.prefix(100) + (text.count > 100 ? "..." : ""))
    }

    @objc func cleanupSelectedText() {
        let prior = NSPasteboard.general.string(forType: .string)
        simulateCommand(keyCode: 0x08, modifiers: .maskCommand) // Cmd+C
        Thread.sleep(forTimeInterval: 0.12)
        guard let selected = NSPasteboard.general.string(forType: .string), !selected.isEmpty, selected != prior else {
            showNotification(title: "Cleanup", text: "No text selected")
            return
        }

        Task { @MainActor in
            let store = CleanupProfileStore.shared
            let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let activeProfile = store.resolveActive(forFrontmostBundleID: frontBundleID, urlHost: nil)
            let effectiveDriver = activeProfile.driverOverride ?? CleanupConfig.selectedDriver
            do {
                let result = try await CleanupDriverRegistry.driver(for: effectiveDriver).cleanup(selected, prompt: activeProfile.prompt)
                let cleaned = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return }
                TranscriptionHistory.shared.addEntry(selected, tag: "raw")
                TranscriptionHistory.shared.addEntry(cleaned, tag: "cleaned", profileName: activeProfile.name)
                typeTextAtCursor(cleaned)
                showNotification(title: "Cleanup Complete", text: cleaned.prefix(100) + (cleaned.count > 100 ? "..." : ""))
            } catch {
                showNotification(title: "Cleanup Failed", text: error.localizedDescription)
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

        guard ensureAccessibilityPermission() else {
            showNotification(
                title: "Typing Blocked",
                text: "Accessibility permission is required to type transcription text.",
                sound: true
            )
            return
        }

        logger.debug("Inserting '\(text.prefix(30))…' at cursor")

        if TranscriptionPreferences.insertionMode == .paste {
            pasteTextAtCursor(text)
            logger.debug("Inserted via Cmd+V")
            return
        }

        // .typing mode uses CGEvent unicode (same path as live transcription)
        insertViaUnicodeEvents(text)
        logger.debug("Inserted via CGEvent unicode")
    }

    private func pasteTextAtCursor(_ text: String) {
        let clipboard = ClipboardManager()
        clipboard.save()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        simulateCommand(keyCode: 0x09, modifiers: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if TranscriptionPreferences.clipboardBehavior == .restoreOriginal {
                clipboard.restore()
            }
        }
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
        let utf16 = Array(text.utf16)
        let chunkSize = 10
        DispatchQueue.global(qos: .userInitiated).async {
            let source = CGEventSource(stateID: .hidSystemState)
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
                usleep(1500)
                if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    up.flags = []
                    up.post(tap: .cgAnnotatedSessionEventTap)
                }
                usleep(2500)
                offset = end
            }
        }
    }

    private func combinedLiveTranscript(partial: String) -> String {
        guard !liveTranscriptCommitted.isEmpty else { return partial }
        if partial.hasPrefix(liveTranscriptCommitted) { return partial }
        return liveTranscriptCommitted + " " + partial
    }

    private func updateLiveInsertedText(_ text: String) {
        guard TranscriptionPreferences.autoPaste, TranscriptionPreferences.useLiveTranscription else { return }
        applyDiffReplace(text)
    }

    private func applyDiffReplace(_ text: String) {
        guard ensureAccessibilityPermission() else { return }
        guard text != liveInsertedText else { return }
        let prefix = commonPrefixLength(liveInsertedText, text)
        let oldSuffixCount = liveInsertedText.utf16.count - prefix
        if oldSuffixCount > 0 { sendBackspaces(count: oldSuffixCount) }
        let newSuffix = String(decoding: text.utf16.dropFirst(prefix), as: UTF16.self)
        insertViaUnicodeEvents(newSuffix)
        liveInsertedText = text
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs.utf16)
        let right = Array(rhs.utf16)
        let limit = min(left.count, right.count)
        var index = 0
        while index < limit, left[index] == right[index] {
            index += 1
        }
        return index
    }

    private func sendBackspaces(count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - AudioTranscriptionManagerDelegate

    func recordingDidStart() {
        liveTranscriptCommitted = ""
        liveInsertedText = ""
        recordingTimer?.invalidate()
        var visible = true
        statusItem.button?.image = nil
        statusItem.button?.title = "●"
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            visible.toggle()
            self?.statusItem.button?.title = visible ? "●" : " "
        }
        windowWasVisibleBeforeRecording = unifiedWindow?.window?.isVisible ?? false
        unifiedWindow?.window?.orderOut(nil)
        MainActor.assumeIsolated { RecordingHUDController.shared.show() }
    }

    func transcriptionDidUpdatePartial(text: String) {
        let display = combinedLiveTranscript(partial: text)
        MainActor.assumeIsolated { RecordingHUDController.shared.updatePartialText(display) }
        updateLiveInsertedText(display)
    }

    func transcriptionDidEndUtterance(text: String) {
        liveTranscriptCommitted = liveTranscriptCommitted.isEmpty ? text : liveTranscriptCommitted + " " + text
        MainActor.assumeIsolated { RecordingHUDController.shared.updatePartialText(liveTranscriptCommitted) }
        updateLiveInsertedText(liveTranscriptCommitted)
    }

    func audioLevelDidUpdate(db: Float) {
        MainActor.assumeIsolated { RecordingHUDController.shared.updateLevel(db) }
    }

    func transcriptionDidStart() {
        NSSound(named: "Glass")?.play()
        startTranscriptionIndicator()
        MainActor.assumeIsolated { RecordingHUDController.shared.updateState(.processing) }
    }

    func transcriptionDidComplete(text: String) {
        NSSound(named: "Glass")?.play()
        stopTranscriptionIndicator()

        let cleanupActive = TranscriptionPreferences.useTextCleanup
        if !cleanupActive { MainActor.assumeIsolated { RecordingHUDController.shared.hide() } }

        if cleanupActive {
            if TranscriptionPreferences.clipboardBehavior == .keepTranscription {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                logger.debug("Raw transcription copied to clipboard (awaiting cleanup)")
            }
            return
        }

        if TranscriptionPreferences.autoPaste {
            if !liveInsertedText.isEmpty {
                updateLiveInsertedText(text)
            } else {
                typeTextAtCursor(text)
            }
        }
        lastOutputText = text
        if TranscriptionPreferences.clipboardBehavior == .keepTranscription {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            logger.debug("Transcription copied to clipboard")
        }

        showTranscriptionNotification(text)
    }

    func transcriptionDidCleanUp(text: String) {
        lastOutputText = text
        MainActor.assumeIsolated { RecordingHUDController.shared.hide() }
        if TranscriptionPreferences.autoPaste {
            if !liveInsertedText.isEmpty {
                updateLiveInsertedText(text)
            } else {
                typeTextAtCursor(text)
            }
        }
        if TranscriptionPreferences.clipboardBehavior == .keepTranscription {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            logger.debug("Cleaned transcription copied to clipboard")
        }

        showNotification(title: "Transcription Complete", text: text, subtitle: "Inserted at cursor", sound: true)
    }

    func transcriptionDidFail(error: String) {
        MainActor.assumeIsolated { RecordingHUDController.shared.hide() }
        stopTranscriptionIndicator()
        showTranscriptionError(error)
    }

    func recordingWasCancelled() {
        MainActor.assumeIsolated { RecordingHUDController.shared.hide() }
        stopTranscriptionIndicator()
        resetStatusBarIcon()
        showNotification(title: "Recording Cancelled", text: "Recording was cancelled")
    }

    func recordingWasSkippedDueToSilence() {
        MainActor.assumeIsolated { RecordingHUDController.shared.hide() }
        stopTranscriptionIndicator()
        resetStatusBarIcon()
        showNotification(title: "Recording Skipped", text: "Audio was too quiet to transcribe")
    }

    private func resetStatusBarIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MOP")
        statusItem.button?.title = ""
        if windowWasVisibleBeforeRecording {
            windowWasVisibleBeforeRecording = false
            unifiedWindow?.window?.makeKeyAndOrderFront(nil)
        }
    }

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

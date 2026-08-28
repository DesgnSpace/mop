import SwiftUI
import SharedModels
import ServiceManagement

struct PreferencesView: View {
    @State private var autoPaste = TranscriptionPreferences.autoPaste
    @State private var clipboardBehavior = TranscriptionPreferences.clipboardBehavior
    @State private var insertionMode = TranscriptionPreferences.insertionMode
    @State private var showHUD = UserDefaults.standard.object(forKey: "showRecordingOverlay") as? Bool ?? true
    @State private var singleClickToRecord = TranscriptionPreferences.singleClickToRecord
    @State private var useLiveTranscription = TranscriptionPreferences.useLiveTranscription
    @State private var cleanupLiveTranscription = TranscriptionPreferences.cleanupLiveTranscription
    @State private var launchAtLogin = { () -> Bool in
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return SMAppService.mainApp.status == .enabled
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: MOPDesign.Spacing.sectionGap) {
                transcriptionBehaviorSection
                liveTranscriptionSection
                appBehaviorSection
            }
            .padding(MOPDesign.Spacing.settings)
            .background(MOPDesign.Surface.content)
        }
        .navigationTitle("Preferences")
    }

    private var transcriptionBehaviorSection: some View {
        MOPCard {
            MOPSectionHeader(title: "After Transcription", icon: "text.badge.checkmark")

            MOPToggleRow(
                title: "Auto-insert at cursor",
                description: "Insert transcribed text where your cursor is",
                isOn: $autoPaste,
                onChange: { TranscriptionPreferences.autoPaste = autoPaste }
            )

            Divider().padding(.leading, 52)

            MOPSettingsRow(title: "Insert method", description: "Type simulates direct input. Paste uses Cmd+V and restores your clipboard.") {
                Picker("Insert method", selection: $insertionMode) {
                    Text("Type").tag(TextInsertionMode.typing)
                    Text("Paste").tag(TextInsertionMode.paste)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: MOPDesign.Spacing.maxSegmented)
                .onChange(of: insertionMode) { _, newValue in
                    TranscriptionPreferences.insertionMode = newValue
                }
            }
            .disabled(!autoPaste)

            Divider().padding(.leading, 52)

            MOPSettingsRow(title: "Clipboard after inserting", description: clipboardBehavior == .restoreOriginal
                ? "Restore your previous clipboard after inserting."
                : "Keep the inserted text in your clipboard.") {
                Picker("Clipboard behavior", selection: $clipboardBehavior) {
                    Text("Restore previous").tag(ClipboardBehavior.restoreOriginal)
                    Text("Keep inserted").tag(ClipboardBehavior.keepTranscription)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: MOPDesign.Spacing.maxSegmented)
                .onChange(of: clipboardBehavior) { _, newValue in
                    TranscriptionPreferences.clipboardBehavior = newValue
                }

            }
            .disabled(!autoPaste)
        }
    }

    private var liveTranscriptionSection: some View {
        MOPCard {
            MOPSectionHeader(title: "Live Transcription", icon: "waveform.and.mic")

            MOPToggleRow(
                title: "Live transcription",
                description: "Show text as you speak. On Parakeet, downloads a streaming model (~120 MB) on first use. On other engines, uses Apple Speech (macOS 26+).",
                isOn: $useLiveTranscription,
                onChange: { TranscriptionPreferences.useLiveTranscription = useLiveTranscription }
            )

            Divider().padding(.leading, 52)

            MOPToggleRow(
                title: "Clean live transcription",
                description: "Clean each completed phrase before inserting it. Sends one cleanup request at a time; final cleanup still runs after recording.",
                isOn: $cleanupLiveTranscription,
                onChange: { TranscriptionPreferences.cleanupLiveTranscription = cleanupLiveTranscription }
            )
            .disabled(!useLiveTranscription)
        }
    }

    private var appBehaviorSection: some View {
        MOPCard {
            MOPSectionHeader(title: "App Behavior", icon: "gearshape.fill")

            MOPToggleRow(
                title: "Launch at login",
                description: "Start MOP automatically when you log in",
                isOn: $launchAtLogin,
                onChange: {
                    guard Bundle.main.bundleIdentifier != nil else { return }
                    do {
                        if launchAtLogin {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("Launch at login toggle failed: \(error)")
                    }
                }
            )
            .disabled(Bundle.main.bundleIdentifier == nil)

            Divider().padding(.leading, 52)

            MOPToggleRow(
                title: "Show recording overlay",
                description: "Display a floating pill while recording — visible in fullscreen apps",
                isOn: $showHUD,
                onChange: { UserDefaults.standard.set(showHUD, forKey: "showRecordingOverlay") }
            )

            Divider().padding(.leading, 52)

            MOPToggleRow(
                title: "Click to record",
                description: "Single-click the menu bar icon to start recording. Double-click for settings.",
                isOn: $singleClickToRecord,
                onChange: { TranscriptionPreferences.singleClickToRecord = singleClickToRecord }
            )
        }
    }
}

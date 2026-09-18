import SwiftUI
import SharedModels
import ServiceManagement

struct PreferencesView: View {
    @State private var autoPaste = TranscriptionPreferences.autoPaste
    @State private var clipboardBehavior = TranscriptionPreferences.clipboardBehavior
    @State private var insertionMode = TranscriptionPreferences.insertionMode
    @State private var recordingMode = TranscriptionPreferences.recordingMode
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
                recordingBehaviorSection
                transcriptionBehaviorSection
                liveTranscriptionSection
                appBehaviorSection
            }
            .padding(MOPDesign.Spacing.settings)
            .background(MOPDesign.Surface.content)
        }
        .navigationTitle("Preferences")
    }

    private var recordingBehaviorSection: some View {
        MOPCard {
            MOPSectionHeader(title: "Recording")

            MOPSettingsRow(title: "Recording shortcut") {
                Picker("Recording shortcut", selection: $recordingMode) {
                    Text("Press to start/stop").tag(RecordingMode.toggle)
                    Text("Press and hold").tag(RecordingMode.hold)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: MOPDesign.Spacing.maxSegmented)
                .onChange(of: recordingMode) { _, newValue in
                    TranscriptionPreferences.recordingMode = newValue
                }
            }
        }
    }

    private var transcriptionBehaviorSection: some View {
        MOPCard {
            MOPSectionHeader(title: "Text Insertion")

            MOPToggleRow(
                title: "Auto-insert at cursor",
                description: nil,
                isOn: $autoPaste,
                onChange: { TranscriptionPreferences.autoPaste = autoPaste }
            )

            MOPSettingsRow(title: "Insert method", description: "Type sends keystrokes; Paste uses the clipboard.") {
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

            MOPSettingsRow(title: "Clipboard after inserting", description: "Choose what remains on the clipboard.") {
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
            MOPSectionHeader(title: "Live Transcription")

            MOPToggleRow(
                title: "Live transcription",
                description: "Show text as you speak.",
                isOn: $useLiveTranscription,
                onChange: { TranscriptionPreferences.useLiveTranscription = useLiveTranscription }
            )

            MOPToggleRow(
                title: "Clean live transcription",
                description: "Fix each phrase before inserting it.",
                isOn: $cleanupLiveTranscription,
                onChange: { TranscriptionPreferences.cleanupLiveTranscription = cleanupLiveTranscription }
            )
            .disabled(!useLiveTranscription)
        }
    }

    private var appBehaviorSection: some View {
        MOPCard {
            MOPSectionHeader(title: "App Behavior")

            MOPToggleRow(
                title: "Launch at login",
                description: nil,
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

            MOPToggleRow(
                title: "Show recording overlay",
                description: "Show recording status while you speak.",
                isOn: $showHUD,
                onChange: { UserDefaults.standard.set(showHUD, forKey: "showRecordingOverlay") }
            )

            MOPToggleRow(
                title: "Click to record",
                description: "Click the menu bar icon to start; double-click to open settings.",
                isOn: $singleClickToRecord,
                onChange: { TranscriptionPreferences.singleClickToRecord = singleClickToRecord }
            )
        }
    }
}

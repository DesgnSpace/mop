import SwiftUI
import SharedModels
import ServiceManagement

struct PreferencesView: View {
    @State private var autoPaste = TranscriptionPreferences.autoPaste
    @State private var copyToClipboard = TranscriptionPreferences.copyToClipboard
    @State private var showHUD = UserDefaults.standard.object(forKey: "showRecordingOverlay") as? Bool ?? true
    @State private var launchAtLogin = { () -> Bool in
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return SMAppService.mainApp.status == .enabled
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                transcriptionBehaviorSection
                appBehaviorSection
            }
            .padding(20)
        }
        .navigationTitle("Preferences")
    }

    private var transcriptionBehaviorSection: some View {
        MOPCard {
            MOPSectionHeader(title: "After Transcription", icon: "text.badge.checkmark")

            MOPToggleRow(
                title: "Auto-insert at cursor",
                description: "Type transcribed text where your cursor is — no clipboard, no manual paste",
                isOn: $autoPaste,
                onChange: { TranscriptionPreferences.autoPaste = autoPaste }
            )

            Divider().padding(.leading, 52)

            MOPToggleRow(
                title: "Copy to clipboard",
                description: "Keep transcribed text in the clipboard after pasting",
                isOn: $copyToClipboard,
                onChange: { TranscriptionPreferences.copyToClipboard = copyToClipboard }
            )
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
        }
    }
}

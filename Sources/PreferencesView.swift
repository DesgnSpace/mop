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
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel(title: "After Transcription", icon: "text.badge.checkmark", color: .blue)

            toggleRow(
                title: "Auto-insert at cursor",
                description: "Type transcribed text where your cursor is — no clipboard, no manual paste",
                isOn: $autoPaste,
                color: .blue
            ) {
                TranscriptionPreferences.autoPaste = autoPaste
            }

            Divider().padding(.leading, 52)

            toggleRow(
                title: "Copy to clipboard",
                description: "Keep transcribed text in the clipboard after pasting",
                isOn: $copyToClipboard,
                color: .blue
            ) {
                TranscriptionPreferences.copyToClipboard = copyToClipboard
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var appBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel(title: "App Behavior", icon: "gearshape.fill", color: .gray)

            toggleRow(
                title: "Launch at login",
                description: "Start MOP automatically when you log in",
                isOn: $launchAtLogin,
                color: .gray
            ) {
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

            Divider().padding(.leading, 52)

            toggleRow(
                title: "Show recording overlay",
                description: "Display a floating pill while recording — visible in fullscreen apps",
                isOn: $showHUD,
                color: .gray
            ) {
                UserDefaults.standard.set(showHUD, forKey: "showRecordingOverlay")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func sectionLabel(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
            }

            Text(title)
                .font(.headline)
        }
    }

    private func toggleRow(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        color: Color,
        disabled: Bool = false,
        onChange: @escaping () -> Void
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(disabled ? .secondary : .primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(color)
        .disabled(disabled)
        .onChange(of: isOn.wrappedValue) { _, _ in onChange() }
        .padding(.leading, 8)
    }
}

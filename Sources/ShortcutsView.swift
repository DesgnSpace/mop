import Cocoa
import SwiftUI
import KeyboardShortcuts

struct ShortcutsView: View {
    var body: some View {
        ScrollView {
            MOPCard {
                MOPSectionHeader(title: "Keyboard Shortcuts", icon: "keyboard")

                VStack(spacing: 6) {
                    shortcutRow(
                        icon: "waveform",
                        title: "Voice Recording",
                        description: "Start/stop audio transcription",
                        name: .startRecording
                    )

                    Divider()

                    shortcutRow(
                        icon: "clock.fill",
                        title: "Show History",
                        description: "Show transcription history window",
                        name: .showHistory
                    )

                    Divider()

                    shortcutRow(
                        icon: "doc.on.clipboard.fill",
                        title: "Paste Last Transcription",
                        description: "Paste last transcription at cursor",
                        name: .pasteLastTranscription
                    )

                    Divider()

                    shortcutRow(
                        icon: "wand.and.stars",
                        title: "Cleanup Selected Text",
                        description: "Run active cleanup profile on selected text",
                        name: .cleanupSelectedText
                    )
                }
            }
            .padding(MOPDesign.Spacing.settings)
            .background(MOPDesign.Surface.content)
        }
        .navigationTitle("Shortcuts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Reset All") {
                    KeyboardShortcuts.reset(.startRecording, .showHistory, .pasteLastTranscription, .cleanupSelectedText)
                }
            }
        }
    }

    private func shortcutRow(
        icon: String,
        title: String,
        description: String,
        name: KeyboardShortcuts.Name
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: MOPDesign.Radius.small)
                    .fill(MOPDesign.Surface.selection)
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            KeyboardShortcuts.Recorder(for: name)
                .frame(width: 140)
        }
        .padding(.vertical, 6)
    }
}

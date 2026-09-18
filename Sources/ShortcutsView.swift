import Cocoa
import SwiftUI
import KeyboardShortcuts

struct ShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: MOPDesign.Spacing.denseRow) {
                shortcutRow(title: "Record and transcribe", name: .startRecording)
                shortcutRow(title: "Show history", name: .showHistory)
                shortcutRow(title: "Paste last transcription", name: .pasteLastTranscription)
                shortcutRow(title: "Clean selected text", name: .cleanupSelectedText)
            }
            .padding(MOPDesign.Spacing.settings)
            .background(MOPDesign.Surface.content)
        }
        .navigationTitle("Shortcuts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Reset Shortcuts") {
                    KeyboardShortcuts.reset(.startRecording, .showHistory, .pasteLastTranscription, .cleanupSelectedText)
                }
            }
        }
    }

    private func shortcutRow(
        title: String,
        name: KeyboardShortcuts.Name
    ) -> some View {
        MOPSettingsRow(title: title) {
            KeyboardShortcuts.Recorder(for: name)
                .frame(width: 140)
        }
    }
}

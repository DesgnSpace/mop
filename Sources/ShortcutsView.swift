import Cocoa
import SwiftUI
import KeyboardShortcuts

struct ShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                shortcutRow(
                    icon: "waveform",
                    title: "Voice Recording",
                    description: "Start/stop audio transcription",
                    name: .startRecording,
                    color: .blue
                )

                shortcutRow(
                    icon: "speaker.wave.2.fill",
                    title: "Read Selected Text",
                    description: "Read selected text aloud with streaming TTS",
                    name: .readSelectedText,
                    color: .green
                )

                shortcutRow(
                    icon: "clock.fill",
                    title: "Show History",
                    description: "Show transcription history window",
                    name: .showHistory,
                    color: .orange
                )

                shortcutRow(
                    icon: "doc.on.clipboard.fill",
                    title: "Paste Last Transcription",
                    description: "Paste last transcription at cursor",
                    name: .pasteLastTranscription,
                    color: .teal
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .navigationTitle("Shortcuts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Reset All") {
                    KeyboardShortcuts.reset(.startRecording, .showHistory, .readSelectedText, .pasteLastTranscription)
                }
            }
        }
    }

    private func shortcutRow(
        icon: String,
        title: String,
        description: String,
        name: KeyboardShortcuts.Name,
        color: Color
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
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
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.03))
        )
    }
}

class ShortcutsViewController: NSViewController {
    override func loadView() {
        let hostingView = NSHostingView(rootView: ShortcutsView())
        self.view = hostingView
    }
}

import Cocoa
import SwiftUI
import KeyboardShortcuts

struct ShortcutsView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Modern Header
            HStack(spacing: 12) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard Shortcuts")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Customize shortcuts for each action")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

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
                        icon: "text.bubble.fill",
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

            Divider()

            HStack {
                Text("Click a shortcut field and press the desired key combination to change it.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Reset All") {
                    KeyboardShortcuts.reset(.startRecording, .showHistory, .readSelectedText, .pasteLastTranscription)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 600, height: 450)
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
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 450)
        self.view = hostingView
    }
}
import SwiftUI
import SharedModels

struct PreferencesView: View {
    @State private var autoPaste = TranscriptionPreferences.autoPaste
    @State private var copyToClipboard = TranscriptionPreferences.copyToClipboard
    @State private var useGeminiCleanup = TranscriptionPreferences.useGeminiTextCleanup
    @State private var cleanupPrompt = TranscriptionPreferences.cleanupPrompt

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                transcriptionBehaviorSection
                geminiSection
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

    private var geminiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel(title: "Gemini Text Cleanup", icon: "sparkles", color: .purple)

            VStack(alignment: .leading, spacing: 12) {
                toggleRow(
                    title: "Grammar cleanup",
                    description: GeminiConfig.isConfigured
                        ? "Fix grammar and punctuation using Gemini after transcription"
                        : "Requires a Gemini API key — configure it in Models",
                    isOn: $useGeminiCleanup,
                    color: .purple,
                    disabled: !GeminiConfig.isConfigured
                ) {
                    TranscriptionPreferences.useGeminiTextCleanup = useGeminiCleanup
                }

                if useGeminiCleanup && GeminiConfig.isConfigured {
                    promptEditor
                }
            }
            .padding(.leading, 8)

            if !GeminiConfig.isConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Text("Add your Gemini API key in the Models section to enable this feature.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
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

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cleanup prompt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reset") {
                    cleanupPrompt = TranscriptionPreferences.defaultCleanupPrompt
                    TranscriptionPreferences.cleanupPrompt = cleanupPrompt
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }

            TextEditor(text: $cleanupPrompt)
                .font(.body)
                .frame(minHeight: 72, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .onChange(of: cleanupPrompt) { _, newValue in
                    TranscriptionPreferences.cleanupPrompt = newValue
                }
        }
        .padding(.top, 4)
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

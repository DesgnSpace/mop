import SwiftUI
import SharedModels

struct PreferencesView: View {
    @State private var autoPaste = TranscriptionPreferences.autoPaste
    @State private var copyToClipboard = TranscriptionPreferences.copyToClipboard
    @State private var useGeminiCleanup = TranscriptionPreferences.useGeminiTextCleanup
    @State private var cleanupPrompt = TranscriptionPreferences.cleanupPrompt

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    transcriptionBehaviorSection
                    geminiSection
                }
                .padding(20)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 28))
                .foregroundStyle(.linearGradient(
                    colors: [.gray, .secondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            VStack(alignment: .leading, spacing: 4) {
                Text("Preferences")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Customize transcription behavior")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var transcriptionBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel(title: "After Transcription", icon: "text.badge.checkmark", color: .blue)

            toggleRow(
                title: "Auto-paste at cursor",
                description: "Paste transcribed text where your cursor is",
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cleanup prompt")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextEditor(text: $cleanupPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 80, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .onChange(of: cleanupPrompt) { _ in
                            TranscriptionPreferences.cleanupPrompt = cleanupPrompt
                        }

                    HStack {
                        Button("Reset to default") {
                            cleanupPrompt = TranscriptionPreferences.defaultCleanupPrompt
                            TranscriptionPreferences.cleanupPrompt = cleanupPrompt
                        }
                        .buttonStyle(.link)
                        .font(.caption)

                        Spacer()
                    }
                }
                .padding(.leading, 52)
            }

            if !GeminiConfig.isConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("Add your Gemini API key in the Models section to enable this feature.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 52)
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
                    .foregroundColor(color)
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
                    .foregroundColor(disabled ? .secondary : .primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(color)
        .disabled(disabled)
        .onChange(of: isOn.wrappedValue) { _ in onChange() }
        .padding(.leading, 8)
    }
}

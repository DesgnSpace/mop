import SwiftUI
import SharedModels

struct PreferencesView: View {
    @State private var autoPaste = TranscriptionPreferences.autoPaste
    @State private var copyToClipboard = TranscriptionPreferences.copyToClipboard
    @State private var useGeminiCleanup = TranscriptionPreferences.useGeminiTextCleanup
    @State private var cleanupPrompt = TranscriptionPreferences.cleanupPrompt
    @State private var cleanupTimeout = TranscriptionPreferences.geminiCleanupTimeout
    @ObservedObject private var callLog = GeminiCallLog.shared

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

                    Stepper(value: $cleanupTimeout, in: 5...60, step: 1) {
                        Text("Request timeout: \(cleanupTimeout)s")
                            .font(.subheadline)
                    }
                    .padding(.top, 8)
                    .onChange(of: cleanupTimeout) { _, newValue in
                        TranscriptionPreferences.geminiCleanupTimeout = newValue
                    }
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

            if !callLog.entries.isEmpty {
                activityLog
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

    private var activityLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { GeminiCallLog.shared.clear() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 3) {
                ForEach(callLog.entries as [GeminiCallLog.Entry], id: \.id) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(entry.success ? Color.green : Color.red)
                            .frame(width: 6, height: 6)

                        Text(relativeTime(entry.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)

                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(entry.success ? .primary : Color.red)
                            .lineLimit(1)

                        Spacer()
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .padding(.top, 4)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
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

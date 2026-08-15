import SwiftUI

struct StatsView: View {
    @ObservedObject private var stats = TranscriptionStats.shared
    @ObservedObject private var history = TranscriptionHistory.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                MOPCard {
                    MOPSectionHeader(title: "Usage", icon: "chart.bar.fill")

                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(stats.totalTranscriptions)")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("Total Transcriptions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    Divider()

                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: "clock.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(history.entries.count)")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("Saved in History")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }

                if let newest = history.entries.first {
                    lastTranscriptionCard(entry: newest)
                }
            }
            .padding(20)
        }
        .navigationTitle("Statistics")
    }

    private func lastTranscriptionCard(entry: TranscriptionEntry) -> some View {
        MOPCard {
            HStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Last Transcription")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(relativeDate(entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DeveloperResponseView(text: entry.text)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

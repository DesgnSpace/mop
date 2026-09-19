import SwiftUI

struct StatsView: View {
    @ObservedObject private var stats = TranscriptionStats.shared
    @ObservedObject private var history = TranscriptionHistory.shared

    var body: some View {
        ScrollView {
            VStack(spacing: MOPDesign.Spacing.sectionGap) {
                MOPCard {
                    MOPSectionHeader(title: "Usage")

                    HStack(alignment: .top, spacing: MOPDesign.Spacing.sectionGap) {
                        statBlock(value: "\(stats.totalTranscriptions)", label: "Total transcriptions")
                        statBlock(value: "\(history.entries.count)", label: "Saved in history")
                    }
                }

                if let newest = history.entries.first {
                    lastTranscriptionCard(entry: newest)
                } else {
                    emptyHistoryCard
                }
            }
            .padding(MOPDesign.Spacing.settings)
            .background(MOPDesign.Surface.content)
        }
        .navigationTitle("Statistics")
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: MOPDesign.Spacing.denseRow) {
            Text(value)
                .font(MOPDesign.Typography.statValue)
                .foregroundStyle(.primary)
            Text(label)
                .font(MOPDesign.Typography.helper)
                .foregroundStyle(MOPDesign.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lastTranscriptionCard(entry: TranscriptionEntry) -> some View {
        MOPCard {
            HStack {
                Text("Latest transcription")
                    .font(MOPDesign.Typography.sectionHeader)
                Spacer()
                Text(relativeDate(entry.timestamp))
                    .font(MOPDesign.Typography.technical)
                    .foregroundStyle(MOPDesign.Text.tertiary)
            }

            DeveloperResponseView(text: entry.text)
        }
    }

    private var emptyHistoryCard: some View {
        MOPCard {
            MOPSectionHeader(title: "Latest transcription")
            Text("Start recording to see your latest transcription here.")
                .font(MOPDesign.Typography.helper)
                .foregroundStyle(MOPDesign.Text.tertiary)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

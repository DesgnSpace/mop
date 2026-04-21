import SwiftUI

struct StatsView: View {
    @ObservedObject private var stats = TranscriptionStats.shared
    @ObservedObject private var history = TranscriptionHistory.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    statCard(
                        value: "\(stats.totalTranscriptions)",
                        label: "Total Transcriptions",
                        icon: "mic.fill",
                        color: .blue
                    )

                    statCard(
                        value: "\(history.entries.count)",
                        label: "Saved in History",
                        icon: "clock.fill",
                        color: .orange
                    )

                    if let newest = history.entries.first {
                        lastTranscriptionCard(entry: newest)
                    }
                }
                .padding(20)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 28))
                .foregroundStyle(.linearGradient(
                    colors: [.green, .teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            VStack(alignment: .leading, spacing: 4) {
                Text("Statistics")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Usage overview")
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

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.12))
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
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

    private func lastTranscriptionCard(entry: TranscriptionEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Last Transcription")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Text(relativeDate(entry.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(entry.text)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

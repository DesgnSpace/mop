import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject private var history = TranscriptionHistory.shared
    @State private var searchText = ""
    @State private var copiedID: UUID?
    @State private var showingClearAlert = false

    private var filteredEntries: [TranscriptionEntry] {
        guard !searchText.isEmpty else { return history.entries }
        return history.entries.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if filteredEntries.isEmpty {
                emptyState
            } else {
                entryList
            }

            Divider()

            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.linearGradient(
                    colors: [.orange, .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(history.entries.isEmpty ? "No transcriptions yet" : "\(history.entries.count) transcriptions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(searchText.isEmpty ? "No transcriptions yet" : "No results for \"\(searchText)\"")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        List {
            ForEach(filteredEntries) { entry in
                entryRow(entry)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
    }

    private func entryRow(_ entry: TranscriptionEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Text(formatDate(entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let tag = entry.tag {
                        tagBadge(tag)
                    }
                }
            }

            Spacer()

            VStack(spacing: 6) {
                Button {
                    copyToClipboard(entry.text)
                    copiedID = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedID == entry.id { copiedID = nil }
                    }
                } label: {
                    Label(copiedID == entry.id ? "Copied" : "Copy", systemImage: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .frame(width: 70)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(copiedID == entry.id ? .green : .accentColor)

                Button(role: .destructive) {
                    deleteEntry(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                        .frame(width: 70)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func tagBadge(_ tag: String) -> some View {
        Text(tag.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagColor(tag).opacity(0.15))
            .foregroundColor(tagColor(tag))
            .cornerRadius(4)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "cleaned": return .green
        case "raw": return .orange
        default: return .secondary
        }
    }

    private var footer: some View {
        HStack {
            Button("Clear All", role: .destructive) {
                showingClearAlert = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(history.entries.isEmpty)

            Spacer()

            Text("\(filteredEntries.count) of \(history.entries.count) shown")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .alert("Clear History", isPresented: $showingClearAlert) {
            Button("Clear", role: .destructive) {
                TranscriptionHistory.shared.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all transcription history.")
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func deleteEntry(_ entry: TranscriptionEntry) {
        guard let index = history.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        TranscriptionHistory.shared.deleteEntry(at: index)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "h:mm a"
            return "Yesterday \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
}

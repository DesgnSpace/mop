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
        Group {
            if filteredEntries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search transcriptions")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear All", role: .destructive) {
                    showingClearAlert = true
                }
                .disabled(history.entries.isEmpty)
            }
            ToolbarItem(placement: .status) {
                Text("\(filteredEntries.count) of \(history.entries.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Clear History", isPresented: $showingClearAlert) {
            Button("Clear", role: .destructive) {
                TranscriptionHistory.shared.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all transcription history.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            searchText.isEmpty ? "No Transcriptions" : "No Results",
            systemImage: searchText.isEmpty ? "clock" : "magnifyingglass",
            description: Text(searchText.isEmpty
                ? "Transcriptions will appear here after recording."
                : "No results for \"\(searchText)\".")
        )
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
                DeveloperResponseView(text: entry.text)

                HStack(spacing: 6) {
                    Text(formatDate(entry.timestamp))
                        .font(MOPDesign.machineFont())
                        .foregroundStyle(.secondary)

                    if let tag = entry.tag {
                        tagBadge(tag)
                    }

                    if let model = entry.model {
                        Text(model)
                            .font(MOPDesign.machineFont(size: 9))
                            .foregroundStyle(MOPDesign.Text.tertiary)
                    }

                    if let profile = entry.profileName {
                        Text(profile)
                            .font(MOPDesign.machineFont(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(MOPDesign.Surface.selection)
                            .foregroundStyle(.secondary)
                            .clipShape(.rect(cornerRadius: 4))
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
                        .font(MOPDesign.machineFont())
                        .frame(width: 70)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(copiedID == entry.id ? Color.green : Color.accentColor)

                Button(role: .destructive) {
                    deleteEntry(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 70)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }

    private func tagBadge(_ tag: String) -> some View {
        Text(tag.uppercased())
            .font(MOPDesign.machineFont(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(MOPDesign.Surface.selection)
            .foregroundStyle(tagColor(tag))
            .clipShape(.rect(cornerRadius: 4))
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "cleaned": return MOPDesign.Semantic.success
        case "raw": return MOPDesign.Semantic.warning
        default: return MOPDesign.Text.tertiary
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
            return "Today  \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "h:mm a"
            return "Yesterday  \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
}

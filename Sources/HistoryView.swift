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
        .background(MOPDesign.Surface.content)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search transcriptions")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Delete history", role: .destructive) {
                    showingClearAlert = true
                }
                .disabled(history.entries.isEmpty)
            }
            ToolbarItem(placement: .status) {
                Text("\(filteredEntries.count) of \(history.entries.count)")
                    .font(MOPDesign.Typography.technical)
                    .foregroundStyle(MOPDesign.Text.tertiary)
            }
        }
        .alert("Delete history?", isPresented: $showingClearAlert) {
            Button("Delete history", role: .destructive) {
                TranscriptionHistory.shared.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all transcription history. You can't undo this.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: MOPDesign.Spacing.output) {
            ContentUnavailableView(
                searchText.isEmpty ? "No transcriptions" : "No results",
                systemImage: searchText.isEmpty ? "clock" : "magnifyingglass",
                description: Text(searchText.isEmpty
                    ? "Start recording to see your transcriptions here."
                    : "No results for \"\(searchText)\".")
            )

            if searchText.isEmpty {
                Button("Start recording") {
                    NSApp.sendAction(#selector(AppDelegate.toggleRecording), to: nil, from: nil)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
            }
        }
    }

    private var entryList: some View {
        List {
            ForEach(filteredEntries) { entry in
                entryRow(entry)
                    .listRowInsets(EdgeInsets(top: 0, leading: MOPDesign.Spacing.detailHorizontal, bottom: 0, trailing: MOPDesign.Spacing.detailHorizontal))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MOPDesign.Surface.content)
    }

    private func entryRow(_ entry: TranscriptionEntry) -> some View {
        HStack(alignment: .top, spacing: MOPDesign.Spacing.output) {
            VStack(alignment: .leading, spacing: MOPDesign.Spacing.denseRow) {
                DeveloperResponseView(text: entry.text)

                HStack(spacing: 6) {
                    Text(formatDate(entry.timestamp))
                        .font(MOPDesign.Typography.technical)
                        .foregroundStyle(MOPDesign.Text.tertiary)

                    if let tag = entry.tag {
                        tagBadge(tag)
                    }

                    if let model = entry.model {
                        Text(model)
                            .font(MOPDesign.Typography.technical)
                            .foregroundStyle(MOPDesign.Text.tertiary)
                    }

                    if let profile = entry.profileName {
                        Text(profile)
                            .font(MOPDesign.Typography.technicalEmphasis)
                            .foregroundStyle(MOPDesign.Text.tertiary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Button {
                    copyToClipboard(entry.text)
                    copiedID = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedID == entry.id { copiedID = nil }
                    }
                } label: {
                    Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copiedID == entry.id ? MOPDesign.Semantic.success : MOPDesign.Text.tertiary)
                .help(copiedID == entry.id ? "Copied" : "Copy")
                .accessibilityLabel(copiedID == entry.id ? "Copied" : "Copy")

                Button(role: .destructive) {
                    deleteEntry(entry)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MOPDesign.Text.tertiary)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
        }
        .padding(.vertical, MOPDesign.Spacing.settingsRow)
    }

    private func tagBadge(_ tag: String) -> some View {
        Text(tag.uppercased())
            .font(MOPDesign.Typography.technicalEmphasis)
            .foregroundStyle(tagColor(tag))
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

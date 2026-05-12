import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case models = "Models"
    case shortcuts = "Shortcuts"
    case history = "History"
    case statistics = "Statistics"
    case audioDevices = "Audio Devices"
    case cleanup = "Cleanup"
    case preferences = "Preferences"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .models: return "waveform.circle"
        case .shortcuts: return "keyboard"
        case .history: return "clock"
        case .statistics: return "chart.bar"
        case .audioDevices: return "speaker.wave.2"
        case .cleanup: return "wand.and.sparkles"
        case .preferences: return "slider.horizontal.3"
        }
    }
}

@Observable
class NavigationState {
    var selectedItem: SidebarItem? = .models
}

struct SidebarNavigationView: View {
    @Bindable var navigationState: NavigationState

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $navigationState.selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 175, ideal: 190, max: 220)
            .listStyle(.sidebar)
            .navigationTitle("Super Voice")
            .safeAreaInset(edge: .bottom) {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigationState.selectedItem {
        case .models:
            SettingsView()
        case .shortcuts:
            ShortcutsView()
        case .history:
            HistoryView()
        case .statistics:
            StatsView()
        case .audioDevices:
            AudioDevicesView()
        case .cleanup:
            CleanupView()
        case .preferences:
            PreferencesView()
        case .none:
            ContentUnavailableView("Select a section", systemImage: "sidebar.left")
        }
    }
}

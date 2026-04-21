import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case models = "Models"
    case shortcuts = "Shortcuts"
    case history = "History"
    case statistics = "Statistics"
    case audioDevices = "Audio Devices"
    case preferences = "Preferences"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .models: return "waveform.circle"
        case .shortcuts: return "keyboard"
        case .history: return "clock"
        case .statistics: return "chart.bar"
        case .audioDevices: return "speaker.wave.2"
        case .preferences: return "slider.horizontal.3"
        }
    }
}

class NavigationState: ObservableObject {
    @Published var selectedItem: SidebarItem? = .models
}

struct SidebarNavigationView: View {
    @ObservedObject var navigationState: NavigationState

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $navigationState.selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 175, ideal: 190, max: 220)
            .listStyle(.sidebar)
            .navigationTitle("Super Voice")
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        case .preferences:
            PreferencesView()
        case .none:
            Text("Select a section")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

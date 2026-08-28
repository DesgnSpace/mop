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

}

@Observable
class NavigationState {
    var selectedItem: SidebarItem? = .models
}

struct SidebarNavigationView: View {
    @Bindable var navigationState: NavigationState

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                        ForEach([SidebarItem.models, .history, .statistics]) { item in
                        sidebarRow(item)
                    }
                } header: {
                    sidebarHeader("Workspace")
                }

                Section {
                    ForEach([SidebarItem.cleanup, .shortcuts, .audioDevices, .preferences]) { item in
                        sidebarRow(item)
                    }
                } header: {
                    sidebarHeader("Configure")
                }
            }
            .background(MOPDesign.Surface.sidebar)
            .navigationSplitViewColumnWidth(min: 175, ideal: 190, max: 220)
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(MOPDesign.Surface.hairline)
                    .frame(width: 1)
            }
            .navigationTitle("MOP")
            .safeAreaInset(edge: .bottom) {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(MOPDesign.Typography.technical)
                    .foregroundStyle(MOPDesign.Text.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MOPDesign.Spacing.panel)
                    .padding(.vertical, 10)
            }
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MOPDesign.Surface.content)
        }
        .navigationSplitViewStyle(.balanced)
        .background(MOPDesign.Surface.content)
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Button {
            navigationState.selectedItem = item
        } label: {
            Text(item.rawValue)
                .font(MOPDesign.Typography.rowLabel)
                .foregroundStyle(navigationState.selectedItem == item ? .primary : MOPDesign.Text.deEmphasized)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background {
                    if navigationState.selectedItem == item {
                        RoundedRectangle(cornerRadius: MOPDesign.Radius.small)
                            .fill(MOPDesign.Surface.selection)
                    }
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowBackground(Color.clear)
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(MOPDesign.Typography.technicalEmphasis)
            .tracking(0.6)
            .foregroundStyle(MOPDesign.Text.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, title == "Configure" ? 18 : 8)
            .padding(.bottom, 4)
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

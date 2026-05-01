import Cocoa
import SwiftUI

class UnifiedManagerWindow: NSWindowController {
    private let navigationState = NavigationState()

    override init(window: NSWindow?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MOP"
        window.minSize = NSSize(width: 680, height: 480)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

        super.init(window: window)

        let rootView = SidebarNavigationView(navigationState: navigationState)
        window.contentViewController = NSHostingController(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow(tab: SidebarItem? = nil) {
        if let tab = tab {
            navigationState.selectedItem = tab
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

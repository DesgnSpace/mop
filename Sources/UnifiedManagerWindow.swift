import Cocoa
import SwiftUI

class UnifiedManagerWindow: NSWindowController, NSWindowDelegate {
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

        window.delegate = self
        let rootView = SidebarNavigationView(navigationState: navigationState)
        window.contentViewController = NSHostingController(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hasBeenShown = false

    func showWindow(tab: SidebarItem? = nil) {
        if let tab = tab {
            navigationState.selectedItem = tab
        }

        if !hasBeenShown {
            window?.center()
            hasBeenShown = true
        }
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

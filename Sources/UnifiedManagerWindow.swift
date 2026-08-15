import Cocoa
import SwiftUI

class UnifiedManagerWindow: NSWindowController {
    private let navigationState = NavigationState()

    override init(window: NSWindow?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MOP"
        window.minSize = NSSize(width: 760, height: 520)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.15, alpha: 1)
                : NSColor(calibratedWhite: 0.98, alpha: 1)
        }

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


}

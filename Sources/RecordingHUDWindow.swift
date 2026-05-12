import AppKit
import SwiftUI

final class RecordingHUDWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 52),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
    }

    func positionAtTopCenter() {
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let winSize = frame.size
        let x = screenFrame.midX - winSize.width / 2
        let y = screenFrame.maxY - winSize.height - 16
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

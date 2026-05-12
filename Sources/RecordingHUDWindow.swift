import AppKit
import SwiftUI

final class RecordingHUDWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 92),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { false }

    override func mouseDown(with event: NSEvent) {
        performDrag(with: event)
    }

    func positionAtBottomCenter() {
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let winSize = frame.size
        let x = visibleFrame.maxX - winSize.width - 32
        let y = visibleFrame.minY + 48
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

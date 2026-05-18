import AppKit
import SwiftUI

private let hudOriginXKey = "recordingHUDOriginX"
private let hudOriginYKey = "recordingHUDOriginY"

final class RecordingHUDWindow: NSWindow {
    private var isProgrammaticMove = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 60),
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    @objc private func windowDidMove() {
        guard !isProgrammaticMove else { return }
        UserDefaults.standard.set(Double(frame.origin.x), forKey: hudOriginXKey)
        UserDefaults.standard.set(Double(frame.origin.y), forKey: hudOriginYKey)
    }

    override var canBecomeKey: Bool { false }

    override func mouseDown(with event: NSEvent) {
        performDrag(with: event)
    }

    func applySavedOrPositionAtBottomCenter() {
        let ud = UserDefaults.standard
        if ud.object(forKey: hudOriginXKey) != nil, ud.object(forKey: hudOriginYKey) != nil {
            let saved = NSPoint(x: ud.double(forKey: hudOriginXKey), y: ud.double(forKey: hudOriginYKey))
            let winRect = NSRect(origin: saved, size: frame.size)
            let onScreen = NSScreen.screens.contains(where: { $0.visibleFrame.intersects(winRect) })
            if onScreen {
                isProgrammaticMove = true
                setFrameOrigin(saved)
                isProgrammaticMove = false
                return
            }
        }
        positionAtBottomCenter()
    }

    func positionAtBottomCenter() {
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let winSize = frame.size
        let x = visibleFrame.maxX - winSize.width - 32
        let y = visibleFrame.minY + 48
        isProgrammaticMove = true
        setFrameOrigin(NSPoint(x: x, y: y))
        isProgrammaticMove = false
    }
}

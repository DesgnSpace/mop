import AppKit
import SwiftUI
import Combine

enum HUDState { case recording, processing }

@Observable
@MainActor
final class RecordingHUDController {
    static let shared = RecordingHUDController()

    var state: HUDState = .recording
    var audioLevel: Float = -60
    var elapsed: TimeInterval = 0
    var partialText: String = ""

    private var window: RecordingHUDWindow?
    private var hostingController: NSHostingController<RecordingHUDView>?
    private var timer: AnyCancellable?
    private var startDate: Date?

    private init() {}

    // MARK: - Public API (safe to call from any thread)

    nonisolated func show() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self._show() } }
    }

    nonisolated func hide() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self._hide() } }
    }

    nonisolated func updateLevel(_ db: Float) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.audioLevel = db } }
    }

    nonisolated func updateState(_ newState: HUDState) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.state = newState } }
    }

    nonisolated func updatePartialText(_ text: String) {
        DispatchQueue.main.async { MainActor.assumeIsolated {
            let wasEmpty = self.partialText.isEmpty
            self.partialText = text
            if wasEmpty != text.isEmpty {
                self._resizeWindow(hasText: !text.isEmpty)
            }
        }}
    }

    func cancel() {
        NotificationCenter.default.post(name: .hudCancelTapped, object: nil)
    }

    // MARK: - Private main-actor implementations

    private func _show() {
        guard UserDefaults.standard.object(forKey: "showRecordingOverlay") as? Bool ?? true else { return }

        state = .recording
        audioLevel = -60
        elapsed = 0
        partialText = ""
        startDate = Date()

        if window == nil { window = RecordingHUDWindow() }
        let hc = NSHostingController(rootView: RecordingHUDView(controller: self))
        hc.view.frame = NSRect(x: 0, y: 0, width: 340, height: 92)
        hc.view.wantsLayer = true
        hc.view.layer?.backgroundColor = NSColor.clear.cgColor
        hc.view.layer?.isOpaque = false
        hostingController = hc
        window?.contentViewController = hc
        window?.setContentSize(NSSize(width: 340, height: 92))
        window?.applySavedOrPositionAtBottomCenter()
        window?.orderFrontRegardless()

        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
    }

    private func _hide() {
        timer?.cancel()
        timer = nil
        startDate = nil
        partialText = ""
        window?.orderOut(nil)
    }

    private func _resizeWindow(hasText: Bool) {
        let height: CGFloat = hasText ? 180 : 92
        let size = NSSize(width: 340, height: height)
        hostingController?.view.frame.size = size
        window?.setContentSize(size)
    }
}

extension Notification.Name {
    static let hudCancelTapped = Notification.Name("hudCancelTapped")
}

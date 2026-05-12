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

    private var window: RecordingHUDWindow?
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

    func cancel() {
        NotificationCenter.default.post(name: .hudCancelTapped, object: nil)
    }

    // MARK: - Private main-actor implementations

    private func _show() {
        guard UserDefaults.standard.object(forKey: "showRecordingOverlay") as? Bool ?? true else { return }

        state = .recording
        audioLevel = -60
        elapsed = 0
        startDate = Date()

        if window == nil { window = RecordingHUDWindow() }
        let hudView = NSHostingView(rootView: RecordingHUDView(controller: self))
        hudView.frame = NSRect(x: 0, y: 0, width: 300, height: 52)
        window?.contentView = hudView
        window?.positionAtTopCenter()
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
        window?.orderOut(nil)
    }
}

extension Notification.Name {
    static let hudCancelTapped = Notification.Name("hudCancelTapped")
}

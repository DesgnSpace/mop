import AppKit
import SwiftUI

final class AboutWindow: NSWindowController {
    static let shared = AboutWindow()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About MOP"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: AboutView())
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutView: View {
    private let version: String = {
        if let path = Bundle.main.path(forResource: "VERSION", ofType: nil),
           let v = try? String(contentsOfFile: path, encoding: .utf8) {
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "1.0.2"
    }()

    var body: some View {
        VStack(spacing: 16) {
            if let img = NSImage(named: "AppIcon") {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 4) {
                Text("MOP")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Built with")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: 16) {
                    ackLink("WhisperKit", url: "https://github.com/argmaxinc/WhisperKit")
                    ackLink("FluidAudio", url: "https://github.com/FluidInference/FluidAudio")
                    ackLink("KeyboardShortcuts", url: "https://github.com/sindresorhus/KeyboardShortcuts")
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 340, height: 280)
    }

    private func ackLink(_ title: String, url: String) -> some View {
        Button(title) {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(Color.accentColor)
    }
}

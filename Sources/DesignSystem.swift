import AppKit
import SwiftUI

enum MOPDesign {
    enum Surface {
        static let sidebar = dynamic(light: "F4F4F4", dark: "1E1E1E")
        static let content = dynamic(light: "FAFAFA", dark: "262626")
        static let panel = dynamic(light: "FFFFFF", dark: "2E2E2E")
        static let hairline = dynamic(light: "EEEEEE", dark: "161616")
        static let selection = Color(nsColor: NSColor(name: nil) { appearance in
            let alpha: CGFloat = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.16 : 0.09
            return NSColor.labelColor.withAlphaComponent(alpha)
        })
        static let sunken = Color(nsColor: NSColor(name: nil) { appearance in
            let alpha: CGFloat = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.05 : 0.08
            return NSColor.labelColor.withAlphaComponent(alpha)
        })
        static let sunkenSoft = Color(nsColor: NSColor(name: nil) { appearance in
            let alpha: CGFloat = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.02 : 0.035
            return NSColor.labelColor.withAlphaComponent(alpha)
        })
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
    }

    enum Spacing {
        static let panel: CGFloat = 16
        static let detailHorizontal: CGFloat = 24
        static let detailTop: CGFloat = 24
        static let detailBottom: CGFloat = 16
        static let settings: CGFloat = 20
        static let card: CGFloat = 12
        static let output: CGFloat = 10
        static let block: CGFloat = 16
        static let denseRow: CGFloat = 5
        static let settingsRow: CGFloat = 10
        static let sectionGap: CGFloat = 24
        static let iconColumn: CGFloat = 24
        static let controlColumn: CGFloat = 180
        static let maxSegmented: CGFloat = 360
    }

    enum Text {
        static let tertiary = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .tertiaryLabelColor : .labelColor.withAlphaComponent(0.48)
        })
        static let disabled = Color.primary.opacity(0.55)
        static let archived = Color.primary.opacity(0.5)
        static let deEmphasized = Color.primary.opacity(0.78)
    }

    enum Semantic {
        static let success = Color(nsColor: .systemGreen).opacity(0.7)
        static let failure = Color(nsColor: .systemRed).opacity(0.9)
        static let attention = Color.blue
        static let warning = Color.orange
    }

    enum Syntax {
        static let keyword = dynamic(light: "8A3FFC", dark: "C9A0FF")
        static let type = dynamic(light: "1D5FD6", dark: "7FB1FF")
        static let string = dynamic(light: "A1620A", dark: "E0A458")
        static let number = dynamic(light: "0F766E", dark: "5FCFC6")
        static let comment = dynamic(light: "6B7280", dark: "8B949E")
    }

    static func sectionLabel(_ text: String) -> some View {
        SwiftUI.Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(Text.tertiary)
    }

    static func machineFont(size: CGFloat = 10, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(hex: hex)
        })
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}

enum MOPStatusState {
    case running, failed, needsInput, cancelled, unknown, blocked, completed, queued, pending, answered

    var color: Color {
        switch self {
        case .running, .cancelled, .pending: return .secondary
        case .failed, .blocked: return MOPDesign.Semantic.failure
        case .needsInput, .answered: return MOPDesign.Semantic.attention
        case .unknown, .queued: return MOPDesign.Text.tertiary
        case .completed: return MOPDesign.Semantic.success
        }
    }

    var isRing: Bool {
        switch self {
        case .blocked, .completed, .queued, .pending, .answered: return true
        default: return false
        }
    }
    var isPulsing: Bool { self == .running }
}

struct MOPStatusMarker: View {
    let state: MOPStatusState
    var dense = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .strokeBorder(state.color, lineWidth: state.isRing ? 1.5 : 0)
            .background(Circle().fill(state.isRing ? .clear : state.color))
            .frame(width: dense ? 6 : 8, height: dense ? 6 : 8)
            .opacity(state.isPulsing && pulsing ? 0.3 : 1)
            .scaleEffect(state.isPulsing && pulsing ? 0.72 : 1)
            .animation(reduceMotion || !state.isPulsing ? nil : .easeInOut(duration: 0.85).repeatForever(), value: pulsing)
            .onAppear { if !reduceMotion && state.isPulsing { pulsing = true } }
    }
}

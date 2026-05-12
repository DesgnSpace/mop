import SwiftUI

struct RecordingHUDView: View {
    var controller: RecordingHUDController

    var body: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
            Capsule()
                .strokeBorder(Color.borderSubtle, lineWidth: 0.5)

            HStack(spacing: 10) {
                recordingDot
                waveformBars
                Spacer()
                elapsedLabel
                cancelButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 300, height: 52)
        .shadow(color: Color(red: 0, green: 0, blue: 0).opacity(0.25), radius: 12, y: 4)
        .padding(20)
        .background(.clear)
    }

    private var recordingDot: some View {
        Circle()
            .fill(controller.state == .recording ? Color.semanticError : Color.semanticWarning)
            .frame(width: 8, height: 8)
            .animation(.easeInOut(duration: 0.3), value: controller.state == .recording)
    }

    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(controller.state == .recording ? Color.textPrimary : Color.textSecondary)
                    .frame(width: 3, height: barHeight(index: i))
                    .animation(.easeInOut(duration: 0.15), value: controller.audioLevel)
            }
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        let base: CGFloat = 4
        let maxH: CGFloat = 22
        guard controller.state == .recording else { return base }
        let normalized = min(1, max(0, CGFloat((controller.audioLevel + 60) / 60)))
        let offsets: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
        return base + (maxH - base) * normalized * offsets[index]
    }

    private var elapsedLabel: some View {
        Text(formattedElapsed)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Color.textSecondary)
            .monospacedDigit()
    }

    private var cancelButton: some View {
        Button(action: controller.cancel) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.textSecondary)
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
    }

    private var formattedElapsed: String {
        let s = Int(controller.elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

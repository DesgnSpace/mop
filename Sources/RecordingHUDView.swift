import SwiftUI

struct RecordingHUDView: View {
    var controller: RecordingHUDController
    @State private var dotPulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)

            HStack(spacing: 8) {
                recordingDot
                waveformBars
                Spacer()
                cancelButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !controller.partialText.isEmpty {
                VStack {
                    Spacer()
                    Color.white.opacity(0.12).frame(height: 0.5)
                    ScrollView {
                        Text(controller.partialText)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 80)
                }
            }
        }
        .frame(width: 200, height: controller.partialText.isEmpty ? 40 : 120)
        .padding(10)
        .background(.clear)
    }

    private var recordingDot: some View {
        Circle()
            .fill(controller.state == .recording ? Color.red : Color.orange)
            .frame(width: 7, height: 7)
            .scaleEffect(controller.state == .recording && dotPulse ? 1.18 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: controller.state)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dotPulse = true
                }
            }
    }

    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(controller.state == .recording ? Color.primary : Color.secondary)
                    .frame(width: 2.5, height: barHeight(index: i))
                    .animation(.easeInOut(duration: 0.15), value: controller.audioLevel)
            }
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        let base: CGFloat = 3
        let maxH: CGFloat = 18
        guard controller.state == .recording else { return base }
        let normalized = min(1, max(0, CGFloat((controller.audioLevel + 60) / 60)))
        let offsets: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
        return base + (maxH - base) * normalized * offsets[index]
    }

    private var cancelButton: some View {
        Button(action: controller.cancel) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
    }
}

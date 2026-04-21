import SwiftUI
import AppKit
import SharedModels

struct AccuracyBar: View {
    let accuracy: String
    let note: String
    let sourceURL: String

    var accuracyValue: Double {
        let cleanedAccuracy = accuracy
            .replacingOccurrences(of: "~", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleanedAccuracy) ?? 0.0
    }

    var fillColor: Color {
        switch accuracyValue {
        case 97...:
            return .green
        case 95..<97:
            return .blue
        case 93..<95:
            return .orange
        default:
            return .yellow
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.fill")
                .font(.caption2)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: max(0, geometry.size.width * accuracyValue / 100), height: 6)
                }
            }
            .frame(width: 35, height: 6)

            Text(accuracy)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(minWidth: 40, alignment: .leading)
                .fixedSize()

            Button(action: {
                if let url = URL(string: sourceURL) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(note)
        }
    }
}

struct ModelCard: View {
    let model: ModelInfo
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let downloadError: String?
    let loadingState: ModelStateManager.ModelLoadingState
    let onSelect: () -> Void
    let onDownload: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Selection indicator
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                    .frame(width: 24, height: 24)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isSelected)

            // Model info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)
                        .foregroundColor(isSelected ? .accentColor : .primary)

                    // Language badge
                    Text(model.languages)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .foregroundColor(.accentColor)
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive")
                            .font(.caption2)
                        Text(model.size)
                            .font(.caption)
                            .fixedSize()
                    }
                    .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.caption2)
                        Text(model.speed)
                            .font(.caption)
                            .fixedSize()
                    }
                    .foregroundColor(.secondary)
                    .help("Speed relative to baseline. See https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks for detailed performance metrics.")

                    AccuracyBar(accuracy: model.accuracy, note: model.accuracyNote, sourceURL: model.sourceURL)
                }
            }

            Spacer()

            // Download button or status
            if isDownloaded {
                switch loadingState {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .loaded:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Loaded")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                default:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.blue)
                        Text("Downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if case .downloading(let progress) = loadingState {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 70)
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 35)
                }
            } else if loadingState == .validating {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Validating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action: onDownload) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let error = downloadError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.08)
                    : (isHovered ? Color.gray.opacity(0.06) : Color.gray.opacity(0.03)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.15), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.1) : Color.clear, radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if isDownloaded {
                onSelect()
            }
        }
    }
}

struct ParakeetModelCard: View {
    let version: ParakeetVersion
    let isSelected: Bool
    let loadingState: ParakeetLoadingState
    let onSelect: () -> Void
    let onDownload: () -> Void

    @State private var isHovered = false

    var isDownloaded: Bool {
        loadingState == .loaded || loadingState == .downloaded
    }

    var body: some View {
        HStack(spacing: 16) {
            // Selection indicator
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                    .frame(width: 24, height: 24)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isSelected)

            // Model info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(version.displayName)
                        .font(.headline)
                        .foregroundColor(isSelected ? .accentColor : .primary)

                    // Language badge
                    Text(version.languages)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12)))
                        .foregroundColor(.accentColor)
                }

                Text(version.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive")
                            .font(.caption2)
                        Text(version.size)
                            .font(.caption)
                            .fixedSize()
                    }
                    .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.caption2)
                        Text(version.speed)
                            .font(.caption)
                            .fixedSize()
                    }
                    .foregroundColor(.secondary)
                    .help("Real-time factor - how many times faster than real-time the model transcribes")

                    AccuracyBar(
                        accuracy: version.accuracyPercent,
                        note: "Word Error Rate on LibriSpeech test-clean",
                        sourceURL: version == .v2
                            ? "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml"
                            : "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml"
                    )
                }
            }

            Spacer()

            // Download button or status
            if isDownloaded {
                switch loadingState {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .loaded:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Loaded")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                default:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.blue)
                        Text("Downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if loadingState == .downloading || loadingState == .loading {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 70)
                    Text(loadingState == .downloading ? "Downloading..." : "Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.08)
                    : (isHovered ? Color.gray.opacity(0.06) : Color.gray.opacity(0.03)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.15), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.1) : Color.clear, radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if isDownloaded {
                onSelect()
            }
        }
    }
}
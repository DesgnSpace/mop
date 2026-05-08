import SwiftUI
import AppKit
import SharedModels

struct AccuracyBar: View {
    let accuracy: String
    let note: String
    let sourceURL: String

    var accuracyValue: Double {
        let cleaned = accuracy
            .replacingOccurrences(of: "~", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0.0
    }

    var fillColor: Color {
        switch accuracyValue {
        case 97...:    return .green
        case 95..<97:  return .blue
        case 93..<95:  return .orange
        default:       return .yellow
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

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
                .foregroundStyle(.primary)
                .frame(minWidth: 40, alignment: .leading)
                .fixedSize()

            Button(action: {
                if let url = URL(string: sourceURL) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(note)
        }
    }
}

struct UnifiedModelCard: View {
    let model: ModelInfo
    let isSelected: Bool
    let loadingState: UnifiedLoadingState
    let updateAvailable: String?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onUpdate: (() -> Void)?
    let onDelete: (() -> Void)?

    init(
        model: ModelInfo,
        isSelected: Bool,
        loadingState: UnifiedLoadingState,
        updateAvailable: String? = nil,
        onSelect: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onUpdate: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.model = model
        self.isSelected = isSelected
        self.loadingState = loadingState
        self.updateAvailable = updateAvailable
        self.onSelect = onSelect
        self.onDownload = onDownload
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }

    @State private var isHovered = false

    private var isDownloaded: Bool {
        loadingState == .downloaded || loadingState == .loading || loadingState == .loaded
    }

    private var engineBadge: String {
        switch model.engine {
        case .whisperKit: return "WhisperKit"
        case .parakeet:   return "Parakeet"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                    .frame(width: 24, height: 24)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isSelected)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Text(model.languages)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .foregroundStyle(Color.accentColor)
                    Text(engineBadge)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                        .foregroundStyle(Color.secondary)
                    if let wkName = model.whisperKitModelName,
                       let versionLabel = ModelUpdateChecker.versionLabel(from: wkName) {
                        Text(versionLabel)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary.opacity(0.7))
                    }
                    if updateAvailable != nil {
                        Text("Update available")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(Color.orange)
                    }
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive").font(.caption2)
                        Text(model.size).font(.caption).fixedSize()
                    }
                    .foregroundStyle(Color.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer").font(.caption2)
                        Text(model.speed).font(.caption).fixedSize()
                    }
                    .foregroundStyle(Color.secondary)
                    .help("Speed relative to baseline. See https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks for detailed benchmarks.")
                    AccuracyBar(accuracy: model.accuracy, note: model.accuracyNote, sourceURL: model.sourceURL)
                }
            }

            Spacer()
            downloadStatus
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
        .shadow(color: isSelected ? Color.accentColor.opacity(0.1) : .clear, radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering } }
        .onTapGesture { if isDownloaded { onSelect() } }
    }

    @ViewBuilder
    private var downloadStatus: some View {
        switch loadingState {
        case .loaded:
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Loaded").font(.caption).fontWeight(.medium).foregroundStyle(.green)
                }
                deleteButton
            }
        case .loading:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Loading...").font(.caption).foregroundStyle(.secondary)
            }
        case .downloaded:
            HStack(spacing: 8) {
                if let onUpdate, updateAvailable != nil {
                    Button(action: onUpdate) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange)
                            Text("Update").font(.caption).fontWeight(.medium).foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle").foregroundStyle(.blue)
                        Text("Downloaded").font(.caption).foregroundStyle(.secondary)
                    }
                }
                deleteButton
            }
        case .validating:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Validating...").font(.caption).foregroundStyle(.secondary)
            }
        case .downloading(let progress):
            if progress >= 0 {
                HStack(spacing: 8) {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 70)
                    Text(String(format: "%.0f%%", progress * 100)).font(.caption).foregroundStyle(.secondary).frame(width: 35)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(.linear).frame(width: 70)
                    Text("Downloading...").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .notDownloaded:
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

    @ViewBuilder
    private var deleteButton: some View {
        if let onDelete, isHovered {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete model")
        }
    }
}

import SwiftUI
import SharedModels

// MARK: - Model Row

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

    var body: some View {
        HStack(spacing: 0) {
            selectionBar

            HStack(spacing: 12) {
                infoBlock
                Spacer()
                actionArea
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? MOPDesign.Surface.selection
                    : (isHovered ? Color.primary.opacity(0.03) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.1), value: isHovered)
        }
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { if isDownloaded { onSelect() } }
    }

    // MARK: - Subviews

    private var selectionBar: some View {
        Rectangle()
            .fill(isSelected ? Color.secondary : Color.clear)
            .frame(width: 2)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(model.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? MOPDesign.Text.deEmphasized : .primary)

                if updateAvailable != nil {
                    updateBadge
                }
            }

            HStack(spacing: 12) {
                Label(model.size, systemImage: "internaldrive")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                Label(model.accuracyDisplay, systemImage: "waveform.path.ecg")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help(model.accuracyNote)

                Text(model.languages)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
        }
    }

    private var updateBadge: some View {
        Text("UPDATE")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(.orange.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.orange.opacity(0.3), lineWidth: 0.5))
            )
    }

    @ViewBuilder
    private var actionArea: some View {
        switch loadingState {
        case .loaded:
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    MOPStatusMarker(state: .completed, dense: true)
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                        .tracking(0.8)
                }
                deleteButton
            }

        case .loading:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                Text("LOADING")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
            }

        case .downloaded:
            HStack(spacing: 10) {
                if let onUpdate, updateAvailable != nil {
                    Button(action: onUpdate) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 11))
                            Text("Update")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11))
                        Text("Ready")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                deleteButton
            }

        case .validating:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                Text("VALIDATING")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
            }

        case .downloading(let progress):
            HStack(spacing: 8) {
                if progress >= 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                    .fill(MOPDesign.Surface.sunken)
                                    .frame(height: 2)
                                Rectangle()
                                    .fill(Color.secondary)
                                    .frame(width: geo.size.width * progress, height: 2)
                                    .animation(.linear(duration: 0.1), value: progress)
                            }
                        }
                        .frame(width: 72, height: 2)
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        Text("DOWNLOADING")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                    }
                }
            }

        case .notDownloaded:
            Button(action: onDownload) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Download")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(MOPDesign.Surface.selection)
                        .overlay(RoundedRectangle(cornerRadius: MOPDesign.Radius.small).stroke(MOPDesign.Surface.hairline, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if let onDelete, isHovered {
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Delete model")
            .transition(.opacity.animation(.easeInOut(duration: 0.1)))
        }
    }
}

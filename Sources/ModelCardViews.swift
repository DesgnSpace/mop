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
            .padding(.horizontal, MOPDesign.Spacing.panel)
            .padding(.vertical, MOPDesign.Spacing.settingsRow)
            .background(
                isSelected
                    ? MOPDesign.Surface.selection
                    : (isHovered ? MOPDesign.Surface.sunkenSoft : Color.clear)
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
            .fill(isSelected ? Color.accentColor : Color.clear)
            .frame(width: 2)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(model.displayName)
                    .font(isSelected ? MOPDesign.Typography.rowLabel.weight(.semibold) : MOPDesign.Typography.rowLabel)
                    .foregroundStyle(.primary)

                if updateAvailable != nil {
                    updateBadge
                }
            }

            HStack(spacing: 12) {
                Label(model.size, systemImage: "internaldrive")
                    .font(MOPDesign.Typography.technical)
                    .foregroundStyle(MOPDesign.Text.tertiary)

                Label(model.accuracyDisplay, systemImage: "waveform.path.ecg")
                    .font(MOPDesign.Typography.technical)
                    .foregroundStyle(MOPDesign.Text.tertiary)
                    .help(model.accuracyNote)

                Text(model.languages)
                    .font(MOPDesign.Typography.technical)
                    .foregroundStyle(MOPDesign.Text.tertiary)
            }
        }
    }

    private var updateBadge: some View {
        Text("Update available")
            .font(MOPDesign.Typography.technicalEmphasis)
            .foregroundStyle(MOPDesign.Semantic.warning)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch loadingState {
        case .loaded:
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    MOPStatusMarker(state: .completed, dense: true)
                    Text("Active")
                        .font(MOPDesign.Typography.technicalEmphasis)
                        .foregroundStyle(MOPDesign.Semantic.success)
                }
                deleteButton
            }

        case .loading:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                Text("Loading")
                    .font(MOPDesign.Typography.technicalEmphasis)
                    .foregroundStyle(MOPDesign.Text.tertiary)
            }

        case .downloaded:
            HStack(spacing: 10) {
                if let onUpdate, updateAvailable != nil {
                    Button(action: onUpdate) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .font(MOPDesign.Typography.controlLabel)
                            Text("Update")
                                .font(MOPDesign.Typography.controlLabel)
                        }
                        .foregroundStyle(MOPDesign.Semantic.warning)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(MOPDesign.Typography.controlLabel)
                        Text("Ready")
                            .font(MOPDesign.Typography.controlLabel)
                    }
                    .foregroundStyle(MOPDesign.Text.tertiary)
                }
                deleteButton
            }

        case .validating:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                Text("Checking model")
                    .font(MOPDesign.Typography.technicalEmphasis)
                    .foregroundStyle(MOPDesign.Text.tertiary)
            }

        case .downloading(let progress):
            HStack(spacing: 8) {
                if progress >= 0 {
                    VStack(alignment: .trailing, spacing: MOPDesign.Spacing.denseRow) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .frame(width: 72)
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(MOPDesign.Typography.technical)
                            .foregroundStyle(MOPDesign.Text.tertiary)
                    }
                } else {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        Text("Downloading")
                            .font(MOPDesign.Typography.technicalEmphasis)
                            .foregroundStyle(MOPDesign.Text.tertiary)
                    }
                }
            }

        case .notDownloaded:
            Button(action: onDownload) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down")
                        .font(MOPDesign.Typography.controlLabel)
                    Text("Download")
                        .font(MOPDesign.Typography.controlLabel)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.accentColor)
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if let onDelete, isHovered {
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(MOPDesign.Typography.helper)
                    .foregroundStyle(MOPDesign.Text.tertiary)
            }
            .buttonStyle(.plain)
            .help("Delete model")
            .transition(.opacity.animation(.easeInOut(duration: 0.1)))
        }
    }
}

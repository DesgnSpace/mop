import SwiftUI
import AppKit
import SharedModels

// MARK: - Engine Filter

enum ModelEngineFilter: String, CaseIterable {
    case all = "All"
    case whisperKit = "WhisperKit"
    case parakeet = "Parakeet"
}

struct EngineFilterBar: View {
    @Binding var selected: ModelEngineFilter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ModelEngineFilter.allCases, id: \.self) { filter in
                Button(action: { withAnimation(.easeInOut(duration: 0.18)) { selected = filter } }) {
                    Text(filter.rawValue)
                        .font(.system(size: 11, weight: selected == filter ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(selected == filter ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            selected == filter
                                ? Color.primary.opacity(0.08)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)

                if filter != ModelEngineFilter.allCases.last {
                    Divider().frame(height: 16)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: 260)
    }
}

// MARK: - Tier Divider

struct TierDivider: View {
    let tier: ModelTier

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(tierColor.opacity(0.3))
                .frame(height: 0.5)
                .frame(width: 16)

            HStack(spacing: 5) {
                Image(systemName: tier.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tierColor)
                Text(tier.displayName.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .tracking(1.2)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tierColor: Color {
        switch tier {
        case .default:      return .accentColor
        case .highAccuracy: return Color(hue: 0.38, saturation: 0.7, brightness: 0.65)
        case .lowMemory:    return Color(hue: 0.08, saturation: 0.75, brightness: 0.75)
        case .fast:         return Color(hue: 0.49, saturation: 0.8, brightness: 0.65)
        }
    }
}

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

    private var engineColor: Color {
        model.engine == .whisperKit
            ? Color(hue: 0.69, saturation: 0.7, brightness: 0.75)   // indigo
            : Color(hue: 0.49, saturation: 0.8, brightness: 0.65)   // teal
    }

    private var accuracyValue: Double {
        Double(model.accuracy
            .replacingOccurrences(of: "~", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var accuracyColor: Color {
        switch accuracyValue {
        case 98...: return Color(hue: 0.38, saturation: 0.7, brightness: 0.65)
        case 97..<98: return .accentColor
        default: return Color(hue: 0.08, saturation: 0.75, brightness: 0.75)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar (selection indicator)
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 2)
                .animation(.easeInOut(duration: 0.15), value: isSelected)

            HStack(spacing: 12) {
                // Main content
                VStack(alignment: .leading, spacing: 5) {
                    // Name row
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                        // Engine tag
                        Text(model.engine == .whisperKit ? "WK" : "PK")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(engineColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(engineColor.opacity(0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(engineColor.opacity(0.25), lineWidth: 0.5))
                            )

                        if updateAvailable != nil {
                            Text("UPDATE")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.orange.opacity(0.1))
                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.orange.opacity(0.3), lineWidth: 0.5))
                                )
                        }
                    }

                    // Stats row — monospaced spec sheet
                    HStack(spacing: 14) {
                        Label(model.size, systemImage: "internaldrive")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.secondary)

                        Label(model.speed, systemImage: "bolt")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.secondary)

                        Button(action: {
                            if let url = URL(string: model.sourceURL) { NSWorkspace.shared.open(url) }
                        }) {
                            Label(model.accuracy + " WER", systemImage: "waveform.path.ecg")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(accuracyColor)
                        }
                        .buttonStyle(.plain)
                        .help(model.accuracyNote)

                        Text("·  " + model.languages)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                    }
                }

                Spacer()

                // Right: action
                actionArea
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.04)
                    : (isHovered ? Color.primary.opacity(0.03) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.1), value: isHovered)
        }
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { if isDownloaded { onSelect() } }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch loadingState {
        case .loaded:
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hue: 0.38, saturation: 0.7, brightness: 0.65))
                        .frame(width: 5, height: 5)
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hue: 0.38, saturation: 0.7, brightness: 0.65))
                        .tracking(0.8)
                }
                deleteButton
            }

        case .loading:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                Text("LOADING")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
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
                    .foregroundStyle(Color.secondary.opacity(0.7))
                }
                deleteButton
            }

        case .validating:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                Text("VALIDATING")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .tracking(0.8)
            }

        case .downloading(let progress):
            HStack(spacing: 8) {
                if progress >= 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 2)
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * progress, height: 2)
                                    .animation(.linear(duration: 0.1), value: progress)
                            }
                        }
                        .frame(width: 72, height: 2)
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                    }
                } else {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        Text("DOWNLOADING")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.secondary)
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
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5))
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

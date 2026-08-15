import SwiftUI

struct MOPCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MOPDesign.Spacing.block) {
            content
        }
        .padding(MOPDesign.Spacing.panel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MOPDesign.Radius.medium)
                .fill(MOPDesign.Surface.panel)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MOPDesign.Radius.medium)
                .stroke(MOPDesign.Surface.hairline, lineWidth: 0.5)
        }
    }
}

// MARK: - Section Header

struct MOPSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(MOPDesign.Text.tertiary)
                .frame(width: MOPDesign.Spacing.iconColumn, alignment: .center)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
    }
}

struct MOPSettingsRow<Control: View>: View {
    let title: String
    let description: String?
    @ViewBuilder let control: () -> Control

    init(title: String, description: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.description = description
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: MOPDesign.Spacing.panel) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(MOPDesign.Text.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
                .frame(width: MOPDesign.Spacing.controlColumn, alignment: .trailing)
        }
        .padding(.vertical, MOPDesign.Spacing.settingsRow)
    }
}

// MARK: - Toggle Row

struct MOPToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var disabled: Bool = false
    let onChange: () -> Void

    var body: some View {
        MOPSettingsRow(title: title, description: description) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.accentColor)
        }
        .foregroundStyle(disabled ? MOPDesign.Text.disabled : .primary)
        .disabled(disabled)
        .onChange(of: isOn) { _, _ in onChange() }
    }
}

// MARK: - Section Divider

struct MOPSectionDivider: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(MOPDesign.Surface.hairline)
                .frame(height: 0.5)
                .frame(width: 16)

            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title.uppercased())
                    .font(MOPDesign.machineFont(size: 9, weight: .semibold))
                    .foregroundStyle(MOPDesign.Text.tertiary)
                    .tracking(0.6)
            }

            Rectangle()
                .fill(MOPDesign.Surface.hairline)
                .frame(height: 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

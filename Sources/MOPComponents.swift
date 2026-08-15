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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
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
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(disabled ? MOPDesign.Text.disabled : .primary)
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(MOPDesign.Text.tertiary)
            }
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
        .disabled(disabled)
        .onChange(of: isOn) { _, _ in onChange() }
        .padding(.leading, 8)
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

import SwiftUI

// MARK: - Card Container

struct MOPCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Section Header

struct MOPSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.headline)
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
                    .font(.body)
                    .foregroundStyle(disabled ? .secondary : .primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(Color.accentColor)
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
                .fill(Color.accentColor.opacity(0.3))
                .frame(height: 0.5)
                .frame(width: 16)

            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

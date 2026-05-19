import SwiftUI

// MARK: - Settings layout helpers (Jan.ai tarzı)

struct SettingsCard<Content: View>: View {
    let title: String?
    var subtitle: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel()
    }
}

struct SettingsNavRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryText)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                if isSelected {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.accent.opacity(0.12) : (hovered ? AppTheme.subtleInteractiveFill : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(AppTheme.fadeQuick, value: hovered)
        .onHover { hovered = $0 }
    }
}

struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppTheme.primaryText)
        }
        .font(.subheadline)
    }
}

struct SettingsCaption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
    }
}

struct SettingsTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 80
    var monospaced: Bool = false

    var body: some View {
        TextEditor(text: $text)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: minHeight)
            .background(AppTheme.composerBackground, in: RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            }
    }
}

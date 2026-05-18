import SwiftUI

/// Paylaşılan arayüz sabitleri — tutarlı boşluk, köşe ve rozet stili.
enum AppTheme {
    static let contentPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let messageSpacing: CGFloat = 16
    static let bubbleRadius: CGFloat = 12
    static let panelRadius: CGFloat = 10
    static let badgeHPadding: CGFloat = 6
    static let badgeVPadding: CGFloat = 2

    static func userBubbleBackground() -> Color {
        Color.accentColor.opacity(0.1)
    }

    static func assistantBubbleBackground() -> Color {
        Color.primary.opacity(0.05)
    }

    static func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, badgeHPadding)
            .padding(.vertical, badgeVPadding)
            .foregroundStyle(color)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

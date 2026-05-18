import SwiftUI

/// Paylaşılan arayüz sabitleri — Jan.ai tarzı koyu tema.
enum AppTheme {
    static let contentPadding: CGFloat = 20
    static let rowSpacing: CGFloat = 12
    static let messageSpacing: CGFloat = 20
    static let bubbleRadius: CGFloat = 16
    static let panelRadius: CGFloat = 14
    static let composerRadius: CGFloat = 18
    static let sidebarWidth: CGFloat = 260
    static let badgeHPadding: CGFloat = 6
    static let badgeVPadding: CGFloat = 2
    static let searchFieldRadius: CGFloat = 8
    static let maxChatContentWidth: CGFloat = 720

    static var chatBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var sidebarBackground: Color { Color(nsColor: .underPageBackgroundColor) }
    static var elevatedSurface: Color { Color.primary.opacity(0.06) }
    static var composerBackground: Color { Color.primary.opacity(0.05) }
    static var border: Color { Color.primary.opacity(0.1) }
    static var primaryText: Color { .primary }
    static var secondaryText: Color { .secondary }
    static var accent: Color { Color(red: 0.95, green: 0.45, blue: 0.35) }

    static func userBubbleBackground() -> Color {
        Color.primary.opacity(0.12)
    }

    static func assistantBubbleBackground() -> Color {
        Color.clear
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

    static func fitBadge(_ fit: ModelFitLevel) -> some View {
        badge(fit.displayName, color: fit.tintColor)
    }

    static func tagBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, badgeHPadding)
            .padding(.vertical, badgeVPadding)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}

extension ModelFitLevel {
    var displayName: String {
        switch self {
        case .ideal: return "En uygun"
        case .workable: return "Dikkat"
        case .notRecommended: return "Ağır"
        }
    }

    var tintColor: Color {
        switch self {
        case .ideal: return .green
        case .workable: return .orange
        case .notRecommended: return .red
        }
    }
}

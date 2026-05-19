import SwiftUI

/// Paylaşılan arayüz sabitleri — modern koyu cam tema.
enum AppTheme {
    static let contentPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let messageSpacing: CGFloat = 20
    static let bubbleRadius: CGFloat = 18
    static let panelRadius: CGFloat = 16
    static let composerRadius: CGFloat = 22
    static let sidebarWidth: CGFloat = 260
    static let badgeHPadding: CGFloat = 7
    static let badgeVPadding: CGFloat = 3
    static let searchFieldRadius: CGFloat = 10
    static let maxChatContentWidth: CGFloat = 720
    static let chatHeaderHeight: CGFloat = 52
    static let composerMinHeight: CGFloat = 80
    static let composerAccessoryHeight: CGFloat = 44
    static let messageStatsHeight: CGFloat = 18

    static let springSnappy = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let springSoft = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let fadeQuick = Animation.easeInOut(duration: 0.16)

    // MARK: - Brand

    static let accent = Color(red: 0.98, green: 0.44, blue: 0.36)
    static let accentSecondary = Color(red: 0.62, green: 0.52, blue: 0.98)
    static let accentTertiary = Color(red: 0.35, green: 0.78, blue: 0.95)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, Color(red: 1.0, green: 0.58, blue: 0.42), accentSecondary.opacity(0.9)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var subtleGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.07),
                Color.primary.opacity(0.03)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Surfaces

    static var chatBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1)
                : NSColor.windowBackgroundColor
        }))
    }

    static var sidebarBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1)
                : NSColor.underPageBackgroundColor
        }))
    }

    static var elevatedSurface: Color { Color.primary.opacity(0.07) }
    static var composerBackground: Color { Color.primary.opacity(0.06) }
    static var border: Color { Color.primary.opacity(0.12) }
    static var borderStrong: Color { Color.primary.opacity(0.18) }
    static var primaryText: Color { .primary }
    static var secondaryText: Color { .secondary }
    static var glowAccent: Color { accent.opacity(0.35) }
    static var subtleInteractiveFill: Color { Color.primary.opacity(0.06) }
    static var subtleInteractiveHoverFill: Color { Color.primary.opacity(0.10) }

    static func userBubbleBackground() -> some ShapeStyle {
        LinearGradient(
            colors: [
                accent.opacity(0.22),
                accentSecondary.opacity(0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func assistantBubbleBackground() -> Color {
        Color.clear
    }

    // MARK: - Components

    static func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, badgeHPadding)
            .padding(.vertical, badgeVPadding)
            .foregroundStyle(color)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.22), lineWidth: 0.5)
            )
    }

    static func fitBadge(_ fit: ModelFitLevel) -> some View {
        badge(fit.displayName, color: fit.tintColor)
    }

    static func tagBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, badgeHPadding)
            .padding(.vertical, badgeVPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5)
            )
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

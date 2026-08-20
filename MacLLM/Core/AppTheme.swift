import SwiftUI

/// Paylaşılan arayüz sabitleri — cam / neon koyu tema.
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
    static let downloadSlimBarHeight: CGFloat = 30

    static let springSnappy = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let springSoft = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let fadeQuick = Animation.easeInOut(duration: 0.16)

    // MARK: - Brand

    static let accent = Color(red: 0.98, green: 0.44, blue: 0.36)
    static let accentSecondary = Color(red: 0.62, green: 0.52, blue: 0.98)
    static let accentTertiary = Color(red: 0.35, green: 0.78, blue: 0.95)
    static let successNeon = Color(red: 0.35, green: 0.92, blue: 0.55)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, Color(red: 1.0, green: 0.58, blue: 0.42), accentSecondary.opacity(0.9)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var navActiveGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.55, green: 0.38, blue: 0.95),
                Color(red: 0.85, green: 0.35, blue: 0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var downloadProgressGradient: LinearGradient {
        LinearGradient(
            colors: [accentTertiary, accentSecondary.opacity(0.85)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var destructiveGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.95, green: 0.32, blue: 0.38), Color(red: 0.75, green: 0.18, blue: 0.28)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Surfaces

    static var chatBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.07, green: 0.05, blue: 0.12, alpha: 1)
                : NSColor.windowBackgroundColor
        }))
    }

    static var sidebarBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.05, green: 0.04, blue: 0.09, alpha: 1)
                : NSColor.underPageBackgroundColor
        }))
    }

    static var elevatedSurface: Color { Color.primary.opacity(0.08) }
    static var composerBackground: Color { Color.primary.opacity(0.07) }
    static var border: Color { Color.primary.opacity(0.14) }
    static var borderStrong: Color { Color.primary.opacity(0.22) }
    static var primaryText: Color { .primary }
    static var secondaryText: Color { .secondary }
    static var glowAccent: Color { accent.opacity(0.4) }
    static var glowSecondary: Color { accentSecondary.opacity(0.35) }
    static var subtleInteractiveFill: Color { Color.primary.opacity(0.07) }
    static var subtleInteractiveHoverFill: Color { Color.primary.opacity(0.11) }

    static func userBubbleBackground() -> some ShapeStyle {
        LinearGradient(
            colors: [
                accent.opacity(0.24),
                accentSecondary.opacity(0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func assistantBubbleBackground() -> Color {
        Color.clear
    }

    // MARK: - Code & Workspace Theming

    static let diffAdditionBg = Color(red: 0.16, green: 0.72, blue: 0.38).opacity(0.14)
    static let diffAdditionText = Color(red: 0.22, green: 0.82, blue: 0.44)
    static let diffAdditionGutter = Color(red: 0.16, green: 0.72, blue: 0.38).opacity(0.25)
    
    static let diffDeletionBg = Color(red: 0.94, green: 0.28, blue: 0.32).opacity(0.13)
    static let diffDeletionText = Color(red: 0.96, green: 0.42, blue: 0.46)
    static let diffDeletionGutter = Color(red: 0.94, green: 0.28, blue: 0.32).opacity(0.25)

    static let terminalBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.11, alpha: 1)
            : NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.18, alpha: 1)
    }))
    static let terminalHeaderBg = Color.black.opacity(0.25)
    static let terminalBorder = Color.white.opacity(0.12)
    static let codeGutterBackground = Color.primary.opacity(0.025)

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

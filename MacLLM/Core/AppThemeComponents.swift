import SwiftUI

// MARK: - Modifiers

extension View {
    func appGlassCard(
        cornerRadius: CGFloat = AppTheme.panelRadius,
        material: Material = .ultraThinMaterial
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(material)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
    }

    func appFloatingShadow(radius: CGFloat = 24, y: CGFloat = 10) -> some View {
        shadow(color: .black.opacity(0.28), radius: radius, y: y)
            .shadow(color: AppTheme.glowAccent.opacity(0.08), radius: radius * 0.6, y: y * 0.5)
    }

    func appCanvasBackground() -> some View {
        background {
            ZStack {
                AppTheme.chatBackground
                RadialGradient(
                    colors: [
                        AppTheme.accentSecondary.opacity(0.07),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [
                        AppTheme.accent.opacity(0.05),
                        .clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 360
                )
            }
            .ignoresSafeArea()
        }
    }

    /// Minimum tıklama alanı — macOS'ta dar ikon hedeflerini genişletir.
    func appHitTarget(minWidth: CGFloat = 32, minHeight: CGFloat = 32) -> some View {
        frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(Rectangle())
    }

    func appPanel(cornerRadius: CGFloat = AppTheme.panelRadius) -> some View {
        background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            }
    }
}

// MARK: - Button styles

struct ModernScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(AppTheme.springSnappy, value: configuration.isPressed)
    }
}

struct SidebarNavButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? AppTheme.accent.opacity(0.18)
                            : hovered
                                ? Color.primary.opacity(0.07)
                                : Color.clear
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(AppTheme.springSnappy, value: configuration.isPressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct PromptChipButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                    .fill(
                        hovered || configuration.isPressed
                            ? AppTheme.accent.opacity(0.10)
                            : AppTheme.elevatedSurface
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                            .strokeBorder(
                                hovered
                                    ? AppTheme.accent.opacity(0.35)
                                    : AppTheme.border,
                                lineWidth: 1
                            )
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : hovered ? 1.01 : 1)
            .animation(AppTheme.springSnappy, value: configuration.isPressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct AccentIconButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .background {
                Circle()
                    .fill(
                        hovered || configuration.isPressed
                            ? AppTheme.accent.opacity(0.16)
                            : Color.primary.opacity(0.06)
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.92 : hovered ? 1.06 : 1)
            .animation(AppTheme.springSnappy, value: configuration.isPressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct AccentPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(disabled ? AppTheme.secondaryText.opacity(0.7) : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(disabled ? AppTheme.subtleInteractiveFill : AppTheme.accentGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                disabled ? AppTheme.border : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(color: disabled ? .clear : AppTheme.glowAccent.opacity(hovered ? 0.45 : 0.25), radius: hovered ? 12 : 8, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : hovered ? 1.01 : 1)
            .animation(AppTheme.springSnappy, value: configuration.isPressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovered ? AppTheme.subtleInteractiveHoverFill : AppTheme.subtleInteractiveFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(AppTheme.springSnappy, value: configuration.isPressed)
            .animation(AppTheme.fadeQuick, value: hovered)
            .onHover { hovered = $0 }
    }
}

// MARK: - Status & chrome

struct AnimatedStatusDot: View {
    let color: Color
    var pulse: Bool = false

    @State private var animating = false

    var body: some View {
        ZStack {
            if pulse {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(animating ? 1.35 : 0.85)
                    .opacity(animating ? 0 : 0.7)
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.55), radius: 4)
        }
        .onAppear {
            guard pulse else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
        .onChange(of: pulse) { _, active in
            animating = false
            if active {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
        }
    }
}

struct AppStatusBar: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .appGlassCard(cornerRadius: 20, material: .thinMaterial)
        .appFloatingShadow(radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var statusIcon: String {
        if message.contains("%") { return "arrow.down.circle" }
        if message.contains("Hata") || message.contains("hata") { return "exclamationmark.circle" }
        if message.contains("vision") || message.contains("Görüntü") { return "eye.slash" }
        return "info.circle"
    }
}

struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(AppTheme.accentGradient)
                .frame(width: size, height: size)
                .shadow(color: AppTheme.glowAccent, radius: 8, y: 2)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

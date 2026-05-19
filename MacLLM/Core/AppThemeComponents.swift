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
                                    Color.white.opacity(0.22),
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
        shadow(color: .black.opacity(0.22), radius: radius, y: y)
            .shadow(color: AppTheme.glowSecondary.opacity(0.1), radius: radius * 0.5, y: y * 0.4)
    }

    func appCanvasBackground() -> some View {
        background {
            ZStack {
                AppTheme.chatBackground
                RadialGradient(
                    colors: [AppTheme.accentSecondary.opacity(0.14), .clear],
                    center: .topLeading,
                    startRadius: 30,
                    endRadius: 480
                )
                RadialGradient(
                    colors: [AppTheme.accent.opacity(0.08), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 400
                )
            }
            .ignoresSafeArea()
        }
    }

    func appHitTarget(minWidth: CGFloat = 32, minHeight: CGFloat = 32) -> some View {
        frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(Rectangle())
    }

    func appPanel(cornerRadius: CGFloat = AppTheme.panelRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                }
        }
    }

    func appTopHighlight(cornerRadius: CGFloat, opacity: Double = 0.28) -> some View {
        overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(opacity), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 14)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 3D button chrome

private enum ButtonChrome3D {
    static func raisedShadows(
        glow: Color,
        hovered: Bool,
        pressed: Bool
    ) -> (Color, CGFloat, CGFloat, Color, CGFloat, CGFloat) {
        if pressed {
            return (.black.opacity(0.12), 2, 1, glow.opacity(0.15), 4, 1)
        }
        if hovered {
            return (.black.opacity(0.28), 8, 5, glow.opacity(0.38), 10, 3)
        }
        return (.black.opacity(0.22), 6, 4, glow.opacity(0.22), 8, 2)
    }
}

struct ModernScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(AppTheme.fadeQuick, value: configuration.isPressed)
    }
}

struct SidebarNavButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shadows = ButtonChrome3D.raisedShadows(
            glow: AppTheme.glowSecondary,
            hovered: hovered,
            pressed: pressed
        )

        return configuration.label
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        pressed
                            ? AppTheme.accentSecondary.opacity(0.2)
                            : hovered
                                ? Color.primary.opacity(0.09)
                                : Color.clear
                    )
                    .shadow(color: shadows.0, radius: shadows.1, y: shadows.2)
            }
            .scaleEffect(pressed ? 0.98 : hovered ? 1.01 : 1)
            .animation(AppTheme.fadeQuick, value: pressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct PromptChipButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                            .strokeBorder(
                                hovered ? AppTheme.accent.opacity(0.4) : AppTheme.border,
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(pressed ? 0.1 : 0.18), radius: pressed ? 2 : 5, y: pressed ? 1 : 3)
            }
            .appTopHighlight(cornerRadius: AppTheme.panelRadius, opacity: hovered ? 0.2 : 0.12)
            .scaleEffect(pressed ? 0.97 : hovered ? 1.01 : 1)
            .animation(AppTheme.springSnappy, value: pressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct AccentIconButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .contentShape(Circle())
            .background {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(hovered ? 0.14 : 0.08),
                                Color.primary.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(pressed ? 0.1 : 0.2), radius: pressed ? 2 : 5, y: pressed ? 1 : 3)
            }
            .scaleEffect(pressed ? 0.94 : hovered ? 1.04 : 1)
            .animation(AppTheme.fadeQuick, value: pressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct AccentPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shadows = ButtonChrome3D.raisedShadows(
            glow: AppTheme.glowAccent,
            hovered: hovered && !disabled,
            pressed: pressed
        )

        return configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(disabled ? AppTheme.secondaryText.opacity(0.7) : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(disabled ? AnyShapeStyle(AppTheme.subtleInteractiveFill) : AnyShapeStyle(AppTheme.accentGradient))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                disabled ? AppTheme.border : Color.white.opacity(0.18),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: shadows.0, radius: shadows.1, y: shadows.2)
                    .shadow(color: shadows.3, radius: shadows.4, y: shadows.5)
            }
            .appTopHighlight(cornerRadius: 12, opacity: disabled ? 0 : 0.32)
            .scaleEffect(pressed ? 0.97 : hovered && !disabled ? 1.02 : 1)
            .offset(y: pressed ? 1 : 0)
            .animation(AppTheme.springSnappy, value: pressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(pressed ? 0.08 : 0.2), radius: pressed ? 2 : 5, y: pressed ? 1 : 3)
            }
            .appTopHighlight(cornerRadius: 11, opacity: 0.15)
            .scaleEffect(pressed ? 0.97 : 1)
            .offset(y: pressed ? 1 : 0)
            .animation(AppTheme.springSnappy, value: pressed)
            .animation(AppTheme.fadeQuick, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shadows = ButtonChrome3D.raisedShadows(
            glow: Color.red.opacity(0.4),
            hovered: hovered,
            pressed: pressed
        )

        return configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.destructiveGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: shadows.0, radius: shadows.1, y: shadows.2)
                    .shadow(color: shadows.3, radius: shadows.4, y: shadows.5)
            }
            .appTopHighlight(cornerRadius: 11, opacity: 0.22)
            .scaleEffect(pressed ? 0.97 : hovered ? 1.02 : 1)
            .offset(y: pressed ? 1 : 0)
            .animation(AppTheme.springSnappy, value: pressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct SendCircleButtonStyle: ButtonStyle {
    var enabled: Bool = true
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background {
                Circle()
                    .fill(
                        enabled
                            ? AnyShapeStyle(AppTheme.accentGradient)
                            : AnyShapeStyle(Color.primary.opacity(0.08))
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(enabled ? 0.2 : 0), lineWidth: 1)
                    }
                    .shadow(
                        color: enabled ? AppTheme.glowAccent.opacity(hovered ? 0.5 : 0.3) : .clear,
                        radius: hovered ? 12 : 8,
                        y: pressed ? 1 : 3
                    )
                    .shadow(color: .black.opacity(enabled ? 0.25 : 0), radius: 6, y: 3)
            }
            .appTopHighlight(cornerRadius: 18, opacity: enabled ? 0.35 : 0)
            .scaleEffect(pressed ? 0.94 : hovered && enabled ? 1.05 : 1)
            .animation(AppTheme.springSnappy, value: pressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

struct StopCircleButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.red.opacity(0.45), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.2), radius: pressed ? 2 : 5, y: pressed ? 1 : 3)
            }
            .scaleEffect(pressed ? 0.94 : hovered ? 1.04 : 1)
            .animation(AppTheme.springSnappy, value: pressed)
            .animation(AppTheme.springSoft, value: hovered)
            .onHover { hovered = $0 }
    }
}

// MARK: - Progress

struct GradientProgressBar: View {
    var progress: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(AppTheme.downloadProgressGradient)
                    .frame(width: max(0, geo.size.width * min(1, max(0, progress))))
                    .shadow(color: AppTheme.accentTertiary.opacity(0.45), radius: 4, y: 0)
            }
        }
        .frame(height: height)
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

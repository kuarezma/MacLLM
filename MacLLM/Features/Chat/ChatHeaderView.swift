import SwiftUI

struct ChatHeaderView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @State private var settingsHovered = false

    var body: some View {
        HStack(spacing: 12) {
            modelMenu

            Spacer(minLength: 0)

            AnimatedStatusDot(color: statusColor, pulse: shouldPulse)

            Button {
                AppSettingsOpener.open()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(settingsHovered ? AppTheme.accent : AppTheme.primaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .background {
                Circle()
                    .fill(settingsHovered ? AppTheme.accent.opacity(0.16) : Color.primary.opacity(0.06))
            }
            .appHitTarget(minWidth: 40, minHeight: 40)
            .help("Ayarlar")
            .accessibilityLabel("Ayarlar")
            .onHover { settingsHovered = $0 }
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 8)
        .frame(height: AppTheme.chatHeaderHeight)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var modelMenu: some View {
        VStack(spacing: 6) {
            Menu {
                if appModel.installedModels.isEmpty {
                    Button("Model Hub…") { appModel.showCatalog = true }
                } else {
                    ForEach(appModel.installedModels) { model in
                        Button {
                            appModel.selectedModelId = model.id
                        } label: {
                            HStack {
                                Text(model.name)
                                if appModel.selectedModelId == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Model Hub…") { appModel.showCatalog = true }
                    if inferenceService.isModelLoaded {
                        Button("Bellekten Çıkar") {
                            Task { await appModel.unloadCurrentModel() }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.14))
                            .frame(width: 28, height: 28)
                        Image(systemName: "cpu")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(appModel.selectedModel?.name ?? "Model seçin")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(AppTheme.primaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .appGlassCard(cornerRadius: 20, material: .ultraThinMaterial)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let profile = appModel.activeProfile {
                profileChips(profile)
            }
        }
    }

    @ViewBuilder
    private func profileChips(_ profile: LoadedModelProfile) -> some View {
        HStack(spacing: 6) {
            profileChip(profile.resolvedChatTemplate, icon: "text.quote")
            profileChip(profile.modality.label, icon: profile.supportsVision ? "eye" : "text.alignleft")
            if let params = profile.parameterLabel {
                profileChip(params, icon: "number")
            }
        }
    }

    private func profileChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var statusColor: Color {
        if appModel.isLoadingModel { return .orange }
        if inferenceService.isGenerating { return .orange }
        if inferenceService.isModelLoaded { return .green }
        return AppTheme.secondaryText.opacity(0.5)
    }

    private var shouldPulse: Bool {
        appModel.isLoadingModel || inferenceService.isGenerating || inferenceService.isModelLoaded
    }
}

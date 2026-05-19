import SwiftUI

struct ChatHeaderView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @State private var settingsHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            modelMenu

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

            AnimatedStatusDot(color: statusColor, pulse: shouldPulse)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 10)
        .frame(height: AppTheme.chatHeaderHeight)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var modelMenu: some View {
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

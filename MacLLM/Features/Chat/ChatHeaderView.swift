import SwiftUI

struct ChatHeaderView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            modelMenu

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Ayarlar")

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .help(statusHelp)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 10)
        .frame(height: AppTheme.chatHeaderHeight)
        .background(AppTheme.chatBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
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
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                Text(appModel.selectedModel?.name ?? "Model seçin")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.primaryText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppTheme.elevatedSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
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

    private var statusHelp: String {
        if appModel.isLoadingModel { return "Model yükleniyor" }
        if inferenceService.isGenerating { return "Yanıt üretiliyor" }
        if inferenceService.isModelLoaded { return "Model hazır" }
        return "Model yüklü değil"
    }
}

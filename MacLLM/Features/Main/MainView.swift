import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = appModel

        NavigationSplitView(columnVisibility: $columnVisibility) {
            ModelSidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            VStack(spacing: 0) {
                AppUpdateBannerView()
                if downloadService.hasActiveTransfers {
                    ActiveDownloadsPanel(downloadService: downloadService, style: .compact)
                }
                ChatView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if model.isLoadingModel || inferenceService.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    model.showCatalog = true
                } label: {
                    Label("Model Ekle", systemImage: "plus.circle")
                }
                .help("Katalogdan indir veya GGUF içe aktar")
                Button {
                    model.newChat()
                } label: {
                    Label("Yeni Sohbet", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                SettingsLink {
                    Label("Ayarlar", systemImage: "gearshape")
                }
                .help("Ayarlar (⌘,)")
            }
        }
        .sheet(isPresented: $model.showCatalog) {
            ModelCatalogView()
        }
        .safeAreaInset(edge: .bottom) {
            if let status = model.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(.bar)
            }
        }
    }
}

struct ModelSidebarView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService

    var body: some View {
        @Bindable var model = appModel

        List {
            Section("Yüklü Modeller") {
                if model.installedModels.isEmpty {
                    ContentUnavailableView {
                        Label("Model yok", systemImage: "brain")
                    } description: {
                        Text("Katalogdan model indirin veya GGUF dosyası içe aktarın.")
                    } actions: {
                        Button("Model Ekle") { model.showCatalog = true }
                    }
                } else {
                    ForEach(model.installedModels) { installed in
                        ModelRowView(model: installed, isSelected: model.selectedModelId == installed.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedModelId = installed.id
                            }
                            .contextMenu {
                                Button("Sil", role: .destructive) {
                                    Task { await model.deleteModel(installed) }
                                }
                            }
                    }
                }
            }

            Section("Sohbetler") {
                if model.sessions.isEmpty {
                    Text("Henüz kayıtlı sohbet yok")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.sessions) { session in
                        HStack {
                            Text(session.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if session.id == model.currentSession.id {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.loadSession(session)
                        }
                        .contextMenu {
                            Button("Sil", role: .destructive) {
                                model.deleteSession(session)
                            }
                        }
                    }
                }
            }

            Section {
                LabeledContent("Disk kullanımı", value: model.diskUsageFormatted)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MacLLM")
        .onChange(of: model.selectedModelId) { _, newId in
            guard let newId,
                  let installed = model.installedModels.first(where: { $0.id == newId }),
                  model.selectedModel?.id != newId || !inferenceService.isModelLoaded else { return }
            Task { await model.selectModel(installed) }
        }
    }
}

struct ModelRowView: View {
    let model: InstalledModel
    let isSelected: Bool

    private var subtitle: String {
        let repo = model.repoId == "imported"
            ? "İçe aktarıldı"
            : model.repoId.split(separator: "/").suffix(2).joined(separator: "/")
        let size = ByteCountFormatter.string(fromByteCount: model.fileSizeBytes, countStyle: .file)
        let quant = ModelMetadataParser.parseQuant(from: model.filename) ?? ""
        if quant.isEmpty {
            return "\(repo) · \(size)"
        }
        return "\(repo) · \(quant) · \(size)"
    }

    var body: some View {
        HStack(spacing: AppTheme.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius))
    }
}

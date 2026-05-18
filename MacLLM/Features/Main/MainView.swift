import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sessionToDelete: ChatSession?
    @State private var modelToDelete: InstalledModel?
    @State private var confirmDeleteCurrentChat = false

    var body: some View {
        @Bindable var model = appModel

        NavigationSplitView(columnVisibility: $columnVisibility) {
            ModelSidebarView(
                sessionToDelete: $sessionToDelete,
                modelToDelete: $modelToDelete
            )
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
                if inferenceService.isModelLoaded {
                    Button {
                        Task { await model.unloadCurrentModel() }
                    } label: {
                        Label("Modeli Çıkar", systemImage: "eject")
                    }
                    .help("Modeli bellekten çıkarır; dosya diskte kalır")
                }
                Button {
                    Task { await model.newChat() }
                } label: {
                    Label("Yeni Sohbet", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                if model.canDeleteCurrentSession {
                    Button(role: .destructive) {
                        confirmDeleteCurrentChat = true
                    } label: {
                        Label("Sohbeti Sil", systemImage: "trash")
                    }
                    .help("Geçerli sohbeti kalıcı olarak siler")
                }
                SettingsLink {
                    Label("Ayarlar", systemImage: "gearshape")
                }
                .help("Ayarlar (⌘,)")
            }
        }
        .sheet(isPresented: $model.showCatalog) {
            ModelCatalogView()
        }
        .confirmationDialog(
            "Bu sohbet silinsin mi?",
            isPresented: $confirmDeleteCurrentChat,
            titleVisibility: .visible
        ) {
            Button("Sohbeti Sil", role: .destructive) {
                Task { await model.deleteSession(model.currentSession) }
            }
            Button("İptal", role: .cancel) {}
        }
        .confirmationDialog(
            "Bu sohbet silinsin mi?",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            presenting: sessionToDelete
        ) { session in
            Button("Sil", role: .destructive) {
                Task { await model.deleteSession(session) }
            }
            Button("İptal", role: .cancel) {
                sessionToDelete = nil
            }
        } message: { session in
            Text("“\(session.title)” kalıcı olarak silinecek.")
        }
        .confirmationDialog(
            "Model diskten silinsin mi?",
            isPresented: Binding(
                get: { modelToDelete != nil },
                set: { if !$0 { modelToDelete = nil } }
            ),
            presenting: modelToDelete
        ) { installed in
            Button("Sil", role: .destructive) {
                Task { await model.deleteModel(installed) }
            }
            Button("İptal", role: .cancel) {
                modelToDelete = nil
            }
        } message: { installed in
            Text("\(installed.name) dosyası silinecek. Bu işlem geri alınamaz.")
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
    @Binding var sessionToDelete: ChatSession?
    @Binding var modelToDelete: InstalledModel?

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
                        let isSelected = model.selectedModelId == installed.id
                        let isLoaded = isSelected
                            && inferenceService.isModelLoaded
                            && inferenceService.loadedModelId == installed.id
                        ModelRowView(
                            model: installed,
                            isSelected: isSelected,
                            isLoadedInMemory: isLoaded,
                            onUnload: { Task { await model.unloadCurrentModel() } }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectedModelId = installed.id
                        }
                        .contextMenu {
                            if isLoaded {
                                Button {
                                    Task { await model.unloadCurrentModel() }
                                } label: {
                                    Label("Bellekten Çıkar", systemImage: "eject")
                                }
                            }
                            Button("Diskten Sil", role: .destructive) {
                                modelToDelete = installed
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
                        HStack(spacing: 8) {
                            Text(session.title)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await model.loadSession(session) }
                                }
                            if session.id == model.currentSession.id {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                sessionToDelete = session
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Sohbeti sil")
                        }
                        .contextMenu {
                            Button("Sil", role: .destructive) {
                                sessionToDelete = session
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
                  let installed = model.installedModels.first(where: { $0.id == newId }) else { return }
            if inferenceService.loadedModelId == newId, inferenceService.isModelLoaded {
                return
            }
            Task { await model.selectModel(installed) }
        }
    }
}

struct ModelRowView: View {
    let model: InstalledModel
    let isSelected: Bool
    var isLoadedInMemory: Bool = false
    var onUnload: (() -> Void)?

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
            if isLoadedInMemory {
                Button {
                    onUnload?()
                } label: {
                    Image(systemName: "eject.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
                .help("Bellekten çıkar")
            } else if isSelected {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Seçili — belleğe almak için dokunun")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius))
    }
}

import SwiftUI
import UniformTypeIdentifiers

enum ModelCatalogTab: String, CaseIterable, Identifiable {
    case hub = "Hub"
    case recommended = "Önerilen"
    case manual = "Manuel"

    var id: String { rawValue }
}

struct ModelCatalogView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    @State private var tab: ModelCatalogTab = .hub
    @State private var showDownloadsPopover = false
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var pendingImportName = ""
    @State private var showOverwriteImportConfirm = false
    @State private var isImportingGGUF = false
    @State private var manualRepoId = ""
    @State private var manualFilename = ""

    var body: some View {
        @Bindable var model = appModel

        NavigationStack {
            VStack(spacing: 0) {
                if !downloadService.activeDownloads.isEmpty {
                    List {
                        ActiveDownloadsPanel(downloadService: downloadService, style: .full)
                    }
                    .listStyle(.inset)
                    .frame(maxHeight: min(220, CGFloat(downloadService.activeDownloads.count) * 88 + 40))
                }

                Picker("Sekme", selection: $tab) {
                    ForEach(ModelCatalogTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.contentPadding)
                .padding(.vertical, 12)

                switch tab {
                case .hub:
                    ModelHubBrowserView()
                case .recommended:
                    recommendedList(model: model)
                case .manual:
                    manualList(model: model)
                }
            }
            .navigationTitle("Model Hub")
            .navigationDestination(for: HFModelSummary.self) { repo in
                HubDetailPane(repo: repo)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    DownloadToolbarButton(
                        downloadService: downloadService,
                        isPresented: $showDownloadsPopover
                    )
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        handleImportSelection(url: url, model: model)
                    }
                case .failure(let error):
                    model.setStatusMessage(UserErrorFormatter.message(for: error), persistent: true)
                }
            }
            .overlay {
                if isImportingGGUF {
                    ZStack {
                        Color.black.opacity(0.25)
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Model kopyalanıyor…")
                                .font(.headline)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.panelRadius))
                    }
                }
            }
            .disabled(isImportingGGUF)
            .alert("Model zaten var", isPresented: $showOverwriteImportConfirm) {
                Button("İptal", role: .cancel) {
                    pendingImportURL = nil
                    pendingImportName = ""
                }
                Button("Üzerine Yaz", role: .destructive) {
                    guard let url = pendingImportURL else { return }
                    startImport(url: url, model: model, replaceExisting: true)
                }
            } message: {
                Text("«\(pendingImportName)» klasörde zaten var. Üzerine yazılsın mı?")
            }
        }
        .frame(minWidth: 980, minHeight: 700)
    }

    private func handleImportSelection(url: URL, model: AppModel) {
        if model.ggufImportDestinationExists(for: url) {
            pendingImportURL = url
            pendingImportName = url.lastPathComponent
            showOverwriteImportConfirm = true
        } else {
            startImport(url: url, model: model, replaceExisting: false)
        }
    }

    private func startImport(url: URL, model: AppModel, replaceExisting: Bool) {
        Task {
            isImportingGGUF = true
            defer {
                isImportingGGUF = false
                pendingImportURL = nil
                pendingImportName = ""
            }
            await model.importGGUF(from: url, replaceExisting: replaceExisting)
        }
    }

    @ViewBuilder
    private func recommendedList(model: AppModel) -> some View {
        let recommendationService = ModelRecommendationService.shared
        List {
            Section {
                Text(recommendationService.guidanceText(profile: model.systemProfile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(recommendationService.sectionTitle(profile: model.systemProfile))
            }

            let ideal = model.modelRecommendations.filter { $0.fit == .ideal }
            if !ideal.isEmpty {
                Section("En uygun") {
                    ForEach(ideal) { scored in
                        CatalogEntryRow(
                            entry: scored.entry,
                            recommendation: scored,
                            isInstalled: !ModelCatalogService.shared.catalogEntryNotInstalled(
                                scored.entry,
                                installed: model.installedModels
                            )
                        )
                    }
                }
            }

            let workable = model.modelRecommendations.filter { $0.fit == .workable }
            if !workable.isEmpty {
                Section("Çalışabilir (bellek için dikkat)") {
                    ForEach(workable) { scored in
                        CatalogEntryRow(
                            entry: scored.entry,
                            recommendation: scored,
                            isInstalled: !ModelCatalogService.shared.catalogEntryNotInstalled(
                                scored.entry,
                                installed: model.installedModels
                            )
                        )
                    }
                }
            }

            let heavy = model.modelRecommendations.filter { $0.fit == .notRecommended }
            if !heavy.isEmpty {
                Section("Bu Mac için genelde uygun değil") {
                    ForEach(heavy) { scored in
                        CatalogEntryRow(
                            entry: scored.entry,
                            recommendation: scored,
                            isInstalled: !ModelCatalogService.shared.catalogEntryNotInstalled(
                                scored.entry,
                                installed: model.installedModels
                            )
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func manualList(model: AppModel) -> some View {
        List {
            Section("GGUF dosyası içe aktar") {
                Button {
                    showImporter = true
                } label: {
                    Label("Dosyadan içe aktar…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Section("Hugging Face bağlantısı") {
                TextField("repo-id (ör. bartowski/Llama-3.2-3B-Instruct-GGUF)", text: $manualRepoId)
                TextField("dosya adı (ör. model.Q4_K_M.gguf)", text: $manualFilename)
                Button("Çevrimiçi indir") {
                    guard !manualRepoId.isEmpty, !manualFilename.isEmpty else { return }
                    let entry = CatalogEntry(
                        id: "manual-\(manualFilename)",
                        name: manualFilename,
                        description: manualRepoId,
                        repoId: manualRepoId,
                        filename: manualFilename,
                        estimatedSizeBytes: 3_000_000_000,
                        chatTemplate: HuggingFaceHubService.guessChatTemplate(
                            repoId: manualRepoId,
                            filename: manualFilename
                        ),
                        ramHintGB: 8
                    )
                    Task { await model.downloadModel(entry) }
                }
                .buttonStyle(AccentPrimaryButtonStyle(disabled: manualRepoId.isEmpty || manualFilename.isEmpty))
                .disabled(manualRepoId.isEmpty || manualFilename.isEmpty)
            }
        }
    }
}

struct CatalogEntryRow: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared
    let entry: CatalogEntry
    var recommendation: ScoredCatalogEntry?
    let isInstalled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.name)
                    .font(.headline)
                Spacer()
                if let recommendation {
                    AppTheme.fitBadge(recommendation.fit)
                }
                if isInstalled {
                    AppTheme.badge("Yüklü", color: .green)
                }
            }
            Text(entry.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let note = recommendation?.fitNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(recommendation?.fit == .notRecommended ? .red : .secondary)
            }
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: entry.estimatedSizeBytes, countStyle: .file))
                Text("·")
                Text("~\(entry.ramHintGB) GB RAM")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            NavigationLink(value: HFModelSummary.hubEntry(repoId: entry.repoId)) {
                Label("Tüm quant seçenekleri…", systemImage: "tablecells")
            }
            .font(.caption)
            .buttonStyle(.link)

            if !isInstalled {
                if let download = downloadService.activeDownloads.first(where: { $0.id == entry.id }),
                   download.state == .downloading || download.state == .paused {
                    DownloadProgressView(
                        download: download,
                        onPause: { downloadService.pauseDownload(id: entry.id) },
                        onResume: { downloadService.resumeDownload(id: entry.id) },
                        onCancel: { downloadService.cancelDownload(id: entry.id) },
                        supportsPause: downloadService.downloadSupportsPause(id: entry.id)
                    )
                } else if let download = downloadService.activeDownloads.first(where: { $0.id == entry.id }),
                          download.state == .failed {
                    Text(download.errorMessage ?? "İndirme başarısız")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Button("Tekrar dene") {
                        Task { await appModel.downloadModel(entry) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Çevrimiçi indir") {
                        Task { await appModel.downloadModel(entry) }
                    }
                    .buttonStyle(AccentPrimaryButtonStyle())
                }
            } else {
                Button("Kullan") {
                    if let model = appModel.installedModels.first(where: { $0.id == entry.id }) {
                        Task {
                            await appModel.selectModel(model)
                            appModel.showCatalog = false
                        }
                    }
                }
                .buttonStyle(AccentPrimaryButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}

import SwiftUI
import UniformTypeIdentifiers

enum ModelCatalogTab: String, CaseIterable, Identifiable {
    case recommended = "Önerilen"
    case online = "Çevrimiçi"
    case manual = "Manuel"

    var id: String { rawValue }
}

struct ModelCatalogView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    @State private var tab: ModelCatalogTab = .recommended
    @State private var showImporter = false
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
                .padding()

                switch tab {
                case .recommended:
                    recommendedList(model: model)
                case .online:
                    OnlineModelSearchView()
                case .manual:
                    manualList(model: model)
                }
            }
            .navigationTitle("Model Ekle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                if !downloadService.activeDownloads.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Label("İndiriliyor", systemImage: "arrow.down.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await model.importGGUF(from: url) }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
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

    private var fitBadge: (text: String, color: Color)? {
        guard let recommendation else { return nil }
        switch recommendation.fit {
        case .ideal:
            return ("En uygun", .green)
        case .workable:
            return ("Dikkat", .orange)
        case .notRecommended:
            return ("Ağır", .red)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.name)
                    .font(.headline)
                Spacer()
                if let fitBadge {
                    Text(fitBadge.text)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(fitBadge.color.opacity(0.15))
                        .foregroundStyle(fitBadge.color)
                        .clipShape(Capsule())
                }
                if isInstalled {
                    Text("Yüklü")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.2))
                        .clipShape(Capsule())
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
                    .controlSize(.small)
                } else {
                    Button("Çevrimiçi indir") {
                        Task { await appModel.downloadModel(entry) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Button("Kullan") {
                    if let model = appModel.installedModels.first(where: { $0.id == entry.id }) {
                        Task { await appModel.selectModel(model) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

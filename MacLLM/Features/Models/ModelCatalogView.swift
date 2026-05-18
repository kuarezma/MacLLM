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

    @State private var tab: ModelCatalogTab = .online
    @State private var showImporter = false
    @State private var manualRepoId = ""
    @State private var manualFilename = ""

    var body: some View {
        @Bindable var model = appModel

        NavigationStack {
            VStack(spacing: 0) {
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
        List {
            Section("M3 MacBook Air · 16 GB için önerilen") {
                ForEach(model.catalogEntries) { entry in
                    CatalogEntryRow(
                        entry: entry,
                        isInstalled: !ModelCatalogService.shared.catalogEntryNotInstalled(
                            entry,
                            installed: model.installedModels
                        )
                    )
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
    let isInstalled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.name)
                    .font(.headline)
                Spacer()
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
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: entry.estimatedSizeBytes, countStyle: .file))
                Text("·")
                Text("~\(entry.ramHintGB) GB RAM")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if !isInstalled {
                if let download = downloadService.activeDownloads.first(where: { $0.id == entry.id }),
                   download.state == .downloading {
                    ProgressView(value: download.progress)
                    HStack {
                        Text(String(format: "%.0f%%", download.progress * 100))
                        Spacer()
                        Button("İptal") {
                            downloadService.cancelDownload(id: entry.id)
                        }
                        .font(.caption)
                    }
                    .font(.caption2)
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
                Button("Yükle") {
                    if let model = appModel.installedModels.first(where: { $0.id == entry.id }) {
                        Task { await appModel.selectModel(model) }
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

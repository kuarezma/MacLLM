import SwiftUI
import AppKit

struct OnlineModelSearchView: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    @State private var searchText = ""
    @State private var results: [HFModelSummary] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var selectedRepo: HFModelSummary?
    @State private var repoDetail: HFRepoDetail?
    @State private var isLoadingFiles = false
    @State private var filesError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            List {
                Section {
                    Text("Popüler GGUF depolarını arayın. Her dosya için Mac uyumu ve quant bilgisi gösterilir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Sonuçlar") {
                    if results.isEmpty && !isSearching {
                        ContentUnavailableView {
                            Label("Arama yapın", systemImage: "cloud")
                        } description: {
                            Text("Örn. \"llama 3\", \"phi-3\", \"mistral 7b\"")
                        }
                    }
                    ForEach(results) { model in
                        Button {
                            Task { await openRepo(model) }
                        } label: {
                            OnlineModelRow(model: model, profile: appModel.systemProfile)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selectedRepo) { repo in
            RepoFilesSheet(
                repo: repo,
                detail: repoDetail,
                isLoading: isLoadingFiles,
                error: filesError,
                profile: appModel.systemProfile,
                downloadService: downloadService,
                onDownload: { file in
                    Task { await downloadFile(repo: repo, file: file, detail: repoDetail) }
                },
                onRefresh: { Task { await loadFiles(for: repo) } }
            )
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Hugging Face'te model ara (ör. llama 3.2, mistral)", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit { scheduleSearch() }
                .onChange(of: searchText) { _, _ in scheduleSearch() }
            if isSearching {
                ProgressView().controlSize(.small)
            } else {
                Button("Ara") { scheduleSearch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            results = try await HuggingFaceHubService.shared.searchModels(query: searchText)
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func openRepo(_ model: HFModelSummary) async {
        selectedRepo = model
        repoDetail = nil
        filesError = nil
        await loadFiles(for: model)
    }

    private func loadFiles(for model: HFModelSummary) async {
        isLoadingFiles = true
        filesError = nil
        defer { isLoadingFiles = false }
        do {
            let detail = try await HuggingFaceHubService.shared.fetchRepoDetail(repoId: model.repoId)
            repoDetail = detail
            if detail.files.isEmpty {
                filesError = "Bu depoda .gguf dosyası bulunamadı."
            }
        } catch {
            filesError = error.localizedDescription
        }
    }

    private func downloadFile(repo: HFModelSummary, file: HFGGUFile, detail: HFRepoDetail?) async {
        if detail?.gated == true || repo.gated {
            let hasToken = !(HuggingFaceCredentials.token ?? "").isEmpty
            if !hasToken {
                filesError = "Gated model — Ayarlar → Hugging Face bölümünden access token ekleyin."
                return
            }
        }
        let entry = CatalogEntry(
            id: "\(repo.repoId)-\(file.filename)",
            name: ModelMetadataParser.repoDisplayName(file.filename),
            description: repo.repoId,
            repoId: repo.repoId,
            filename: file.filename,
            estimatedSizeBytes: max(file.sizeBytes, 1),
            chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: repo.repoId, filename: file.filename),
            ramHintGB: ramHint(for: file.sizeBytes)
        )
        await appModel.downloadModel(entry)
    }

    private func ramHint(for bytes: Int64) -> Int {
        let gb = Double(bytes) / 1_073_741_824.0
        return Int(ceil(gb * 1.4))
    }
}

// MARK: - Search result row

private struct OnlineModelRow: View {
    let model: HFModelSummary
    let profile: MacSystemProfile

    private var fitBadge: (String, Color)? {
        let entry = CatalogEntry(
            id: model.id,
            name: model.repoId,
            description: "",
            repoId: model.repoId,
            filename: "model.Q4_K_M.gguf",
            estimatedSizeBytes: 2_000_000_000,
            chatTemplate: "chatml",
            ramHintGB: estimateRamHint()
        )
        let scored = ModelRecommendationService.shared.recommend(catalog: [entry], profile: profile).first
        guard let scored else { return nil }
        switch scored.fit {
        case .ideal: return ("Uygun", .green)
        case .workable: return ("Çalışır", .orange)
        case .notRecommended: return ("Ağır", .red)
        }
    }

    private func estimateRamHint() -> Int {
        if let param = model.parameterSize, param.hasSuffix("B"),
           let num = Double(param.dropLast()) {
            return Int(ceil(num * 0.7))
        }
        return 8
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(ModelMetadataParser.repoDisplayName(model.repoId))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if model.gated {
                        Text("Gated")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                if let author = ModelMetadataParser.repoAuthor(model.repoId) {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Label(ModelMetadataParser.formatCount(model.downloads), systemImage: "arrow.down.circle")
                    Label(ModelMetadataParser.formatCount(model.likes), systemImage: "heart")
                    if let updated = ModelMetadataParser.relativeDate(model.lastModified) {
                        Text(updated)
                    }
                    if let tag = model.pipelineTag {
                        Text(tag)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if !model.displayTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(model.displayTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }
                        if let param = model.parameterSize {
                            Text(param)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let (label, color) = fitBadge {
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.15))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Repo sheet

private struct RepoFilesSheet: View {
    let repo: HFModelSummary
    let detail: HFRepoDetail?
    let isLoading: Bool
    let error: String?
    let profile: MacSystemProfile
    @ObservedObject var downloadService: HuggingFaceDownloadService
    let onDownload: (HFGGUFile) -> Void
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var files: [HFGGUFile] { detail?.files ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Depo bilgileri yükleniyor…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("Hata", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Tekrar dene", action: onRefresh)
                    }
                } else {
                    List {
                        if let detail {
                            repoHeader(detail)
                        }
                        if !downloadService.activeDownloads.filter({ $0.catalogEntry.repoId == repo.repoId }).isEmpty {
                            Section("Bu depodan indirilenler") {
                                ForEach(downloadService.activeDownloads.filter { $0.catalogEntry.repoId == repo.repoId }) { dl in
                                    ActiveDownloadRowInline(download: dl)
                                }
                            }
                        }
                        ForEach(groupedFiles.keys.sorted(), id: \.self) { group in
                            Section(group) {
                                ForEach(groupedFiles[group] ?? []) { file in
                                    GGUFFileRow(
                                        file: file,
                                        repo: repo,
                                        profile: profile,
                                        isRecommended: file.id == recommendedFileId,
                                        download: downloadService.activeDownloads.first {
                                            $0.catalogEntry.filename == file.filename
                                                && $0.catalogEntry.repoId == repo.repoId
                                        },
                                        gated: detail?.gated == true || repo.gated,
                                        onDownload: { onDownload(file) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(ModelMetadataParser.repoDisplayName(repo.repoId))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let url = HuggingFaceHubService.huggingFaceURL(repoId: repo.repoId) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("HF'de aç", systemImage: "safari")
                        }
                    }
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    @ViewBuilder
    private func repoHeader(_ detail: HFRepoDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Label(ModelMetadataParser.formatCount(detail.downloads), systemImage: "arrow.down.circle")
                    Label(ModelMetadataParser.formatCount(detail.likes), systemImage: "heart")
                    if let tag = detail.pipelineTag {
                        Text(tag)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let license = detail.license {
                    LabeledContent("Lisans", value: license)
                        .font(.caption)
                }

                Text(ModelRecommendationService.shared.guidanceText(profile: profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if detail.gated || repo.gated {
                    Label("Gated model — indirmek için Hugging Face token gerekir (Ayarlar).", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var groupedFiles: [String: [HFGGUFile]] {
        Dictionary(grouping: files) { file in
            file.quantLabel.map { "Quant: \($0)" } ?? "Diğer"
        }
    }

    private var recommendedFileId: String? {
        guard let best = files.first else { return nil }
        let entry = catalogEntry(for: best)
        let fit = ModelRecommendationService.shared.recommend(catalog: [entry], profile: profile).first?.fit
        return fit == .ideal || fit == .workable ? best.id : files.first?.id
    }

    private func catalogEntry(for file: HFGGUFile) -> CatalogEntry {
        CatalogEntry(
            id: "\(repo.repoId)-\(file.filename)",
            name: file.filename,
            description: repo.repoId,
            repoId: repo.repoId,
            filename: file.filename,
            estimatedSizeBytes: max(file.sizeBytes, 1),
            chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: repo.repoId, filename: file.filename),
            ramHintGB: Int(ceil(Double(file.sizeBytes) / 1_073_741_824.0 * 1.4))
        )
    }
}

private struct ActiveDownloadRowInline: View {
    let download: DownloadTaskInfo
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    var body: some View {
        DownloadProgressView(
            download: download,
            onPause: { downloadService.pauseDownload(id: download.id) },
            onResume: { downloadService.resumeDownload(id: download.id) },
            onCancel: { downloadService.cancelDownload(id: download.id) },
            supportsPause: downloadService.downloadSupportsPause(id: download.id)
        )
    }
}

private struct GGUFFileRow: View {
    let file: HFGGUFile
    let repo: HFModelSummary
    let profile: MacSystemProfile
    let isRecommended: Bool
    let download: DownloadTaskInfo?
    let gated: Bool
    let onDownload: () -> Void

    private var fitNote: String? {
        let entry = CatalogEntry(
            id: file.id,
            name: file.filename,
            description: repo.repoId,
            repoId: repo.repoId,
            filename: file.filename,
            estimatedSizeBytes: max(file.sizeBytes, 1),
            chatTemplate: "chatml",
            ramHintGB: Int(ceil(Double(file.sizeBytes) / 1_073_741_824.0 * 1.4))
        )
        return ModelRecommendationService.shared.recommend(catalog: [entry], profile: profile).first?.fitNote
    }

    private var tokenMissing: Bool {
        gated && (HuggingFaceCredentials.token ?? "").isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(file.filename)
                    .font(.subheadline)
                    .lineLimit(2)
                if isRecommended {
                    Text("Önerilen")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 8) {
                if let quant = file.quantLabel {
                    Text(quant)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = fitNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let download, download.state == .downloading || download.state == .paused {
                DownloadProgressView(
                    download: download,
                    onPause: { HuggingFaceDownloadService.shared.pauseDownload(id: download.id) },
                    onResume: { HuggingFaceDownloadService.shared.resumeDownload(id: download.id) },
                    onCancel: { HuggingFaceDownloadService.shared.cancelDownload(id: download.id) },
                    supportsPause: HuggingFaceDownloadService.shared.downloadSupportsPause(id: download.id)
                )
            } else if download?.state == .completed {
                Label("İndirildi", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if download?.state == .failed {
                Text(download?.errorMessage ?? "Hata")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("Tekrar indir", action: onDownload)
                    .controlSize(.small)
            } else {
                Button(tokenMissing ? "Token gerekli" : "İndir", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(tokenMissing)
            }
        }
        .padding(.vertical, 4)
    }
}

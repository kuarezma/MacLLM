import SwiftUI
import AppKit

/// Hugging Face deposu — quant tablosu, README ve etiketler (Hub görünümü).
struct ModelHubDetailView: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    let repo: HFModelSummary

    @State private var detail: HFRepoDetail?
    @State private var readmeText: String?
    @State private var isLoading = true
    @State private var loadError: String?

    private var files: [HFGGUFile] { detail?.files ?? [] }
    private var gated: Bool { detail?.gated == true || repo.gated }

    private var recommendedFileId: String? {
        guard !files.isEmpty else { return nil }
        let profile = appModel.systemProfile
        let scored = files.map { file -> (HFGGUFile, ModelFitLevel?) in
            let entry = catalogEntry(for: file)
            let fit = ModelRecommendationService.shared.recommend(catalog: [entry], profile: profile).first?.fit
            return (file, fit)
        }
        if let ideal = scored.first(where: { $0.1 == .ideal })?.0 { return ideal.id }
        if let workable = scored.first(where: { $0.1 == .workable })?.0 { return workable.id }
        return files.first?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    ProgressView("Depo yükleniyor…")
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Yüklenemedi", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Tekrar dene") { Task { await loadRepo() } }
                    }
                    .padding(40)
                } else {
                    quantTable
                    readmeSection
                }
            }
        }
        .navigationTitle(ModelMetadataParser.repoDisplayName(repo.repoId))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let url = HuggingFaceHubService.huggingFaceURL(repoId: repo.repoId) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Hugging Face", systemImage: "safari")
                    }
                }
                Button {
                    Task { await loadRepo() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Yenile")
            }
        }
        .task { await loadRepo() }
    }

    // MARK: - Quant table

    @ViewBuilder
    private var quantTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let detail {
                repoMetaBar(detail)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    headerCell("Model")
                    headerCell("Format")
                    headerCell("Dosya boyutu")
                    headerCell("")
                    headerCell("")
                        .frame(width: 120, alignment: .trailing)
                }
                .padding(.vertical, 8)

                Divider()

                if files.isEmpty {
                    Text("Bu depoda .gguf dosyası bulunamadı.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                } else {
                    ForEach(files) { file in
                        HubQuantRowView(
                            file: file,
                            repo: repo,
                            profile: appModel.systemProfile,
                            download: downloadService.activeDownloads.first {
                                $0.catalogEntry.filename == file.filename
                                    && $0.catalogEntry.repoId == repo.repoId
                            },
                            gated: gated,
                            isRecommended: file.id == recommendedFileId,
                            onDownload: { Task { await download(file) } }
                        )
                        if file.id != files.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func headerCell(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private func repoMetaBar(_ detail: HFRepoDetail) -> some View {
        HStack(spacing: 16) {
            Label(ModelMetadataParser.formatCount(detail.downloads), systemImage: "arrow.down.circle")
            Label(ModelMetadataParser.formatCount(detail.likes), systemImage: "heart")
            if let tag = detail.pipelineTag {
                Text(tag)
            }
            if gated {
                AppTheme.badge("Gated", color: .orange)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)

        if gated && (HuggingFaceCredentials.token ?? "").isEmpty {
            Label("İndirmek için Ayarlar → Hugging Face token gerekir.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    // MARK: - README

    @ViewBuilder
    private var readmeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.horizontal, 20)

            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text("README")
                    .font(.headline)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if let tags = detail?.tags, !tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("tags:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayoutTags(tags: ModelMetadataParser.displayTags(tags))
                }
                .padding(.horizontal, 20)
            }

            if let readmeText, !readmeText.isEmpty {
                Text(readmePreview(readmeText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            } else if !isLoading {
                Text("README bulunamadı.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
            }

            if let url = HuggingFaceHubService.huggingFaceURL(repoId: repo.repoId) {
                Link("Tam README — Hugging Face'te aç", destination: url)
                    .font(.caption)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
    }

    private func readmePreview(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let head = lines.prefix(40).joined(separator: "\n")
        return head.count > 4000 ? String(head.prefix(4000)) + "…" : head
    }

    // MARK: - Actions

    private func loadRepo() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let detailTask = HuggingFaceHubService.shared.fetchRepoDetail(repoId: repo.repoId)
            async let readmeTask = HuggingFaceHubService.shared.fetchReadme(repoId: repo.repoId)
            let (fetchedDetail, fetchedReadme) = try await (detailTask, readmeTask)
            detail = fetchedDetail
            readmeText = fetchedReadme
            if fetchedDetail.files.isEmpty {
                loadError = "Bu depoda .gguf dosyası bulunamadı."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func download(_ file: HFGGUFile) async {
        if gated && (HuggingFaceCredentials.token ?? "").isEmpty {
            loadError = "Gated model — Ayarlar'dan Hugging Face token ekleyin."
            return
        }
        await appModel.downloadModel(catalogEntry(for: file))
    }

    private func catalogEntry(for file: HFGGUFile) -> CatalogEntry {
        CatalogEntry(
            id: "\(repo.repoId)-\(file.filename)",
            name: ModelMetadataParser.repoDisplayName(file.filename),
            description: repo.repoId,
            repoId: repo.repoId,
            filename: file.filename,
            estimatedSizeBytes: max(file.sizeBytes, 1),
            chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: repo.repoId, filename: file.filename),
            ramHintGB: Int(ceil(Double(file.sizeBytes) / 1_073_741_824.0 * 1.4))
        )
    }
}

/// README etiketleri — yatay akış.
private struct FlowLayoutTags: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    AppTheme.tagBadge(tag)
                }
            }
        }
    }
}

extension HFModelSummary {
    static func hubEntry(repoId: String, tags: [String] = [], gated: Bool = false) -> HFModelSummary {
        HFModelSummary(
            id: repoId,
            repoId: repoId,
            downloads: 0,
            likes: 0,
            pipelineTag: nil,
            tags: tags,
            lastModified: nil,
            gated: gated
        )
    }
}

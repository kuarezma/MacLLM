import SwiftUI
import AppKit

@MainActor
final class ModelHubDetailUIState: ObservableObject {
    @Published var detail: HFRepoDetail?
    @Published var readmeText: String?
    @Published var isLoading = true
    @Published var loadError: String?
    @Published var sortOrder: HubQuantSort = .recommended
    @Published var quantFilter: HubQuantFilter = .all
    @Published var readmeExpanded = false
    @Published var fileSearchText = ""
}

/// Hugging Face deposu — quant tablosu, README ve etiketler (Hub görünümü).
struct ModelHubDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    let repo: HFModelSummary
    @StateObject private var ui = ModelHubDetailUIState()
    @Environment(\.presentationMode) private var presentationMode

    private var files: [HFGGUFile] { ui.detail?.files ?? [] }
    private var modelFiles: [HFGGUFile] { files.filter(\.isModelWeights) }
    private var mmprojFile: HFGGUFile? { MmprojDiscovery.findInRepo(files: files) }
    private var gated: Bool { ui.detail?.gated == true || repo.gated }

    private var fitLevelsByFileId: [String: ModelFitLevel] {
        let profile = appModel.systemProfile
        var map: [String: ModelFitLevel] = [:]
        for file in modelFiles {
            let entry = catalogEntry(for: file)
            if let fit = ModelRecommendationService.shared.recommend(catalog: [entry], profile: profile).first?.fit {
                map[file.id] = fit
            }
        }
        return map
    }

    private var displayedFiles: [HFGGUFile] {
        HubFileListLogic.filterAndSort(
            files: modelFiles,
            filter: ui.quantFilter,
            sort: ui.sortOrder,
            fitLevels: fitLevelsByFileId,
            searchQuery: ui.fileSearchText
        )
    }

    private func installedModel(for file: HFGGUFile) -> InstalledModel? {
        appModel.installedModels.first { model in
            model.filename == file.filename
                && (model.repoId == repo.repoId || model.id == "\(repo.repoId)-\(file.filename)")
        }
    }

    private var recommendedFileId: String? {
        guard !files.isEmpty else { return nil }
        if let ideal = files.first(where: { fitLevelsByFileId[$0.id] == .ideal }) { return ideal.id }
        if let workable = files.first(where: { fitLevelsByFileId[$0.id] == .workable }) { return workable.id }
        return files.first?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if ui.isLoading {
                    ProgressView("Depo yükleniyor…")
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else if let loadError = ui.loadError {
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
        .navigationSubtitle(repo.parameterSizeDisplay ?? "")
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
            if let detail = ui.detail {
                repoMetaBar(detail)
            }

            quantControlsBar

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    sortableHeader(.model)
                    headerCell("Format")
                    sortableHeader(.size)
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
                } else if displayedFiles.isEmpty {
                    Text(
                        ui.fileSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Seçilen filtreye uygun quant yok."
                            : "Aramanızla eşleşen quant yok."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
                } else {
                    ForEach(displayedFiles) { file in
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
                            installedModel: installedModel(for: file),
                            onDownload: { Task { await download(file) } },
                            onUse: {
                                Task {
                                    if let model = installedModel(for: file) {
                                        await appModel.selectModel(model)
                                        appModel.showCatalog = false
                                        presentationMode.wrappedValue.dismiss()
                                    }
                                }
                            }
                        )
                        if file.id != displayedFiles.last?.id {
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
    private var quantControlsBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Quant veya dosya adı ara…", text: $ui.fileSearchText)
                    .textFieldStyle(.roundedBorder)
                if !ui.fileSearchText.isEmpty {
                    Button {
                        ui.fileSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HubQuantFilter.allCases) { filter in
                        Button {
                            ui.quantFilter = filter
                        } label: {
                            Text(filter.label)
                                .font(.caption)
                                .fontWeight(ui.quantFilter == filter ? .semibold : .regular)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    ui.quantFilter == filter
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.primary.opacity(0.06)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                Picker("Sırala", selection: $ui.sortOrder) {
                    ForEach(HubQuantSort.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                Text("\(displayedFiles.count) / \(files.count) dosya")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if recommendedFileId != nil, ui.quantFilter != .macFriendly {
                    Button("Önerilene git") {
                        ui.quantFilter = .all
                        ui.sortOrder = .recommended
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
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
    private func sortableHeader(_ column: HubTableColumn) -> some View {
        Button {
            ui.sortOrder = HubFileListLogic.sortForColumnTap(column, current: ui.sortOrder)
        } label: {
            HStack(spacing: 4) {
                Text(column.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        HubFileListLogic.isActiveSort(ui.sortOrder, for: column) ? Color.accentColor : .secondary
                    )
                    .textCase(.uppercase)
                if HubFileListLogic.isActiveSort(ui.sortOrder, for: column) {
                    Image(systemName: sortIndicator(for: ui.sortOrder, column: column))
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Sıralamak için tıklayın")
    }

    private func sortIndicator(for sort: HubQuantSort, column: HubTableColumn) -> String {
        switch column {
        case .size:
            return sort == .sizeAscending ? "chevron.up" : "chevron.down"
        case .model:
            switch sort {
            case .quantAscending, .name: return "chevron.up"
            case .quantDescending: return "chevron.down"
            default: return "chevron.up"
            }
        }
    }

    @ViewBuilder
    private func repoMetaBar(_ detail: HFRepoDetail) -> some View {
        HStack(spacing: 16) {
            if let badge = detail.parameterSizeBadge {
                AppTheme.badge(badge, color: AppTheme.accent)
            }
            if let paramDisplay = detail.parameterSizeDisplay {
                Label(paramDisplay, systemImage: "cpu")
            }
            Label(ModelMetadataParser.formatCount(detail.downloads), systemImage: "arrow.down.circle")
            Label(ModelMetadataParser.formatCount(detail.likes), systemImage: "heart")
            if let tag = detail.pipelineTag {
                Text(tag)
            }
            if gated {
                AppTheme.badge("Kilitli", color: .orange)
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

            if let tags = ui.detail?.tags, !tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("tags:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayoutTags(tags: ModelMetadataParser.displayTags(tags))
                }
                .padding(.horizontal, 20)
            }

            if let readmeText = ui.readmeText, !readmeText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ReadmeMarkdownView(
                        markdown: ui.readmeExpanded ? readmeText : readmePreview(readmeText),
                        maxHeight: ui.readmeExpanded ? 560 : 320
                    )
                    if readmeText.count > 3200 || readmeText.components(separatedBy: "\n").count > 40 {
                        Button(ui.readmeExpanded ? "Daha az göster" : "Tamamını göster") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                ui.readmeExpanded.toggle()
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
                .padding(.horizontal, 20)
            } else if !ui.isLoading {
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
        let head = lines.prefix(28).joined(separator: "\n")
        if head.count > 2800 { return String(head.prefix(2800)) + "\n\n…" }
        return head
    }

    // MARK: - Actions

    private func loadRepo() async {
        ui.isLoading = true
        ui.loadError = nil
        defer { ui.isLoading = false }
        do {
            async let detailTask = HuggingFaceHubService.shared.fetchRepoDetail(repoId: repo.repoId)
            async let readmeTask = HuggingFaceHubService.shared.fetchReadme(repoId: repo.repoId)
            let (fetchedDetail, fetchedReadme) = try await (detailTask, readmeTask)
            ui.detail = fetchedDetail
            ui.readmeText = fetchedReadme
            if fetchedDetail.files.isEmpty {
                ui.loadError = "Bu depoda .gguf dosyası bulunamadı."
            }
        } catch {
            ui.loadError = UserErrorFormatter.details(for: error).displayText
        }
    }

    private func download(_ file: HFGGUFile) async {
        if gated && (HuggingFaceCredentials.token ?? "").isEmpty {
            ui.loadError = "Kilitli model — Ayarlar'dan Hugging Face token ekleyin."
            return
        }
        await appModel.downloadModel(
            catalogEntry(for: file),
            companionMmproj: file.isModelWeights ? mmprojFile.map(catalogEntry(for:)) : nil
        )
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

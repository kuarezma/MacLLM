import SwiftUI
import AppKit

/// LM Studio tarzı split Hub — sol arama listesi, sağ detay paneli.
@MainActor
struct ModelHubBrowserView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [HFModelSummary] = []
    @State private var selectedRepo: HFModelSummary?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var sortOrder: HubSearchSort = .bestMatch
    @State private var searchTask: Task<Void, Never>?

    private let sidebarWidth: CGFloat = 340

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
            Divider()
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.chatBackground)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(12)

            filterBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            if isSearching, results.isEmpty {
                Spacer()
                ProgressView("Aranıyor…")
                Spacer()
            } else if results.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("Model ara", systemImage: "magnifyingglass")
                } description: {
                    Text("Örn. phi, llama, qwen, mistral")
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { model in
                            HubSearchResultRow(
                                model: model,
                                isSelected: selectedRepo?.id == model.id,
                                profile: appModel.systemProfile
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedRepo = model }
                            Divider().padding(.leading, HubSearchRowLayout.dividerLeadingInset)
                        }
                    }
                }
            }

            footerBar
        }
        .background(AppTheme.sidebarBackground)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)
            TextField("Model ara…", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit { scheduleSearch() }
                .onChange(of: searchText) { _, _ in scheduleSearch() }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    scheduleSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            if isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.composerBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.searchFieldRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.searchFieldRadius, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Text("\(results.count) model")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            Spacer()

            AppTheme.badge("GGUF", color: .blue)

            Menu {
                ForEach(HubSearchSort.allCases) { sort in
                    Button {
                        sortOrder = sort
                        scheduleSearch()
                    } label: {
                        if sortOrder == sort {
                            Label(sort.label, systemImage: "checkmark")
                        } else {
                            Text(sort.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sortOrder.label)
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var footerBar: some View {
        HStack {
            let count = appModel.installedModels.count
            let bytes = appModel.installedModels.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
            Text("\(count) yerel model · \(ModelMetadataParser.formatFileSize(bytes: bytes))")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.elevatedSurface)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let selectedRepo {
            HubDetailPane(repo: selectedRepo, onUseModel: { dismiss() })
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.5))
                Text("Detay için bir model seçin")
                    .font(.headline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count < 2 {
            results = []
            selectedRepo = nil
            searchError = nil
            isSearching = false
            return
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let fetched = try await HuggingFaceHubService.shared.searchModels(
                query: query,
                sort: sortOrder
            )
            results = fetched
            if selectedRepo == nil || !fetched.contains(where: { $0.id == selectedRepo?.id }) {
                selectedRepo = fetched.first
            }
        } catch {
            searchError = error.localizedDescription
        }
    }
}

// MARK: - Search list layout

private enum HubSearchRowLayout {
    static let avatarSize: CGFloat = 40
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let avatarSpacing: CGFloat = 10
    static let rowHeight: CGFloat = 98
    static let contentHeight: CGFloat = 82
    static let titleHeight: CGFloat = 16
    static let authorHeight: CGFloat = 13
    static let blurbHeight: CGFloat = 28
    static let statsHeight: CGFloat = 16
    static let rowSpacing: CGFloat = 3

    static var dividerLeadingInset: CGFloat {
        horizontalPadding + avatarSize + avatarSpacing
    }
}

// MARK: - Search result row

private struct HubSearchResultRow: View {
    let model: HFModelSummary
    let isSelected: Bool
    let profile: MacSystemProfile

    private var fitLevel: ModelFitLevel? {
        let entry = CatalogEntry(
            id: model.id,
            name: model.displayName,
            description: "",
            repoId: model.repoId,
            filename: "model.Q4_K_M.gguf",
            estimatedSizeBytes: 2_000_000_000,
            chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: model.repoId, filename: "model.Q4_K_M.gguf"),
            ramHintGB: 8
        )
        return ModelRecommendationService.shared.recommend(catalog: [entry], profile: profile).first?.fit
    }

    private var isVerified: Bool {
        model.downloads >= 10_000 || ["microsoft", "meta-llama", "mistralai", "google", "qwen"].contains(model.author?.lowercased() ?? "")
    }

    var body: some View {
        HStack(alignment: .top, spacing: HubSearchRowLayout.avatarSpacing) {
            HubModelAvatarView(repoId: model.repoId, size: HubSearchRowLayout.avatarSize)

            VStack(alignment: .leading, spacing: HubSearchRowLayout.rowSpacing) {
                Text(model.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: HubSearchRowLayout.titleHeight, maxHeight: HubSearchRowLayout.titleHeight, alignment: .leading)

                Text(model.author ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(model.author == nil ? 0 : 1)
                    .frame(maxWidth: .infinity, minHeight: HubSearchRowLayout.authorHeight, maxHeight: HubSearchRowLayout.authorHeight, alignment: .leading)

                Text(model.shortBlurb)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: HubSearchRowLayout.blurbHeight, maxHeight: HubSearchRowLayout.blurbHeight, alignment: .topLeading)

                HStack(spacing: 0) {
                    HubSearchParamSlot(badge: model.parameterSizeBadge)

                    HubSearchStatLabel(
                        systemImage: "arrow.down.circle",
                        value: ModelMetadataParser.formatCount(model.downloads),
                        width: 52
                    )

                    HubSearchStatLabel(
                        systemImage: "heart",
                        value: ModelMetadataParser.formatCount(model.likes),
                        width: 44
                    )

                    HubSearchFitSlot(fitLevel: fitLevel)

                    Spacer(minLength: 0)

                    HubSearchStatusIcons(isVerified: isVerified, isGated: model.gated)
                }
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: HubSearchRowLayout.statsHeight, maxHeight: HubSearchRowLayout.statsHeight, alignment: .leading)
            }
            .frame(height: HubSearchRowLayout.contentHeight, alignment: .top)
        }
        .padding(.horizontal, HubSearchRowLayout.horizontalPadding)
        .padding(.vertical, HubSearchRowLayout.verticalPadding)
        .frame(height: HubSearchRowLayout.rowHeight, alignment: .top)
        .background(isSelected ? AppTheme.accent.opacity(0.12) : Color.clear)
    }
}

private struct HubSearchParamSlot: View {
    let badge: String?

    var body: some View {
        Group {
            if let badge {
                AppTheme.badge(badge, color: AppTheme.accent)
            } else {
                Color.clear
            }
        }
        .frame(width: 38, alignment: .leading)
    }
}

private struct HubSearchStatLabel: View {
    let systemImage: String
    let value: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
                .frame(width: 10)
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
                .monospacedDigit()
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct HubSearchFitSlot: View {
    let fitLevel: ModelFitLevel?

    var body: some View {
        Group {
            if let fitLevel {
                AppTheme.fitBadge(fitLevel)
            } else {
                Color.clear
            }
        }
        .frame(width: 58, alignment: .leading)
    }
}

private struct HubSearchStatusIcons: View {
    let isVerified: Bool
    let isGated: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .opacity(isVerified ? 1 : 0)
                .frame(width: 12)

            Text("Gated")
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .foregroundStyle(.orange)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
                .opacity(isGated ? 1 : 0)
                .frame(width: 42)
        }
    }
}

@MainActor
struct HubDetailPane: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared

    let repo: HFModelSummary
    var onUseModel: (() -> Void)?

    @State private var detail: HFRepoDetail?
    @State private var readmeText: String?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedFileId: String?
    @State private var readmeExpanded = false

    private var files: [HFGGUFile] { detail?.files ?? [] }
    private var modelFiles: [HFGGUFile] { files.filter(\.isModelWeights) }
    private var mmprojFile: HFGGUFile? { MmprojDiscovery.findInRepo(files: files) }
    private var gated: Bool { detail?.gated == true || repo.gated }

    private var fitLevelsByFileId: [String: ModelFitLevel] {
        Dictionary(uniqueKeysWithValues: assessmentsByFileId.map { ($0.key, $0.value.fit) })
    }

    private var assessmentsByFileId: [String: HubQuantAssessment] {
        Dictionary(uniqueKeysWithValues: modelFiles.map { file in
            (
                file.id,
                HubQuantAdvisor.assess(
                    file: file,
                    repoId: repo.repoId,
                    profile: appModel.systemProfile
                )
            )
        })
    }

    private var recommendedFile: HFGGUFile? {
        guard !modelFiles.isEmpty else { return nil }
        if let id = selectedFileId, let file = modelFiles.first(where: { $0.id == id }) { return file }
        if let ideal = modelFiles.first(where: { fitLevelsByFileId[$0.id] == .ideal }) { return ideal }
        if let workable = modelFiles.first(where: { fitLevelsByFileId[$0.id] == .workable }) { return workable }
        return modelFiles.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("Depo yükleniyor…")
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else if let loadError {
                    ContentUnavailableView("Yüklenemedi", systemImage: "exclamationmark.triangle", description: Text(loadError))
                        .padding(40)
                } else {
                    headerSection
                    metadataGrid
                    capabilitiesSection
                    downloadSection
                    readmeSection
                }
            }
            .padding(24)
        }
        .task(id: repo.id) { await loadRepo() }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                HubModelAvatarView(repoId: repo.repoId, size: 56)

                VStack(alignment: .leading, spacing: 6) {
                    Text(repo.displayName)
                        .font(.title2.weight(.semibold))

                    HStack(spacing: 6) {
                        Text(repo.repoId)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(repo.repoId, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Kopyala")
                    }
                }

                Spacer()

                if let url = HuggingFaceHubService.huggingFaceURL(repoId: repo.repoId) {
                    Link(destination: url) {
                        Label("HF", systemImage: "safari")
                            .font(.caption)
                    }
                }
            }

            HStack(spacing: 16) {
                Label(ModelMetadataParser.formatCount(detail?.downloads ?? repo.downloads), systemImage: "arrow.down.circle")
                Label(ModelMetadataParser.formatCount(detail?.likes ?? repo.likes), systemImage: "heart")
                if let updated = ModelMetadataParser.relativeDate(repo.lastModified) {
                    Label(updated, systemImage: "clock")
                }
                if gated {
                    AppTheme.badge("Gated", color: .orange)
                }
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)

            if let description = detail?.description ?? repo.summary, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var metadataGrid: some View {
        HStack(spacing: 12) {
            if let params = repo.parameterSizeBadge ?? detail?.parameterSizeBadge {
                HubMetaChip(title: "Params", value: params)
            }
            if let arch = repo.architecture {
                HubMetaChip(title: "Arch", value: arch)
            }
            if let domain = detail?.pipelineTag ?? repo.pipelineTag {
                HubMetaChip(title: "Domain", value: domain)
            }
            HubMetaChip(title: "Format", value: "GGUF", accent: .blue)
            if let license = detail?.license {
                HubMetaChip(title: "License", value: license)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var capabilitiesSection: some View {
        let caps = ModelMetadataParser.capabilityTags(from: detail?.tags ?? repo.tags)
        if !caps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Capabilities")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    ForEach(caps, id: \.self) { cap in
                        HStack(spacing: 4) {
                            Image(systemName: capabilityIcon(cap))
                                .font(.caption)
                            Text(cap)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.elevatedSurface)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("İndirme Seçenekleri")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)

            Text("Quant seçin — dosya boyutu ve \(appModel.systemProfile.physicalMemoryGB) GB RAM'inize göre uygunluk gösterilir.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            if modelFiles.isEmpty {
                Text("Bu depoda .gguf dosyası bulunamadı.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            } else if gated && (HuggingFaceCredentials.token ?? "").isEmpty {
                Label("Gated model — Ayarlar'dan Hugging Face token ekleyin.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                downloadPicker
                if mmprojFile != nil {
                    Label("Vision: mmproj dosyası indirme ile birlikte otomatik eklenir.", systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                if let file = recommendedFile, let assessment = assessmentsByFileId[file.id] {
                    HubQuantFitCard(assessment: assessment, profile: appModel.systemProfile)
                }
                downloadActions
            }
        }
        .padding(16)
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
    }

    @ViewBuilder
    private var downloadPicker: some View {
        Menu {
            ForEach(modelFiles) { file in
                let assessment = assessmentsByFileId[file.id]
                Button {
                    selectedFileId = file.id
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(HubFileListLogic.displayName(for: file))
                            Spacer()
                            Text(ModelMetadataParser.formatFileSize(bytes: file.sizeBytes))
                        }
                        if let assessment {
                            HStack(spacing: 6) {
                                Text(assessment.fitTitle)
                                Text("· ~\(assessment.estimatedRamGB) GB RAM")
                            }
                            .font(.caption2)
                        }
                    }
                }
            }
        } label: {
            HStack {
                if let file = recommendedFile, let assessment = assessmentsByFileId[file.id] {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            AppTheme.badge("GGUF", color: .blue)
                            if let quant = file.quantLabel {
                                AppTheme.badge(quant, color: AppTheme.accent)
                            }
                            Text(HubFileListLogic.displayName(for: file))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(ModelMetadataParser.formatFileSize(bytes: file.sizeBytes))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Text(assessment.fitTitle)
                            .font(.caption)
                            .foregroundStyle(assessment.fit == .notRecommended ? .red : AppTheme.secondaryText)
                    }
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.composerBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var downloadActions: some View {
        if let file = recommendedFile {
            let installed = installedModel(for: file)
            let activeDownload = downloadService.activeDownloads.first {
                $0.catalogEntry.filename == file.filename && $0.catalogEntry.repoId == repo.repoId
            }

            HStack(spacing: 12) {
                if let fit = fitLevelsByFileId[file.id] {
                    AppTheme.fitBadge(fit)
                }
                if let quant = file.quantLabel {
                    AppTheme.badge(quant, color: AppTheme.secondaryText)
                }

                Spacer()

                if let installed {
                    Button("Kullan") {
                        Task {
                            await appModel.selectModel(installed)
                            onUseModel?()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                } else if let activeDownload, activeDownload.state == .downloading || activeDownload.state == .paused {
                    DownloadProgressView(
                        download: activeDownload,
                        onPause: { downloadService.pauseDownload(id: activeDownload.id) },
                        onResume: { downloadService.resumeDownload(id: activeDownload.id) },
                        onCancel: { downloadService.cancelDownload(id: activeDownload.id) },
                        supportsPause: downloadService.downloadSupportsPause(id: activeDownload.id)
                    )
                    .frame(maxWidth: 280)
                } else {
                    Button("İndir") {
                        Task { await download(file) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var readmeSection: some View {
        if let readmeText, !readmeText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Model Card")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .textCase(.uppercase)

                ReadmeMarkdownView(
                    markdown: readmeExpanded ? readmeText : String(readmeText.prefix(2000)),
                    maxHeight: readmeExpanded ? 480 : 240
                )

                if readmeText.count > 2000 {
                    Button(readmeExpanded ? "Daha az" : "Tamamını göster") {
                        withAnimation { readmeExpanded.toggle() }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }
        }
    }

    private func capabilityIcon(_ cap: String) -> String {
        switch cap {
        case "Tool Use": return "wrench.and.screwdriver"
        case "Reasoning": return "brain"
        case "Vision": return "eye"
        default: return "bubble.left"
        }
    }

    private func installedModel(for file: HFGGUFile) -> InstalledModel? {
        appModel.installedModels.first {
            $0.filename == file.filename && ($0.repoId == repo.repoId || $0.id == "\(repo.repoId)-\(file.filename)")
        }
    }

    private func loadRepo() async {
        isLoading = true
        loadError = nil
        selectedFileId = nil
        defer { isLoading = false }
        do {
            async let detailTask = HuggingFaceHubService.shared.fetchRepoDetail(repoId: repo.repoId)
            async let readmeTask = HuggingFaceHubService.shared.fetchReadme(repoId: repo.repoId)
            let (fetchedDetail, fetchedReadme) = try await (detailTask, readmeTask)
            detail = fetchedDetail
            readmeText = fetchedReadme
            if let best = recommendedFileIdAfterLoad(files: fetchedDetail.files) {
                selectedFileId = best
            }
            if fetchedDetail.files.isEmpty {
                loadError = "Bu depoda .gguf dosyası bulunamadı."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func recommendedFileIdAfterLoad(files: [HFGGUFile]) -> String? {
        let weights = files.filter(\.isModelWeights)
        guard !weights.isEmpty else { return nil }
        let fitLevels = Dictionary(uniqueKeysWithValues: weights.map { file in
            let fit = HubQuantAdvisor.assess(
                file: file,
                repoId: repo.repoId,
                profile: appModel.systemProfile
            ).fit
            return (file.id, fit)
        })
        return HubFileListLogic.filterAndSort(
            files: weights,
            filter: .all,
            sort: .recommended,
            fitLevels: fitLevels
        ).first?.id
    }

    private func download(_ file: HFGGUFile) async {
        let companion = mmprojCompanion(for: file)
        await appModel.downloadModel(
            catalogEntry(for: file),
            companionMmproj: companion.map(catalogEntry(for:))
        )
    }

    private func mmprojCompanion(for file: HFGGUFile) -> HFGGUFile? {
        guard file.isModelWeights, let mmprojFile else { return nil }
        return mmprojFile
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
            ramHintGB: HubQuantAdvisor.estimatedRamGB(for: file)
        )
    }
}

private struct HubMetaChip: View {
    let title: String
    let value: String
    var accent: Color = AppTheme.primaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

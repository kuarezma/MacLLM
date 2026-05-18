import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @ObservedObject private var downloadService = HuggingFaceDownloadService.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sessionToDelete: ChatSession?
    @State private var modelToDelete: InstalledModel?
    @State private var confirmDeleteCurrentChat = false
    @State private var showDownloadsPopover = false
    @State private var sidebarSearchFocused = false

    var body: some View {
        @Bindable var model = appModel

        NavigationSplitView(columnVisibility: $columnVisibility) {
            JanSidebarView(
                sessionToDelete: $sessionToDelete,
                modelToDelete: $modelToDelete,
                showDownloadsPopover: $showDownloadsPopover
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: AppTheme.sidebarWidth, max: 320)
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
                DownloadToolbarButton(
                    downloadService: downloadService,
                    isPresented: $showDownloadsPopover
                )
            }
        }
        .sheet(isPresented: $model.showCatalog) {
            ModelCatalogView()
        }
        .sheet(isPresented: $model.showNewProjectSheet) {
            NewProjectSheet()
                .environment(appModel)
        }
        .sheet(isPresented: $model.showSystemPromptSheet) {
            SystemPromptSheet()
                .environment(appModel)
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
            Button("İptal", role: .cancel) { sessionToDelete = nil }
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
            Button("İptal", role: .cancel) { modelToDelete = nil }
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

// MARK: - Jan-style sidebar

struct JanSidebarView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService
    @Environment(\.openSettings) private var openSettings
    @Binding var sessionToDelete: ChatSession?
    @Binding var modelToDelete: InstalledModel?
    @Binding var showDownloadsPopover: Bool

    @State private var sessionSearchText = ""
    @State private var searchedSessions: [ChatSession] = []
    @State private var modelsExpanded = false
    @FocusState private var sessionSearchFocused: Bool

    private var sessionsToShow: [ChatSession] {
        sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? appModel.filteredSessions
            : searchedSessions
    }

    var body: some View {
        @Bindable var model = appModel

        List {
            Section {
                sidebarNavRow("square.and.pencil", title: "Yeni Sohbet", shortcut: "⌘N") {
                    Task { await model.newChat() }
                }
                sidebarNavRow("folder.badge.plus", title: "Yeni Proje", shortcut: "⌘P") {
                    model.showNewProjectSheet = true
                }
                sidebarNavRow("magnifyingglass", title: "Ara", shortcut: "⌘K") {
                    sessionSearchFocused = true
                }
                sidebarNavRow("square.grid.2x2", title: "Hub") {
                    model.showCatalog = true
                }
                sidebarNavRow("gearshape", title: "Ayarlar", shortcut: "⌘,") {
                    openSettings()
                }
            }

            if !model.projects.isEmpty {
                Section("Projeler") {
                    Button {
                        model.selectedProjectId = nil
                    } label: {
                        HStack {
                            Image(systemName: "tray.full")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            Text("Tüm sohbetler")
                                .foregroundStyle(AppTheme.primaryText)
                            Spacer()
                            if model.selectedProjectId == nil {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(model.projects) { project in
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(project.name)
                                .lineLimit(1)
                                .fontWeight(model.selectedProjectId == project.id ? .semibold : .regular)
                            Spacer()
                            if model.selectedProjectId == project.id {
                                Circle()
                                    .fill(AppTheme.accent)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectedProjectId = project.id
                        }
                        .contextMenu {
                            Button("Sil", role: .destructive) {
                                model.deleteProject(project)
                            }
                        }
                    }
                }
            }

            Section("Sohbetler") {
                TextField("Sohbetlerde ara…", text: $sessionSearchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($sessionSearchFocused)
                    .onChange(of: sessionSearchText) { _, query in
                        performSessionSearch(query: query)
                    }

                if model.sessions.isEmpty {
                    Text("Henüz sohbet yok")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                } else if sessionsToShow.isEmpty {
                    Text("Eşleşme yok")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ForEach(sessionsToShow) { session in
                        HStack(spacing: 8) {
                            Text(session.title)
                                .lineLimit(1)
                                .fontWeight(session.id == model.currentSession.id ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await model.loadSession(session) }
                                }
                            if session.id == model.currentSession.id {
                                Circle()
                                    .fill(AppTheme.accent)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .contextMenu {
                            Menu("Projeye taşı") {
                                Button("Proje yok") {
                                    Task { await model.assignSession(session.id, to: nil) }
                                }
                                ForEach(model.projects) { project in
                                    Button(project.name) {
                                        Task { await model.assignSession(session.id, to: project.id) }
                                    }
                                }
                            }
                            Button("Sil", role: .destructive) {
                                sessionToDelete = session
                            }
                        }
                    }
                }
            }

            Section {
                DisclosureGroup("Modeller", isExpanded: $modelsExpanded) {
                    if model.installedModels.isEmpty {
                        Button("Model Hub…") { model.showCatalog = true }
                            .font(.caption)
                    } else {
                        ForEach(model.installedModels) { installed in
                            ModelRowView(
                                model: installed,
                                isSelected: model.selectedModelId == installed.id,
                                isLoadedInMemory: model.selectedModelId == installed.id
                                    && inferenceService.isModelLoaded
                                    && inferenceService.loadedModelId == installed.id,
                                onUnload: { Task { await model.unloadCurrentModel() } }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedModelId = installed.id
                            }
                            .contextMenu {
                                Button("Diskten Sil", role: .destructive) {
                                    modelToDelete = installed
                                }
                            }
                        }
                    }
                    LabeledContent("Disk", value: model.diskUsageFormatted)
                        .font(.caption)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MacLLM")
        .background(AppTheme.sidebarBackground)
        .onChange(of: model.sessions.count) { _, _ in
            if !sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                performSessionSearch(query: sessionSearchText)
            }
        }
        .onChange(of: model.selectedModelId) { _, newId in
            guard let newId,
                  let installed = model.installedModels.first(where: { $0.id == newId }) else { return }
            if inferenceService.loadedModelId == newId, inferenceService.isModelLoaded {
                Task { await model.refreshContextTokenCount() }
                return
            }
            Task {
                await model.selectModel(installed)
                await model.refreshContextTokenCount()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebarSearch)) { _ in
            sessionSearchFocused = true
        }
    }

    private func sidebarNavRow(
        _ icon: String,
        title: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(title)
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.7))
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func performSessionSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchedSessions = []
            return
        }
        Task {
            let summaries = (try? ChatHistoryStore.shared.searchSessionSummaries(matching: trimmed)) ?? []
            await MainActor.run {
                var results = summaries.map { $0.asEmptySession() }
                if let projectId = appModel.selectedProjectId {
                    results = results.filter { $0.projectId == projectId }
                }
                searchedSessions = results
            }
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
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if isLoadedInMemory {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 2)
    }
}

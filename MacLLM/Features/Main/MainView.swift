import SwiftUI

@MainActor
final class MainUIState: ObservableObject {
    @Published var showDownloadsPopover: Bool = false
    @Published var showAllDownloadsSheet: Bool = false
    @Published var showWorkspaceInspector: Bool = false
}

struct MainView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var inferenceService: InferenceService
    private let downloadService = HuggingFaceDownloadService.shared
    @StateObject private var ui = MainUIState()

    var body: some View {
        let model = appModel

        NavigationSplitView {
            JanSidebarView(showDownloadsPopover: $ui.showDownloadsPopover)
            .navigationSplitViewColumnWidth(min: 220, ideal: AppTheme.sidebarWidth, max: 320)
        } detail: {
            VStack(spacing: 0) {
                AppUpdateBannerView()
                ImportedModelFlashBannerView()
                ChatView(showDownloadsPopover: $ui.showDownloadsPopover)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .inspector(isPresented: $ui.showWorkspaceInspector) {
            WorkspaceSidebarView()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 380)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if model.selectedProjectId != nil {
                    Button {
                        ui.showWorkspaceInspector.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help(ui.showWorkspaceInspector ? "Çalışma alanını gizle" : "Çalışma alanı dosya ağacı")
                }
                if showsToolbarActivity {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(toolbarActivityText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                DownloadToolbarButton(
                    downloadService: downloadService,
                    isPresented: $ui.showDownloadsPopover,
                    showAllDownloadsSheet: $ui.showAllDownloadsSheet
                )
            }
        }
        .sheet(isPresented: $ui.showDownloadsPopover) {
            DownloadManagerPopover(
                downloadService: downloadService,
                showAllDownloadsSheet: $ui.showAllDownloadsSheet
            )
        }
        .sheet(isPresented: $ui.showAllDownloadsSheet) {
            NavigationStack {
                ScrollView {
                    ActiveDownloadsPanel(downloadService: downloadService, style: .full)
                        .padding()
                }
                .navigationTitle("İndirmeler")
                .frame(minWidth: 480, minHeight: 360)
            }
        }
        .sheet(isPresented: Binding(
            get: { model.showCatalog },
            set: { model.showCatalog = $0 }
        )) {
            ModelCatalogView()
        }
        .sheet(isPresented: Binding(
            get: { model.showNewProjectSheet },
            set: { model.showNewProjectSheet = $0 }
        )) {
            NewProjectSheet()
                .environmentObject(appModel)
        }
        .sheet(isPresented: Binding(
            get: { model.showSystemPromptSheet },
            set: { model.showSystemPromptSheet = $0 }
        )) {
            SystemPromptSheet()
                .environmentObject(appModel)
        }
        .sheet(isPresented: Binding(
            get: { model.showProjectPromptSheet },
            set: { model.showProjectPromptSheet = $0 }
        )) {
            if let projectId = model.projectPromptEditId {
                ProjectPromptSheet(projectId: projectId)
                    .environmentObject(appModel)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let status = model.statusMessage, !status.isEmpty {
                AppStatusBar(message: status)
                    .animation(AppTheme.springSoft, value: status)
            }
        }
        .tint(AppTheme.accent)
        .launchLoadAlert(model: appModel)
    }

    private var showsToolbarActivity: Bool {
        appModel.isLoadingModel
            || inferenceService.isGenerating
            || inferenceService.isStoppingGeneration
    }

    private var toolbarActivityText: String {
        if appModel.isLoadingModel {
            if let stage = inferenceService.modelLoadingStage, !stage.isEmpty {
                return stage
            }
            return "Model hazırlanıyor"
        }
        if inferenceService.isStoppingGeneration {
            return "Yanıt durduruluyor"
        }
        if inferenceService.isGenerating {
            return "Yanıt üretiliyor"
        }
        return ""
    }
}

private extension View {
    func launchLoadAlert(model: AppModel) -> some View {
        alert(
            "Model yüklensin mi?",
            isPresented: Binding(
                get: { model.showLaunchLoadPrompt },
                set: { isPresented in
                    if !isPresented, model.showLaunchLoadPrompt {
                        model.confirmLaunchLoad(load: false)
                    }
                }
            )
        ) {
            Button("Yükle") {
                model.confirmLaunchLoad(load: true)
            }
            Button("Hayır, sonra", role: .cancel) {
                model.confirmLaunchLoad(load: false)
            }
        } message: {
            if let candidate = model.launchLoadCandidate {
                Text(model.launchLoadPromptMessage(for: candidate))
            }
        }
    }
}

// MARK: - Jan-style sidebar

@MainActor
final class JanSidebarUIState: ObservableObject {
    @Published var sessionSearchText = ""
    @Published var searchedSessions: [ChatSession] = []
    @Published var modelsExpanded = false
    @Published var sessionPendingDelete: ChatSession?
    @Published var sessionsPendingDeleteAll = false
    @Published var modelPendingDelete: InstalledModel?
    @Published var hoveredSessionId: UUID?
    @Published var selectedSessionId: UUID?
}

struct JanSidebarView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var inferenceService: InferenceService
    @Binding var showDownloadsPopover: Bool
    @StateObject private var ui = JanSidebarUIState()
    @FocusState private var sessionSearchFocused: Bool

    private var sessionsToShow: [ChatSession] {
        ui.sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? appModel.filteredSessions
            : ui.searchedSessions
    }

    private var sessionDeleteAlertPresented: Binding<Bool> {
        Binding(
            get: { ui.sessionPendingDelete != nil },
            set: { isPresented in
                if !isPresented { ui.sessionPendingDelete = nil }
            }
        )
    }

    var body: some View {
        let model = appModel
        sidebarList(model: model)
            .listStyle(.sidebar)
            .navigationTitle("")
            .toolbar { sidebarToolbar }
            .background(AppTheme.sidebarBackground)
            .onChange(of: model.sessions.count) { _, _ in
                if !ui.sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    performSessionSearch(query: ui.sessionSearchText)
                }
                if !model.sessions.contains(where: { $0.id == ui.selectedSessionId }) {
                    ui.selectedSessionId = model.currentSession.id
                }
            }
            .onAppear { ui.selectedSessionId = model.currentSession.id }
            .onChange(of: model.currentSession.id) { _, newId in
                if ui.selectedSessionId != newId { ui.selectedSessionId = newId }
            }
            .onChange(of: ui.selectedSessionId) { _, newId in
                guard let newId, newId != model.currentSession.id else { return }
                guard let session = model.sessions.first(where: { $0.id == newId })
                    ?? ui.searchedSessions.first(where: { $0.id == newId }) else { return }
                Task { await model.loadSession(session) }
            }
            .onChange(of: model.selectedModelId) { _, newId in
                guard !model.suppressAutoModelLoad else { return }
                guard let newId,
                      let installed = model.installedModels.first(where: { $0.id == newId }) else { return }
                if inferenceService.loadedModelId == newId, inferenceService.isModelLoaded {
                    Task { await model.refreshContextTokenCount() }
                    return
                }
                Task {
                    _ = await model.selectModel(installed)
                    await model.refreshContextTokenCount()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSidebarSearch)) { _ in
                sessionSearchFocused = true
            }
            .onDeleteCommand {
                guard let selectedId = ui.selectedSessionId else { return }
                if let session = model.sessions.first(where: { $0.id == selectedId })
                    ?? ui.searchedSessions.first(where: { $0.id == selectedId }) {
                    ui.sessionPendingDelete = session
                }
            }
            .alert("Bu sohbet silinsin mi?", isPresented: sessionDeleteAlertPresented, presenting: ui.sessionPendingDelete) { session in
                Button("Sil", role: .destructive) {
                    Task {
                        await model.deleteSession(session)
                        ui.sessionPendingDelete = nil
                    }
                }
                Button("İptal", role: .cancel) { ui.sessionPendingDelete = nil }
            } message: { session in
                Text("“\(session.title)” kalıcı olarak silinecek.")
            }
            .alert("Listedeki sohbetler silinsin mi?", isPresented: $ui.sessionsPendingDeleteAll) {
                Button("Hepsini sil", role: .destructive) {
                    let targets = sessionsToShow
                    Task { await model.deleteSessions(targets) }
                }
                Button("İptal", role: .cancel) {}
            } message: {
                Text("\(sessionsToShow.count) sohbet kalıcı olarak silinecek. Bu işlem geri alınamaz.")
            }
            .alert("Model diskten silinsin mi?", isPresented: modelDeleteAlertPresented, presenting: ui.modelPendingDelete) { installed in
                Button("Sil", role: .destructive) {
                    Task {
                        await model.deleteModel(installed)
                        ui.modelPendingDelete = nil
                    }
                }
                Button("İptal", role: .cancel) { ui.modelPendingDelete = nil }
            } message: { installed in
                Text("\(installed.name) dosyası silinecek. Bu işlem geri alınamaz.")
            }
    }

    private var modelDeleteAlertPresented: Binding<Bool> {
        Binding(
            get: { ui.modelPendingDelete != nil },
            set: { isPresented in
                if !isPresented { ui.modelPendingDelete = nil }
            }
        )
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 10) {
                BrandMark(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MacLLM")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Yerel AI")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarList(model: AppModel) -> some View {
        List(selection: $ui.selectedSessionId) {
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
                    AppSettingsOpener.open()
                }
            }

            if !model.projects.isEmpty {
                Section("Projeler") {
                    Button {
                        model.selectedProjectId = nil
                        model.syncActiveWorkspace()
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
                        Button {
                            model.selectedProjectId = project.id
                            model.syncActiveWorkspace()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: project.rootDirectoryPath != nil ? "folder.fill.badge.gearshape" : "folder")
                                    .font(.caption)
                                    .foregroundStyle(project.rootDirectoryPath != nil ? AppTheme.accent : AppTheme.secondaryText)
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
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Proje ve çalışma alanı ayarları…") {
                                model.projectPromptEditId = project.id
                                model.showProjectPromptSheet = true
                            }
                            Button("Sil", role: .destructive) {
                                model.deleteProject(project)
                            }
                        }
                    }
                }
            }

            Section {
                TextField("Sohbetlerde ara…", text: $ui.sessionSearchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.searchFieldRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.searchFieldRadius, style: .continuous)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    }
                    .focused($sessionSearchFocused)
                    .onChange(of: ui.sessionSearchText) { _, query in
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
                        sessionRow(session)
                    }
                }
            } header: {
                HStack {
                    Text("Sohbetler")
                    Spacer()
                    Button("Hepsini sil") {
                        ui.sessionsPendingDeleteAll = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(sessionsToShow.isEmpty ? AppTheme.secondaryText.opacity(0.4) : Color.red.opacity(0.85))
                    .disabled(sessionsToShow.isEmpty)
                }
            }

            Section {
                DisclosureGroup("Modeller", isExpanded: $ui.modelsExpanded) {
                    if model.installedModels.isEmpty {
                        Button("Model Hub…") { model.showCatalog = true }
                            .font(.caption)
                    } else {
                        ForEach(model.installedModels) { installed in
                            Button {
                                if model.selectedModelId == installed.id,
                                   inferenceService.loadedModelId == installed.id,
                                   inferenceService.isModelLoaded {
                                    return
                                }
                                model.selectedModelId = installed.id
                            } label: {
                                installedModelRow(installed, model: model)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Diskten Sil", role: .destructive) {
                                    ui.modelPendingDelete = installed
                                }
                            }
                        }
                    }
                    LabeledContent("Disk", value: model.diskUsageFormatted)
                        .font(.caption)
                }
            }
        }
    }

    private func installedModelRow(_ installed: InstalledModel, model: AppModel) -> some View {
        let isSelected = model.selectedModelId == installed.id
        let isLoaded = isSelected
            && inferenceService.isModelLoaded
            && inferenceService.loadedModelId == installed.id
        let modality = isLoaded ? model.activeProfile?.modality.label : nil
        return ModelRowView(
            model: installed,
            isSelected: isSelected,
            isLoadedInMemory: isLoaded,
            modalityLabel: modality,
            onUnload: { Task { await model.unloadCurrentModel() } }
        )
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        let isCurrent = session.id == appModel.currentSession.id
        let isHovered = ui.hoveredSessionId == session.id

        return HStack(spacing: 8) {
            Text(session.title)
                .lineLimit(1)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                ui.sessionPendingDelete = session
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.red : AppTheme.secondaryText.opacity(0.55))
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isCurrent ? 1 : 0.35)
            .appHitTarget(minWidth: 28, minHeight: 28)
            .help("Sohbeti sil")

            if isCurrent {
                Capsule(style: .continuous)
                    .fill(AppTheme.navActiveGradient)
                    .frame(width: 3, height: 18)
                    .shadow(color: AppTheme.glowSecondary.opacity(0.5), radius: 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.navActiveGradient.opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AppTheme.accentSecondary.opacity(0.35), lineWidth: 1)
                    }
            } else if isHovered {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .onHover { hovering in
            ui.hoveredSessionId = hovering ? session.id : nil
        }
        .tag(session.id)
        .contextMenu {
            Menu("Projeye taşı") {
                Button("Proje yok") {
                    Task { await appModel.assignSession(session.id, to: nil) }
                }
                ForEach(appModel.projects) { project in
                    Button(project.name) {
                        Task { await appModel.assignSession(session.id, to: project.id) }
                    }
                }
            }
            Button("Sil", role: .destructive) {
                ui.sessionPendingDelete = session
            }
        }
    }

    private func sidebarNavRow(
        _ icon: String,
        title: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.65))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SidebarNavButtonStyle())
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 8))
    }

    private func performSessionSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            ui.searchedSessions = []
            return
        }
        Task {
            let summaries = (try? ChatHistoryStore.shared.searchSessionSummaries(matching: trimmed)) ?? []
            await MainActor.run {
                var results = summaries.map { $0.asEmptySession() }
                if let projectId = appModel.selectedProjectId {
                    results = results.filter { $0.projectId == projectId }
                }
                ui.searchedSessions = results
            }
        }
    }
}

struct ModelRowView: View {
    let model: InstalledModel
    let isSelected: Bool
    var isLoadedInMemory: Bool = false
    var modalityLabel: String? = nil
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
            if let modalityLabel, isLoadedInMemory {
                Text(modalityLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent.opacity(0.12), in: Capsule())
            }
            if isLoadedInMemory {
                AnimatedStatusDot(color: .green, pulse: true)
            }
        }
        .padding(.vertical, 2)
    }
}

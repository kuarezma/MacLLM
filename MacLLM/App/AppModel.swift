import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var installedModels: [InstalledModel] = []
    var catalogEntries: [CatalogEntry] = []
    var modelRecommendations: [ScoredCatalogEntry] = []
    var systemProfile: MacSystemProfile = .current()
    var selectedModelId: String?
    var currentSession: ChatSession
    var sessions: [ChatSession] = []
    var settings: InferenceSettings = .default
    var statusMessage: String?
    var isLoadingModel = false
    var showCatalog = false
    var showNewProjectSheet = false
    var showSystemPromptSheet = false
    var showProjectPromptSheet = false
    var projectPromptEditId: UUID?
    var projects: [ChatProject] = []
    var selectedProjectId: UUID?
    var contextTokenCount: Int = 0
    var contextTokenCountIsEstimate = true
    var activeProfile: LoadedModelProfile?
    var streamingBuffer = StreamingTextBuffer()
    var suppressAutoModelLoad = false
    var showLaunchLoadPrompt = false
    var launchLoadCandidate: InstalledModel?
    var showImportedFlashBanner = false

    private let modelStore = ModelStore.shared
    private var statusClearTask: Task<Void, Never>?
    private var contextRefreshTask: Task<Void, Never>?
    private let catalogService = ModelCatalogService.shared
    private let recommendationService = ModelRecommendationService.shared
    private let downloadService = HuggingFaceDownloadService.shared
    private let inferenceService = InferenceService.shared
    private let chatStore = ChatHistoryStore.shared
    private let projectStore = ChatProjectStore.shared
    private var modelLoadGeneration: UInt = 0
    private var deletedSessionIDs: Set<UUID> = []
    private var pendingSaveTask: Task<Void, Never>?
    private var contextTokenFingerprint: String = ""

    var selectedModel: InstalledModel? {
        installedModels.first { $0.id == selectedModelId }
    }

    var effectiveContextLength: Int {
        guard let profile = activeProfile else { return Int(settings.contextLength) }
        return min(Int(settings.contextLength), Int(profile.recommendedMaxContext))
    }

    var isModelLoadedInMemory: Bool {
        inferenceService.isModelLoaded
    }

    var canDeleteCurrentSession: Bool {
        !currentSession.messages.isEmpty
            || sessions.contains(where: { $0.id == currentSession.id })
    }

    var diskUsageFormatted: String {
        let used = (try? modelStore.totalDiskUsageBytes()) ?? 0
        return ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
    }

    var filteredSessions: [ChatSession] {
        guard let selectedProjectId else { return sessions }
        return sessions.filter { $0.projectId == selectedProjectId }
    }

    func projectName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return projects.first(where: { $0.id == id })?.name
    }

    init() {
        currentSession = ChatSession()
        Task { await bootstrap() }
    }

    func bootstrap() async {
        do {
            try modelStore.ensureDirectories()
            installedModels = try modelStore.loadInstalledModels()
            repairInstalledModelTemplates()
            repairMmprojLinks()
            systemProfile = MacSystemProfile.current()
            catalogEntries = try catalogService.loadDefaultCatalog()
            modelRecommendations = recommendationService.recommend(
                catalog: catalogEntries,
                profile: systemProfile
            )
            sessions = try chatStore.loadSessionIndex()
            projects = (try? projectStore.load()) ?? []
            if let saved = UserDefaults.standard.data(forKey: "inferenceSettings"),
               let decoded = try? JSONDecoder().decode(InferenceSettings.self, from: saved) {
                settings = decoded
                inferenceService.settings = decoded
            } else {
                settings = InferenceSettings.defaults(for: systemProfile)
                inferenceService.settings = settings
            }
            mergeDefaultStopSequences()
            migrateImportedModelFlashAttentionIfNeeded()
            repairQwopusProfilesIfNeeded()
            await configureLaunchModelSelection()
        } catch {
            reportError(error, context: "Baslatma hatasi")
        }
    }

    func dismissImportedFlashBanner() {
        showImportedFlashBanner = false
        ImportedModelPreferences.flashBannerDismissed = true
    }

    /// Daha önce içe aktarılmış modellerde Flash Attention açık kalmışsa tek seferlik kapatır.
    private func migrateImportedModelFlashAttentionIfNeeded() {
        let hasImported = installedModels.contains { $0.repoId == "imported" }
        guard hasImported else {
            ImportedModelPreferences.flashMigrationCompleted = true
            return
        }
        guard !ImportedModelPreferences.flashMigrationCompleted else { return }

        ImportedModelPreferences.flashMigrationCompleted = true

        guard settings.flashAttention else { return }

        settings.flashAttention = false
        let shouldReload = inferenceService.isModelLoaded
            && installedModels.contains {
                $0.id == inferenceService.loadedModelId && $0.repoId == "imported"
            }
        saveSettings(reloadModel: shouldReload, silent: true)

        if !ImportedModelPreferences.flashBannerDismissed {
            showImportedFlashBanner = true
        }
    }

    private func preferredLaunchModel() -> InstalledModel? {
        installedModels.max { lhs, rhs in
            (lhs.lastUsedAt ?? .distantPast) < (rhs.lastUsedAt ?? .distantPast)
        } ?? installedModels.first
    }

    private func configureLaunchModelSelection() async {
        guard selectedModelId == nil, let preferred = preferredLaunchModel() else { return }

        suppressAutoModelLoad = true
        selectedModelId = preferred.id
        suppressAutoModelLoad = false

        switch LaunchPreferences.loadModelOnLaunch {
        case .always:
            _ = await selectModel(preferred)
        case .never:
            break
        case .ask:
            launchLoadCandidate = preferred
            showLaunchLoadPrompt = true
        }
    }

    func confirmLaunchLoad(load: Bool) {
        showLaunchLoadPrompt = false
        guard let model = launchLoadCandidate else { return }
        launchLoadCandidate = nil
        if load {
            Task { _ = await selectModel(model) }
        } else {
            setStatusMessage("Model ilk mesajda yüklenecek")
        }
    }

    func launchLoadPromptMessage(for model: InstalledModel) -> String {
        let size = ByteCountFormatter.string(fromByteCount: model.fileSizeBytes, countStyle: .memory)
        return "«\(model.name)» belleğe alınsın mı? (yaklaşık \(size) RAM)"
    }

    func refreshModels() {
        do {
            installedModels = try modelStore.loadInstalledModels()
            repairInstalledModelTemplates()
            repairMmprojLinks()
        } catch {
            reportError(error, context: "Model listesi yenilenemedi")
        }
    }

    func visionAttachmentWarning(for attachments: [MessageAttachment]) -> String? {
        activeProfile?.attachmentWarning(for: attachments)
    }

    func chatCompatibilityWarning() -> String? {
        activeProfile?.composerHints.first {
            $0.kind == .warning && $0.icon == "exclamationmark.triangle"
        }?.message
    }

    func composerHint(for attachments: [MessageAttachment]) -> ComposerHint? {
        activeProfile?.primaryComposerHint(pendingAttachments: attachments)
    }

    func deleteSession(_ session: ChatSession) async {
        await stopGenerationAndWait()
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        deletedSessionIDs.insert(session.id)
        invalidateInferenceCache()
        do {
            try chatStore.deleteSession(id: session.id)
            AttachmentStore.shared.deleteSessionAttachments(sessionId: session.id)
            sessions.removeAll { $0.id == session.id }
            if currentSession.id == session.id {
                await newChat(saveCurrent: false)
            } else {
                sessions = try chatStore.loadSessionIndex()
            }
            setStatusMessage("Sohbet silindi")
        } catch {
            reportError(error, context: "Sohbet silinemedi")
        }
    }

    func setStatusMessage(_ message: String?, persistent: Bool = false) {
        statusClearTask?.cancel()
        statusMessage = message
        guard let message, !message.isEmpty, !persistent else { return }
        statusClearTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, statusMessage == message else { return }
            statusMessage = nil
        }
    }

    private func reportError(
        _ error: Error,
        context: String? = nil,
        persistent: Bool = true
    ) {
        let details = UserErrorFormatter.details(for: error)
        let text: String
        if let context, !context.isEmpty {
            text = "\(context): \(details.displayText)"
        } else {
            text = details.displayText
        }
        setStatusMessage(text, persistent: persistent)
    }

    /// Kayıtlı ayarlara şablon stop dizilerini ekler (eski kurulumlar için).
    private func mergeDefaultStopSequences() {
        let merged = ChatTemplateResolver.mergedStopSequences(
            settings: settings,
            template: selectedModel?.chatTemplate ?? "chatml"
        )
        if merged != settings.stopSequences {
            settings.stopSequences = merged
            inferenceService.settings = settings
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "inferenceSettings")
            }
        }
    }

    private func repairInstalledModelTemplates() {
        var changed = false
        for index in installedModels.indices {
            let repaired = ChatTemplateResolver.repairStoredTemplate(
                installedModels[index].chatTemplate,
                repoId: installedModels[index].repoId,
                filename: installedModels[index].filename
            )
            if repaired != installedModels[index].chatTemplate {
                installedModels[index].chatTemplate = repaired
                changed = true
            }
        }
        if changed {
            try? modelStore.saveInstalledModels(installedModels)
        }
    }

    /// Qwopus / Qwen3.5: redacted_im_end stop listesi ve chatml şablonu (v1.14.16).
    private func repairQwopusProfilesIfNeeded() {
        let hasQwopus = installedModels.contains { model in
            let haystack = "\(model.name) \(model.filename) \(model.repoId)".lowercased()
            return haystack.contains("qwopus") || haystack.contains("qwen3.5")
        }
        guard hasQwopus else {
            ImportedModelPreferences.qwopusStopMigrationCompleted = true
            return
        }
        guard !ImportedModelPreferences.qwopusStopMigrationCompleted else { return }

        ImportedModelPreferences.qwopusStopMigrationCompleted = true
        var modelsChanged = false
        for index in installedModels.indices {
            let haystack = "\(installedModels[index].name) \(installedModels[index].filename)".lowercased()
            guard haystack.contains("qwopus") || haystack.contains("qwen3.5") else { continue }
            if installedModels[index].chatTemplate != "chatml" {
                installedModels[index].chatTemplate = "chatml"
                modelsChanged = true
            }
        }
        if modelsChanged {
            try? modelStore.saveInstalledModels(installedModels)
        }
        mergeDefaultStopSequences()
    }

    private func repairMmprojLinks() {
        var changed = false
        for index in installedModels.indices {
            let modelURL = URL(fileURLWithPath: installedModels[index].localPath)
            if let mmproj = MmprojDiscovery.findSibling(to: modelURL) {
                if installedModels[index].mmprojLocalPath != mmproj.path {
                    installedModels[index].mmprojLocalPath = mmproj.path
                    installedModels[index].mmprojFilename = mmproj.lastPathComponent
                    changed = true
                }
            } else if let stalePath = installedModels[index].mmprojLocalPath,
                      !FileManager.default.fileExists(atPath: stalePath) {
                installedModels[index].mmprojLocalPath = nil
                installedModels[index].mmprojFilename = nil
                changed = true
            }
        }
        if changed {
            try? modelStore.saveInstalledModels(installedModels)
        }
    }

    @discardableResult
    func selectModel(_ model: InstalledModel) async -> Bool {
        modelLoadGeneration &+= 1
        let generation = modelLoadGeneration

        isLoadingModel = true
        setStatusMessage("\(model.name) hazırlanıyor…")
        defer { isLoadingModel = false }

        do {
            try Task.checkCancellation()
            inferenceService.settings = settings
            try await inferenceService.loadModel(model)
            guard generation == modelLoadGeneration else { return false }

            selectedModelId = model.id
            currentSession.modelId = model.id
            invalidateInferenceCache()
            if let profile = await inferenceService.buildLoadedProfile(
                for: model,
                systemProfile: systemProfile
            ) {
                applyRuntimeProfile(profile)
            }
            setStatusMessage("\(model.name) kullanıma hazır")
            refreshModels()
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == modelLoadGeneration else { return false }
            reportError(error, context: "Yukleme hatasi")
            return false
        }
    }

    func unloadCurrentModel() async {
        modelLoadGeneration &+= 1
        await stopGenerationAndWait()
        await inferenceService.unloadModel()
        activeProfile = nil
        if let name = selectedModel?.name {
            setStatusMessage("\(name) bellekten çıkarıldı")
        } else {
            setStatusMessage("Model bellekten çıkarıldı")
        }
    }

    func downloadModel(_ entry: CatalogEntry, companionMmproj: CatalogEntry? = nil) async {
        setStatusMessage("\(entry.name) indiriliyor…")
        do {
            let localURL = try await downloadService.download(entry: entry) { info in
                Task { @MainActor in
                    let eta = info.estimatedSecondsRemaining.map {
                        DownloadMetrics.formatETA(seconds: $0)
                    } ?? "—"
                    self.setStatusMessage(String(
                        format: "%.0f%% · %@ · kalan %@",
                        info.progress * 100,
                        entry.name,
                        eta
                    ))
                }
            }
            try GGUFFileValidator.validateDownload(at: localURL, expectedBytes: entry.estimatedSizeBytes)

            var mmprojURL = MmprojDiscovery.findSibling(to: localURL)
            if mmprojURL == nil, let companion = companionMmproj {
                setStatusMessage("Vision projeksiyonu (mmproj) indiriliyor…")
                let mmprojLocal = try await downloadService.download(entry: companion) { info in
                    Task { @MainActor in
                        self.setStatusMessage(String(
                            format: "mmproj %.0f%% · kalan %@",
                            info.progress * 100,
                            info.estimatedSecondsRemaining.map { DownloadMetrics.formatETA(seconds: $0) } ?? "—"
                        ))
                    }
                }
                try GGUFFileValidator.validateDownload(at: mmprojLocal, expectedBytes: companion.estimatedSizeBytes)
                mmprojURL = mmprojLocal
            }

            _ = try modelStore.registerModel(
                id: entry.id,
                name: entry.name,
                repoId: entry.repoId,
                filename: entry.filename,
                localURL: localURL,
                chatTemplate: entry.chatTemplate,
                mmprojURL: mmprojURL
            )
            refreshModels()
            guard let model = installedModels.first(where: { $0.id == entry.id }) else {
                setStatusMessage("\(entry.name) kaydedildi ancak listede bulunamadı.")
                return
            }
            let loaded = await selectModel(model)
            if loaded {
                setStatusMessage("\(entry.name) indirildi ve kullanıma hazır")
            } else {
                setStatusMessage("\(entry.name) indirildi; soldan modeli seçerek yükleyin.")
            }
        } catch is CancellationError {
            setStatusMessage("İndirme iptal edildi")
        } catch let error as NSError where error.domain == "MacLLM" && error.code == 101 {
            setStatusMessage(UserErrorFormatter.details(for: error).displayText)
        } catch {
            reportError(error, context: "Indirme hatasi")
        }
    }

    func deleteModel(_ model: InstalledModel) async {
        modelLoadGeneration &+= 1
        if selectedModelId == model.id {
            await stopGenerationAndWait()
            await inferenceService.unloadModel()
            selectedModelId = nil
        }
        do {
            try modelStore.deleteModel(id: model.id)
            if currentSession.modelId == model.id {
                currentSession.modelId = nil
            }
            for index in sessions.indices where sessions[index].modelId == model.id {
                sessions[index].modelId = nil
            }
            if let summaries = try? chatStore.loadSessionIndex() {
                for summary in summaries where summary.modelId == model.id {
                    guard var full = try? chatStore.loadSession(id: summary.id) else { continue }
                    full.modelId = nil
                    try? chatStore.saveSession(full)
                }
                sessions = try chatStore.loadSessionIndex()
            }
            refreshModels()
            setStatusMessage("\(model.name) silindi")
        } catch {
            reportError(error, context: "Model silinemedi")
        }
    }

    func ggufImportDestinationExists(for url: URL) -> Bool {
        let filename = url.lastPathComponent
        let dest = modelStore.destinationURL(repoId: "imported", filename: filename)
        return FileManager.default.fileExists(atPath: dest.path)
    }

    func importGGUF(from url: URL, replaceExisting: Bool = false) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        setStatusMessage("Model dosyası kopyalanıyor…")
        do {
            let filename = url.lastPathComponent
            let id = filename.replacingOccurrences(of: ".gguf", with: "")
            let dest = modelStore.destinationURL(repoId: "imported", filename: filename)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                guard replaceExisting else {
                    setStatusMessage("«\(filename)» zaten yüklü. Üzerine yazmak için onaylayın.", persistent: true)
                    return
                }
                try FileManager.default.removeItem(at: dest)
            }
            try await Task.detached(priority: .utility) {
                try FileManager.default.copyItem(at: url, to: dest)
            }.value
            try GGUFFileValidator.validateDownload(at: dest, expectedBytes: 0)
            let mmproj = MmprojDiscovery.findSibling(to: dest)
            _ = try modelStore.registerModel(
                id: id,
                name: filename,
                repoId: "imported",
                filename: filename,
                localURL: dest,
                chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: filename, filename: filename),
                mmprojURL: mmproj
            )
            refreshModels()
            if settings.flashAttention {
                settings.flashAttention = false
                inferenceService.settings = settings
                if let data = try? JSONEncoder().encode(settings) {
                    UserDefaults.standard.set(data, forKey: "inferenceSettings")
                }
            }
            if let model = installedModels.first(where: { $0.id == id }) {
                let loaded = await selectModel(model)
                setStatusMessage(loaded ? "Model içe aktarıldı ve hazır" : "Model içe aktarıldı; soldan seçin")
            } else {
                setStatusMessage("Model içe aktarıldı")
            }
        } catch {
            reportError(error, context: "Ice aktarma hatasi")
        }
    }

    func newChat(saveCurrent: Bool = true) async {
        await stopGenerationAndWait()
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        if saveCurrent, !currentSession.messages.isEmpty {
            try? await saveCurrentSession()
        }
        invalidateInferenceCache()
        streamingBuffer.reset()
        currentSession = ChatSession(modelId: selectedModelId, projectId: selectedProjectId)
        setStatusMessage(nil)
    }

    func effectiveSystemPrompt() -> String {
        var parts: [String] = []
        let projectId = currentSession.projectId ?? selectedProjectId
        if let projectId,
           let project = projects.first(where: { $0.id == projectId }) {
            let projectPrompt = project.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !projectPrompt.isEmpty {
                parts.append(projectPrompt)
            }
        }
        let global = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !global.isEmpty {
            parts.append(global)
        }
        return parts.joined(separator: "\n\n")
    }

    func createProject(named name: String, systemPrompt: String = "") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let project = ChatProject(name: trimmed, systemPrompt: systemPrompt)
        do {
            try projectStore.save(project)
            projects.insert(project, at: 0)
            selectedProjectId = project.id
            currentSession.projectId = project.id
            setStatusMessage("Proje oluşturuldu: \(trimmed)")
        } catch {
            reportError(error, context: "Proje olusturulamadi")
        }
    }

    func updateProjectSystemPrompt(projectId: UUID, prompt: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        var project = projects[index]
        project.systemPrompt = prompt
        project.updatedAt = .now
        do {
            try projectStore.save(project)
            projects[index] = project
            setStatusMessage("Proje istemi güncellendi")
        } catch {
            reportError(error, context: "Proje istemi guncellenemedi")
        }
    }

    func importChat(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            guard let session = ChatImporter.session(fromMarkdown: content) else {
                setStatusMessage("Sohbet dosyası okunamadı veya mesaj bulunamadı.", persistent: true)
                return
            }
            var imported = session
            imported.modelId = selectedModelId
            imported.projectId = selectedProjectId
            try chatStore.saveSession(imported)
            let summary = try chatStore.upsertSummary(for: imported)
            sessions.insert(summary.asEmptySession(), at: 0)
            await loadSession(imported)
            setStatusMessage("Sohbet içe aktarıldı")
        } catch {
            reportError(error, context: "Sohbet ice aktarilamadi")
        }
    }

    func deleteProject(_ project: ChatProject) {
        do {
            try projectStore.delete(id: project.id)
            projects.removeAll { $0.id == project.id }
            if selectedProjectId == project.id {
                selectedProjectId = nil
            }
            for session in sessions where session.projectId == project.id {
                if var full = try? chatStore.loadSession(id: session.id) {
                    full.projectId = nil
                    try? chatStore.saveSession(full)
                }
            }
            for index in sessions.indices where sessions[index].projectId == project.id {
                sessions[index].projectId = nil
            }
            if currentSession.projectId == project.id {
                currentSession.projectId = nil
            }
            setStatusMessage("Proje silindi")
        } catch {
            reportError(error, context: "Proje silinemedi")
        }
    }

    func assignSession(_ sessionId: UUID, to projectId: UUID?) async {
        guard var session = try? chatStore.loadSession(id: sessionId) else { return }
        session.projectId = projectId
        try? chatStore.saveSession(session)
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].projectId = projectId
        }
        if currentSession.id == sessionId {
            currentSession.projectId = projectId
        }
        if let projectId, var project = projects.first(where: { $0.id == projectId }) {
            project.updatedAt = .now
            try? projectStore.save(project)
            if let pIndex = projects.firstIndex(where: { $0.id == projectId }) {
                projects[pIndex] = project
            }
        }
    }

    func exportCurrentSessionMarkdown() -> String {
        ChatExporter.markdown(for: currentSession, modelName: selectedModel?.name)
    }

    func saveCurrentSession() async throws {
        guard !deletedSessionIDs.contains(currentSession.id) else { return }
        guard !currentSession.messages.isEmpty else { return }
        if currentSession.title == "Yeni sohbet",
           let firstUser = currentSession.messages.first(where: { $0.role == .user }) {
            currentSession.title = String(firstUser.content.prefix(48))
        }
        currentSession.updatedAt = .now
        let snapshot = currentSession
        try await Task.detached(priority: .utility) {
            try ChatHistoryStore.shared.writeSessionFile(snapshot)
            _ = try ChatHistoryStore.shared.upsertSummary(for: snapshot)
        }.value
        patchLocalSessionSummary(snapshot)
    }

    private func patchLocalSessionSummary(_ session: ChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].title = session.title
            sessions[index].updatedAt = session.updatedAt
            sessions[index].modelId = session.modelId
            sessions[index].projectId = session.projectId
        } else {
            sessions.insert(
                ChatSession(
                    id: session.id,
                    title: session.title,
                    modelId: session.modelId,
                    projectId: session.projectId,
                    messages: [],
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt
                ),
                at: 0
            )
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }

    private func scheduleSaveCurrentSession() {
        pendingSaveTask?.cancel()
        let sessionId = currentSession.id
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard let self, !Task.isCancelled else { return }
            guard !deletedSessionIDs.contains(sessionId) else { return }
            guard currentSession.id == sessionId else { return }
            try? await saveCurrentSession()
        }
    }

    private func invalidateInferenceCache() {
        inferenceService.invalidatePromptCache()
        contextTokenFingerprint = ""
        Task { await inferenceService.clearKVCache() }
    }

    func loadSession(_ session: ChatSession) async {
        await stopGenerationAndWait()
        if !currentSession.messages.isEmpty, currentSession.id != session.id {
            try? await saveCurrentSession()
        }
        if let stored = try? chatStore.loadSession(id: session.id) {
            currentSession = stored
        } else {
            currentSession = session
        }
        if let modelId = currentSession.modelId,
           let model = installedModels.first(where: { $0.id == modelId }) {
            await applySessionModelSelection(model)
        }
    }

    /// Eski sohbet açılırken `LaunchPreferences` ile uyumlu model seçimi / yükleme.
    private func applySessionModelSelection(_ model: InstalledModel) async {
        selectedModelId = model.id

        switch LaunchPreferences.loadModelOnLaunch {
        case .never:
            if inferenceService.loadedModelId != model.id {
                setStatusMessage("Model ilk mesajda yüklenecek")
            }
        case .ask:
            if inferenceService.loadedModelId == model.id, inferenceService.isModelLoaded {
                return
            }
            launchLoadCandidate = model
            showLaunchLoadPrompt = true
        case .always:
            if inferenceService.loadedModelId != model.id || !inferenceService.isModelLoaded {
                _ = await selectModel(model)
            }
        }
    }

    func sendMessage(
        _ text: String,
        pendingAttachments: [MessageAttachment] = [],
        appendUserMessage: Bool = true,
        forceFullPrefill: Bool = false
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if appendUserMessage {
            guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }
        }
        guard !inferenceService.isGenerating, !inferenceService.isStoppingGeneration else {
            let message = inferenceService.isStoppingGeneration
                ? "Önce durdurma işlemi tamamlansın."
                : "Önce mevcut yanıtın bitmesini bekleyin veya «Yanıtı Durdur» kullanın."
            setStatusMessage(message)
            return
        }
        guard let model = selectedModel else {
            setStatusMessage("Önce bir model seçin veya indirin", persistent: true)
            return
        }
        guard inferenceService.isModelLoaded, inferenceService.loadedModelId == model.id else {
            setStatusMessage(isLoadingModel ? "Model yükleniyor…" : "Model henüz hazır değil — soldan seçin")
            if !isLoadingModel {
                Task { _ = await selectModel(model) }
            }
            return
        }

        var webContext: String?
        if WebSearchPreferences.isEnabled, !trimmed.isEmpty {
            do {
                webContext = try await WebSearchService.fetchContext(for: trimmed)
            } catch {
                reportError(error, context: "Web aramasi")
                return
            }
        }

        let caps = ModelCapabilities.detect(model: model)
        let profile = activeProfile
        var attachments = pendingAttachments

        for index in attachments.indices {
            do {
                try await MediaContentProcessor.enrich(&attachments[index], sessionId: currentSession.id)
            } catch {
                reportError(error, context: "Ek dosya islenemedi")
                return
            }
        }

        if let videoIndex = attachments.firstIndex(where: { $0.kind == .video }) {
            let video = attachments[videoIndex]
            do {
                let frames = try await MediaContentProcessor.videoFrameAttachments(
                    source: video,
                    sessionId: currentSession.id
                )
                attachments.remove(at: videoIndex)
                attachments.append(contentsOf: frames)
            } catch {
                reportError(error, context: "Video kareleri alinamadi")
                return
            }
        }

        for index in attachments.indices.reversed() {
            let attachment = attachments[index]
            guard attachment.kind == .document,
                  attachment.fileName.lowercased().hasSuffix(".pdf"),
                  attachment.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            else { continue }
            do {
                let pages = try await MediaContentProcessor.pdfPageAttachments(
                    source: attachment,
                    sessionId: currentSession.id
                )
                attachments.remove(at: index)
                attachments.append(contentsOf: pages)
            } catch {
                reportError(error, context: "PDF sayfalari islenemedi")
                return
            }
        }

        let pdfPageImages = attachments.filter { Self.isPdfDerivedPage($0) }
        if !pdfPageImages.isEmpty {
            let supportsVision = profile?.supportsVision ?? caps.supportsVision
            let hasMmproj = profile?.hasMmproj ?? (model.mmprojLocalPath != nil)
            let runtimeReady = profile?.runtimeMultimodal ?? false
            if !supportsVision {
                setStatusMessage(
                    "Bu PDF taranmış veya şekilli içerik barındırıyor. Görmek için vision model gerekir (Hub → Qwen-VL, LLaVA vb.).",
                    persistent: true
                )
                return
            }
            if !hasMmproj || !runtimeReady {
                setStatusMessage(
                    profile?.attachmentWarning(for: pdfPageImages)
                        ?? "Vision model için mmproj GGUF gerekli. PDF ile aynı klasöre *mmproj*.gguf ekleyip modeli yeniden yükleyin.",
                    persistent: true
                )
                return
            }
        }

        let mediaAttachments = attachments.filter { $0.kind == .image || $0.kind == .audio || $0.kind == .video }
        if !mediaAttachments.isEmpty {
            if let warning = profile?.attachmentWarning(for: attachments) {
                setStatusMessage(warning, persistent: true)
                return
            }
            if let profile {
                for attachment in mediaAttachments where !profile.allowsAttachment(attachment.kind) {
                    setStatusMessage(
                        profile.attachmentWarning(for: [attachment])
                            ?? "Bu model bu ek türünü desteklemiyor.",
                        persistent: true
                    )
                    return
                }
            } else if !caps.supportsVision, mediaAttachments.contains(where: { $0.kind == .image || $0.kind == .video }) {
                setStatusMessage(
                    ModelCapabilities.attachmentWarning(model: model, attachments: attachments)
                        ?? "Görüntü için vision modeli gerekir.",
                    persistent: true
                )
                return
            }
        }

        if appendUserMessage {
            let displayText = trimmed.isEmpty ? attachments.map(\.fileName).joined(separator: ", ") : trimmed
            currentSession.messages.append(
                ChatMessage(role: .user, content: displayText, attachments: attachments)
            )
        }
        let assistantIndex = currentSession.messages.count
        let assistantMessageId = UUID()
        currentSession.messages.append(
            ChatMessage(id: assistantMessageId, role: .assistant, content: "")
        )
        let activeSessionId = currentSession.id

        let template = activeProfile?.resolvedChatTemplate ?? model.chatTemplate
        var messagesForInference = Self.trimMessagesForContext(
            currentSession.messages.dropLast().map { $0 },
            maxContextTokens: effectiveContextLength
        )
        if let webContext,
           let userIndex = messagesForInference.lastIndex(where: { $0.role == .user }) {
            var userMessage = messagesForInference[userIndex]
            userMessage.content += "\n\n" + webContext
            messagesForInference[userIndex] = userMessage
        }
        let systemPrompt = effectiveSystemPrompt()
        streamingBuffer.begin(sessionId: activeSessionId, messageId: assistantMessageId)
        let stream = inferenceService.streamResponse(
            messages: messagesForInference,
            chatTemplate: template,
            sessionId: currentSession.id,
            stopSequences: activeProfile?.recommendedStopSequences,
            forceFullPrefill: forceFullPrefill,
            systemPromptOverride: systemPrompt
        )

        do {
            for try await chunk in stream {
                guard currentSession.id == activeSessionId,
                      assistantIndex < currentSession.messages.count,
                      currentSession.messages[assistantIndex].id == assistantMessageId else {
                    break
                }
                streamingBuffer.append(chunk)
            }
            if currentSession.id == activeSessionId,
               assistantIndex < currentSession.messages.count,
               currentSession.messages[assistantIndex].id == assistantMessageId {
                let finalText = ControlTokenSanitizer.sanitizeForDisplay(streamingBuffer.finish())
                currentSession.messages[assistantIndex].content = finalText
                streamingBuffer.reset()
                contextTokenFingerprint = ""
                scheduleSaveCurrentSession()
                GenerationNotificationService.notifyGenerationComplete(sessionTitle: currentSession.title)
            }
        } catch is CancellationError {
            streamingBuffer.reset()
            if currentSession.id == activeSessionId,
               assistantIndex < currentSession.messages.count,
               currentSession.messages[assistantIndex].content.isEmpty {
                currentSession.messages.remove(at: assistantIndex)
            }
            setStatusMessage("Üretim durduruldu")
            try? await saveCurrentSession()
        } catch let llamaError as LlamaError {
            guard currentSession.id == activeSessionId,
                  assistantIndex < currentSession.messages.count else { return }
            if currentSession.messages[assistantIndex].content.isEmpty {
                currentSession.messages[assistantIndex].content =
                    "Hata: \(UserErrorFormatter.message(for: llamaError))"
            }
            switch llamaError {
            case .generationStalled:
                setStatusMessage("Üretim zaman aşımına uğradı. Yeniden deneyin.", persistent: true)
            case .generationEmpty:
                setStatusMessage("Model anlamlı yanıt üretemedi. Yeniden deneyin.", persistent: true)
            default:
                reportError(llamaError, context: "Uretim hatasi")
            }
            await inferenceService.clearKVCache()
            try? await saveCurrentSession()
        } catch {
            guard currentSession.id == activeSessionId,
                  assistantIndex < currentSession.messages.count else { return }
            if currentSession.messages[assistantIndex].content.isEmpty {
                currentSession.messages[assistantIndex].content =
                    "Hata: \(UserErrorFormatter.message(for: error))"
            }
            reportError(error, context: "Uretim hatasi")
            await inferenceService.clearKVCache()
            try? await saveCurrentSession()
        }
    }

    func stopGeneration() {
        Task { await stopGenerationAndWait() }
    }

    func stopGenerationAndWait() async {
        if inferenceService.isGenerating || inferenceService.isStoppingGeneration {
            setStatusMessage("Üretim durduruluyor…")
        }
        await inferenceService.stopGeneration()
    }

    func estimatedContextTokens() -> Int {
        currentSession.messages.reduce(0) { partial, message in
            let attachmentCost = message.attachments.reduce(0) { sum, attachment in
                sum + (attachment.extractedText?.count ?? 0) / 4 + 64
            }
            return partial + max(1, message.content.count / 3 + attachmentCost)
        }
    }

    func scheduleContextTokenRefresh() {
        guard !inferenceService.isGenerating else { return }
        contextRefreshTask?.cancel()
        contextRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            await refreshContextTokenCount()
        }
    }

    private func contextMessagesFingerprint() -> String {
        InferenceService.messageFingerprint(messages: currentSession.messages)
    }

    func refreshContextTokenCount() async {
        guard !inferenceService.isGenerating else {
            contextTokenCount = estimatedContextTokens()
            contextTokenCountIsEstimate = true
            return
        }
        let fingerprint = contextMessagesFingerprint()
        if fingerprint == contextTokenFingerprint, !contextTokenCountIsEstimate {
            return
        }
        guard let model = selectedModel, inferenceService.isModelLoaded else {
            contextTokenCount = estimatedContextTokens()
            contextTokenCountIsEstimate = true
            return
        }
        let trimmed = Self.trimMessagesForContext(
            currentSession.messages,
            maxContextTokens: effectiveContextLength
        )
        do {
            contextTokenCount = try await inferenceService.countPromptTokens(
                messages: trimmed,
                chatTemplate: activeProfile?.resolvedChatTemplate ?? model.chatTemplate,
                sessionId: currentSession.id,
                systemPromptOverride: effectiveSystemPrompt()
            )
            contextTokenCountIsEstimate = false
            contextTokenFingerprint = fingerprint
        } catch {
            contextTokenCount = estimatedContextTokens()
            contextTokenCountIsEstimate = true
        }
    }

    func editUserMessage(id: UUID, newText: String) async {
        await stopGenerationAndWait()
        invalidateInferenceCache()
        guard let index = currentSession.messages.firstIndex(where: { $0.id == id }),
              currentSession.messages[index].role == .user else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let attachments = currentSession.messages[index].attachments
        currentSession.messages[index].content = trimmed
        if index + 1 < currentSession.messages.count {
            currentSession.messages.removeSubrange((index + 1)...)
        }
        await sendMessage(trimmed, pendingAttachments: attachments, appendUserMessage: false, forceFullPrefill: true)
    }

    func deleteMessage(id: UUID) async {
        await stopGenerationAndWait()
        invalidateInferenceCache()
        guard let index = currentSession.messages.firstIndex(where: { $0.id == id }) else { return }
        currentSession.messages.remove(at: index)
        try? await saveCurrentSession()
    }

    func regenerate(from messageId: UUID) async {
        await stopGenerationAndWait()
        invalidateInferenceCache()
        guard let index = currentSession.messages.firstIndex(where: { $0.id == messageId }) else { return }
        let message = currentSession.messages[index]
        guard message.role == .assistant else { return }

        currentSession.messages.removeSubrange(index...)
        guard let userMessage = currentSession.messages.last(where: { $0.role == .user }) else { return }
        await sendMessage(
            userMessage.content,
            pendingAttachments: userMessage.attachments,
            appendUserMessage: false,
            forceFullPrefill: true
        )
    }

    private static func isPdfDerivedPage(_ attachment: MessageAttachment) -> Bool {
        attachment.kind == .image
            && (attachment.extractedText?.contains("[PDF sayfası") ?? false)
    }

    private static func trimMessagesForContext(_ messages: [ChatMessage], maxContextTokens: Int) -> [ChatMessage] {
        let budget = max(512, Int(Double(maxContextTokens) * 0.78))
        var estimated = 0
        var kept: [ChatMessage] = []
        for message in messages.reversed() {
            let attachmentCost = message.attachments.reduce(0) { partial, attachment in
                partial + (attachment.extractedText?.count ?? 0) / 4 + 64
            }
            let cost = max(1, message.content.count / 3 + attachmentCost)
            if estimated + cost > budget, !kept.isEmpty { break }
            estimated += cost
            kept.insert(message, at: 0)
        }
        if kept.isEmpty, let last = messages.last {
            return [last]
        }
        if let system = messages.first(where: { $0.role == .system }),
           !kept.contains(where: { $0.id == system.id }) {
            kept.insert(system, at: 0)
        }
        return kept
    }

    func saveSettings(reloadModel: Bool = false, silent: Bool = false) {
        inferenceService.settings = settings
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "inferenceSettings")
        }
        mergeDefaultStopSequences()
        if reloadModel, let model = selectedModel {
            invalidateInferenceCache()
            if !silent { setStatusMessage("Ayarlar kaydedildi") }
            Task { await selectModel(model) }
            return
        }
        Task {
            await inferenceService.applyRuntimeSettingsIfLoaded()
            if inferenceService.isModelLoaded, let model = selectedModel,
               let profile = await inferenceService.buildLoadedProfile(
                   for: model,
                   systemProfile: systemProfile
               ) {
                applyRuntimeProfile(profile)
            }
        }
        if !silent { setStatusMessage("Ayarlar kaydedildi") }
    }

    private func applyRuntimeProfile(_ profile: LoadedModelProfile) {
        activeProfile = profile
        guard let index = installedModels.firstIndex(where: { $0.id == profile.modelId }) else { return }
        if installedModels[index].chatTemplate != profile.resolvedChatTemplate {
            installedModels[index].chatTemplate = profile.resolvedChatTemplate
            try? modelStore.saveInstalledModels(installedModels)
        }
    }

    func saveSettingsIfNeeded(comparedTo baseline: InferenceSettings) {
        saveSettings(reloadModel: settings.needsModelReload(comparedTo: baseline))
    }
}

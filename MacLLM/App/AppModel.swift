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

    private let modelStore = ModelStore.shared
    private var statusClearTask: Task<Void, Never>?
    private let catalogService = ModelCatalogService.shared
    private let recommendationService = ModelRecommendationService.shared
    private let downloadService = HuggingFaceDownloadService.shared
    private let inferenceService = InferenceService.shared
    private let chatStore = ChatHistoryStore.shared
    private var modelLoadGeneration: UInt = 0

    var selectedModel: InstalledModel? {
        installedModels.first { $0.id == selectedModelId }
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

    init() {
        currentSession = ChatSession()
        Task { await bootstrap() }
    }

    func bootstrap() async {
        do {
            try modelStore.ensureDirectories()
            installedModels = try modelStore.loadInstalledModels()
            repairInstalledModelTemplates()
            systemProfile = MacSystemProfile.current()
            catalogEntries = try catalogService.loadDefaultCatalog()
            modelRecommendations = recommendationService.recommend(
                catalog: catalogEntries,
                profile: systemProfile
            )
            sessions = try chatStore.loadSessionIndex()
            if let saved = UserDefaults.standard.data(forKey: "inferenceSettings"),
               let decoded = try? JSONDecoder().decode(InferenceSettings.self, from: saved) {
                settings = decoded
                inferenceService.settings = decoded
            } else {
                settings = InferenceSettings.defaults(for: systemProfile)
                inferenceService.settings = settings
            }
            mergeDefaultStopSequences()
            if selectedModelId == nil, let first = installedModels.first {
                await selectModel(first)
            }
        } catch {
            setStatusMessage(error.localizedDescription)
        }
    }

    func refreshModels() {
        do {
            installedModels = try modelStore.loadInstalledModels()
            repairInstalledModelTemplates()
        } catch {
            setStatusMessage(error.localizedDescription)
        }
    }

    func deleteSession(_ session: ChatSession) async {
        await stopGenerationAndWait()
        do {
            try chatStore.deleteSession(id: session.id)
            AttachmentStore.shared.deleteSessionAttachments(sessionId: session.id)
            sessions.removeAll { $0.id == session.id }
            if currentSession.id == session.id {
                await newChat()
            }
            setStatusMessage("Sohbet silindi")
        } catch {
            setStatusMessage(UserErrorFormatter.message(for: error), persistent: true)
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

    @discardableResult
    func selectModel(_ model: InstalledModel) async -> Bool {
        modelLoadGeneration &+= 1
        let generation = modelLoadGeneration

        isLoadingModel = true
        setStatusMessage("\(model.name) yükleniyor…")
        defer { isLoadingModel = false }

        do {
            try Task.checkCancellation()
            inferenceService.settings = settings
            try await inferenceService.loadModel(model)
            guard generation == modelLoadGeneration else { return false }

            selectedModelId = model.id
            currentSession.modelId = model.id
            setStatusMessage("\(model.name) hazır")
            refreshModels()
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == modelLoadGeneration else { return false }
            setStatusMessage("Yükleme hatası: \(UserErrorFormatter.message(for: error))", persistent: true)
            return false
        }
    }

    func unloadCurrentModel() async {
        modelLoadGeneration &+= 1
        await stopGenerationAndWait()
        await inferenceService.unloadModel()
        if let name = selectedModel?.name {
            setStatusMessage("\(name) bellekten çıkarıldı")
        } else {
            setStatusMessage("Model bellekten çıkarıldı")
        }
    }

    func downloadModel(_ entry: CatalogEntry) async {
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
            _ = try modelStore.registerModel(
                id: entry.id,
                name: entry.name,
                repoId: entry.repoId,
                filename: entry.filename,
                localURL: localURL,
                chatTemplate: entry.chatTemplate
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
        } catch {
            setStatusMessage("İndirme hatası: \(error.localizedDescription)")
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
            setStatusMessage(UserErrorFormatter.message(for: error), persistent: true)
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

        setStatusMessage("Model kopyalanıyor…")
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
            try FileManager.default.copyItem(at: url, to: dest)
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
            if let model = installedModels.first(where: { $0.id == id }) {
                let loaded = await selectModel(model)
                setStatusMessage(loaded ? "Model içe aktarıldı ve hazır" : "Model içe aktarıldı; soldan seçin")
            } else {
                setStatusMessage("Model içe aktarıldı")
            }
        } catch {
            setStatusMessage("İçe aktarma hatası: \(error.localizedDescription)")
        }
    }

    func newChat() async {
        await stopGenerationAndWait()
        if !currentSession.messages.isEmpty {
            try? await saveCurrentSession()
        }
        currentSession = ChatSession(modelId: selectedModelId)
        setStatusMessage(nil)
    }

    func saveCurrentSession() async throws {
        guard !currentSession.messages.isEmpty else { return }
        if currentSession.title == "Yeni sohbet",
           let firstUser = currentSession.messages.first(where: { $0.role == .user }) {
            currentSession.title = String(firstUser.content.prefix(48))
        }
        currentSession.updatedAt = .now
        try chatStore.saveSession(currentSession)
        sessions = try chatStore.loadSessionIndex()
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
            selectedModelId = modelId
            if inferenceService.loadedModelId != modelId || !inferenceService.isModelLoaded {
                _ = await selectModel(model)
            }
        }
    }

    func sendMessage(_ text: String, pendingAttachments: [MessageAttachment] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }
        guard !inferenceService.isGenerating else {
            setStatusMessage("Önce mevcut yanıtın bitmesini bekleyin veya «Yanıtı Durdur» kullanın.")
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

        let caps = ModelCapabilities.detect(model: model)
        var attachments = pendingAttachments
        var content = trimmed

        for index in attachments.indices {
            do {
                try MediaContentProcessor.enrich(&attachments[index], sessionId: currentSession.id)
            } catch {
                setStatusMessage(error.localizedDescription)
                return
            }
        }

        if let videoIndex = attachments.firstIndex(where: { $0.kind == .video }) {
            let video = attachments[videoIndex]
            do {
                let frames = try MediaContentProcessor.videoFrameAttachments(
                    source: video,
                    sessionId: currentSession.id
                )
                attachments.remove(at: videoIndex)
                attachments.append(contentsOf: frames)
            } catch {
                setStatusMessage(error.localizedDescription)
                return
            }
        }

        for attachment in attachments where attachment.kind == .document {
            if let docText = attachment.extractedText {
                content += MediaContentProcessor.documentTextBlock(
                    fileName: attachment.fileName,
                    text: docText
                )
            }
        }

        let mediaAttachments = attachments.filter { $0.kind == .image || $0.kind == .audio }
        if !mediaAttachments.isEmpty {
            let hasImage = mediaAttachments.contains { $0.kind == .image }
            let hasAudio = mediaAttachments.contains { $0.kind == .audio }

            if hasImage, !caps.supportsVision {
                setStatusMessage(
                    "Görüntü için vision modeli gerekir. Yalnızca metin/belge gönderebilirsiniz.",
                    persistent: true
                )
                if trimmed.isEmpty { return }
                attachments.removeAll { $0.kind == .image }
            }
            if hasAudio, !caps.supportsAudio {
                setStatusMessage("Ses için ses destekli vision modeli gerekir.", persistent: true)
                if trimmed.isEmpty, !attachments.contains(where: { $0.kind == .document }) { return }
                attachments.removeAll { $0.kind == .audio }
            }
            if caps.requiresMmproj, model.mmprojLocalPath == nil,
               attachments.contains(where: { $0.kind == .image || $0.kind == .audio }) {
                setStatusMessage(
                    "Çok modlu model için aynı klasöre mmproj GGUF ekleyip modeli yeniden yükleyin.",
                    persistent: true
                )
                if trimmed.isEmpty { return }
            }
        }

        let displayText = trimmed.isEmpty ? attachments.map(\.fileName).joined(separator: ", ") : trimmed
        currentSession.messages.append(
            ChatMessage(role: .user, content: displayText, attachments: attachments)
        )
        let assistantIndex = currentSession.messages.count
        let assistantMessageId = UUID()
        currentSession.messages.append(
            ChatMessage(id: assistantMessageId, role: .assistant, content: "")
        )
        let activeSessionId = currentSession.id

        let template = model.chatTemplate
        let messagesForInference = Self.trimMessagesForContext(
            currentSession.messages.dropLast().map { $0 },
            maxContextTokens: Int(settings.contextLength)
        )
        let stream = inferenceService.streamResponse(
            messages: messagesForInference,
            chatTemplate: template,
            sessionId: currentSession.id
        )

        do {
            var pending = ""
            var lastFlush = Date()
            for try await chunk in stream {
                guard currentSession.id == activeSessionId,
                      assistantIndex < currentSession.messages.count,
                      currentSession.messages[assistantIndex].id == assistantMessageId else {
                    break
                }
                pending += chunk
                let now = Date()
                if now.timeIntervalSince(lastFlush) >= 0.06 {
                    let combined = currentSession.messages[assistantIndex].content + pending
                    currentSession.messages[assistantIndex].content =
                        ControlTokenSanitizer.sanitizeForDisplay(combined)
                    pending = ""
                    lastFlush = now
                }
            }
            if currentSession.id == activeSessionId,
               assistantIndex < currentSession.messages.count,
               currentSession.messages[assistantIndex].id == assistantMessageId {
                if !pending.isEmpty {
                    let combined = currentSession.messages[assistantIndex].content + pending
                    currentSession.messages[assistantIndex].content =
                        ControlTokenSanitizer.sanitizeForDisplay(combined)
                }
                currentSession.messages[assistantIndex].content = ControlTokenSanitizer.sanitizeForDisplay(
                    currentSession.messages[assistantIndex].content
                )
                try await saveCurrentSession()
            }
        } catch is CancellationError {
            if currentSession.id == activeSessionId,
               assistantIndex < currentSession.messages.count,
               currentSession.messages[assistantIndex].content.isEmpty {
                currentSession.messages.remove(at: assistantIndex)
            }
            setStatusMessage("Üretim durduruldu")
            try? await saveCurrentSession()
        } catch {
            guard currentSession.id == activeSessionId,
                  assistantIndex < currentSession.messages.count else { return }
            if currentSession.messages[assistantIndex].content.isEmpty {
                currentSession.messages[assistantIndex].content =
                    "Hata: \(UserErrorFormatter.message(for: error))"
            }
            setStatusMessage(UserErrorFormatter.message(for: error), persistent: true)
            try? await saveCurrentSession()
        }
    }

    func stopGeneration() {
        Task { await stopGenerationAndWait() }
    }

    func stopGenerationAndWait() async {
        await inferenceService.stopGeneration()
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

    func saveSettings(reloadModel: Bool = false) {
        inferenceService.settings = settings
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "inferenceSettings")
        }
        mergeDefaultStopSequences()
        setStatusMessage("Ayarlar kaydedildi")
        if reloadModel, let model = selectedModel {
            Task { await selectModel(model) }
        }
    }

    func saveSettingsIfNeeded(comparedTo baseline: InferenceSettings) {
        let needsReload =
            baseline.contextLength != settings.contextLength
            || baseline.gpuLayers != settings.gpuLayers
            || baseline.threadCount != settings.threadCount
        saveSettings(reloadModel: needsReload)
    }
}

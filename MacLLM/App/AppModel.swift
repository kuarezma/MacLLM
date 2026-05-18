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

    func deleteSession(_ session: ChatSession) {
        do {
            try chatStore.deleteSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
            if currentSession.id == session.id {
                newChat()
            }
            setStatusMessage("Sohbet silindi")
        } catch {
            setStatusMessage(error.localizedDescription)
        }
    }

    func setStatusMessage(_ message: String?) {
        statusClearTask?.cancel()
        statusMessage = message
        guard let message, !message.isEmpty else { return }
        statusClearTask = Task {
            try? await Task.sleep(for: .seconds(6))
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
        isLoadingModel = true
        setStatusMessage("\(model.name) yükleniyor…")
        defer { isLoadingModel = false }
        do {
            inferenceService.settings = settings
            try await inferenceService.loadModel(model)
            selectedModelId = model.id
            currentSession.modelId = model.id
            setStatusMessage("\(model.name) hazır")
            refreshModels()
            return true
        } catch {
            setStatusMessage("Yükleme hatası: \(error.localizedDescription)")
            return false
        }
    }

    func unloadCurrentModel() async {
        if inferenceService.isGenerating {
            stopGeneration()
        }
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
        if selectedModelId == model.id {
            await inferenceService.unloadModel()
            selectedModelId = nil
        }
        do {
            try modelStore.deleteModel(id: model.id)
            refreshModels()
            setStatusMessage("\(model.name) silindi")
        } catch {
            setStatusMessage(error.localizedDescription)
        }
    }

    func importGGUF(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        setStatusMessage("Model kopyalanıyor…")
        do {
            let filename = url.lastPathComponent
            let id = filename.replacingOccurrences(of: ".gguf", with: "")
            let dest = modelStore.destinationURL(repoId: "imported", filename: filename)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
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

    func newChat() {
        if inferenceService.isGenerating {
            stopGeneration()
        }
        if !currentSession.messages.isEmpty {
            Task { try? await saveCurrentSession() }
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

    func loadSession(_ session: ChatSession) {
        if !currentSession.messages.isEmpty, currentSession.id != session.id {
            Task { try? await saveCurrentSession() }
        }
        if let stored = try? chatStore.loadSession(id: session.id) {
            currentSession = stored
        } else {
            currentSession = session
        }
        if let modelId = currentSession.modelId,
           let model = installedModels.first(where: { $0.id == modelId }) {
            selectedModelId = modelId
            Task { await selectModel(model) }
        }
    }

    func sendMessage(_ text: String, pendingAttachments: [MessageAttachment] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }
        guard let model = selectedModel else {
            setStatusMessage("Önce bir model seçin veya indirin")
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
            if !caps.supportsVision && mediaAttachments.contains(where: { $0.kind == .image }) {
                setStatusMessage(
                    "Görüntü/video için vision modeli ve mmproj GGUF gerekir. Belgeler metin olarak gönderilebilir."
                )
                if trimmed.isEmpty, attachments.allSatisfy({ $0.kind == .image || $0.kind == .video }) {
                    return
                }
            }
            if mediaAttachments.contains(where: { $0.kind == .audio }), !caps.supportsAudio {
                setStatusMessage("Ses için ses destekli vision modeli gerekir.")
            }
            if caps.requiresMmproj, model.mmprojLocalPath == nil {
                setStatusMessage(
                    "Bu model çok modlu — aynı klasöre mmproj GGUF dosyasını ekleyip modeli yeniden yükleyin."
                )
                if mediaAttachments.allSatisfy({ $0.kind == .image || $0.kind == .audio }) && trimmed.isEmpty {
                    return
                }
            }
        }

        let displayText = trimmed.isEmpty ? attachments.map(\.fileName).joined(separator: ", ") : trimmed
        currentSession.messages.append(
            ChatMessage(role: .user, content: displayText, attachments: attachments)
        )
        let assistantIndex = currentSession.messages.count
        currentSession.messages.append(ChatMessage(role: .assistant, content: ""))

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
            if !pending.isEmpty {
                let combined = currentSession.messages[assistantIndex].content + pending
                currentSession.messages[assistantIndex].content =
                    ControlTokenSanitizer.sanitizeForDisplay(combined)
            }
            currentSession.messages[assistantIndex].content = ControlTokenSanitizer.sanitizeForDisplay(
                currentSession.messages[assistantIndex].content
            )
            try await saveCurrentSession()
        } catch is CancellationError {
            setStatusMessage("Üretim durduruldu")
        } catch {
            if currentSession.messages[assistantIndex].content.isEmpty {
                currentSession.messages[assistantIndex].content = "Hata: \(error.localizedDescription)"
            }
            setStatusMessage(error.localizedDescription)
        }
    }

    func stopGeneration() {
        inferenceService.stopGeneration()
    }

    private static func trimMessagesForContext(_ messages: [ChatMessage], maxContextTokens: Int) -> [ChatMessage] {
        let budget = max(512, Int(Double(maxContextTokens) * 0.82))
        var estimated = 0
        var kept: [ChatMessage] = []
        for message in messages.reversed() {
            let cost = max(1, message.content.count / 4)
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

    func saveSettings() {
        inferenceService.settings = settings
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "inferenceSettings")
        }
        setStatusMessage("Ayarlar kaydedildi")
        if let model = selectedModel {
            Task { await selectModel(model) }
        }
    }
}

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
    var showSettings = false

    private let modelStore = ModelStore.shared
    private let catalogService = ModelCatalogService.shared
    private let recommendationService = ModelRecommendationService.shared
    private let downloadService = HuggingFaceDownloadService.shared
    private let inferenceService = InferenceService.shared
    private let chatStore = ChatHistoryStore.shared

    var selectedModel: InstalledModel? {
        installedModels.first { $0.id == selectedModelId }
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
            if selectedModelId == nil, let first = installedModels.first {
                await selectModel(first)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshModels() {
        do {
            installedModels = try modelStore.loadInstalledModels()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func selectModel(_ model: InstalledModel) async -> Bool {
        isLoadingModel = true
        statusMessage = "\(model.name) yükleniyor..."
        defer { isLoadingModel = false }
        do {
            inferenceService.settings = settings
            try await inferenceService.loadModel(model)
            selectedModelId = model.id
            currentSession.modelId = model.id
            statusMessage = "\(model.name) hazır"
            refreshModels()
            return true
        } catch {
            statusMessage = "Yükleme hatası: \(error.localizedDescription)"
            return false
        }
    }

    func downloadModel(_ entry: CatalogEntry) async {
        statusMessage = "\(entry.name) indiriliyor…"
        do {
            let localURL = try await downloadService.download(entry: entry) { info in
                Task { @MainActor in
                    let eta = info.estimatedSecondsRemaining.map {
                        DownloadMetrics.formatETA(seconds: $0)
                    } ?? "—"
                    self.statusMessage = String(
                        format: "%.0f%% · %@ · kalan %@",
                        info.progress * 100,
                        entry.name,
                        eta
                    )
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
                statusMessage = "\(entry.name) kaydedildi ancak listede bulunamadı."
                return
            }
            let loaded = await selectModel(model)
            if loaded {
                statusMessage = "\(entry.name) indirildi ve kullanıma hazır"
            } else {
                statusMessage = "\(entry.name) indirildi; yüklenemedi — soldan «Yükle» veya tekrar deneyin."
            }
        } catch is CancellationError {
            statusMessage = "İndirme iptal edildi"
        } catch {
            statusMessage = "İndirme hatası: \(error.localizedDescription)"
        }
    }

    func deleteModel(_ model: InstalledModel) async {
        if selectedModelId == model.id {
            inferenceService.unloadModel()
            selectedModelId = nil
        }
        do {
            try modelStore.deleteModel(id: model.id)
            refreshModels()
            statusMessage = "\(model.name) silindi"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importGGUF(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        statusMessage = "Model kopyalanıyor…"
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
            _ = try modelStore.registerModel(
                id: id,
                name: filename,
                repoId: "imported",
                filename: filename,
                localURL: dest,
                chatTemplate: HuggingFaceHubService.guessChatTemplate(repoId: filename, filename: filename)
            )
            refreshModels()
            if let model = installedModels.first(where: { $0.id == id }) {
                let loaded = await selectModel(model)
                statusMessage = loaded ? "Model içe aktarıldı ve hazır" : "Model içe aktarıldı; yüklenemedi"
            } else {
                statusMessage = "Model içe aktarıldı"
            }
        } catch {
            statusMessage = "İçe aktarma hatası: \(error.localizedDescription)"
        }
    }

    func newChat() {
        if !currentSession.messages.isEmpty {
            Task { try? await saveCurrentSession() }
        }
        currentSession = ChatSession(modelId: selectedModelId)
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
        currentSession = session
        if let modelId = session.modelId,
           let model = installedModels.first(where: { $0.id == modelId }) {
            Task { await selectModel(model) }
        }
    }

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let model = selectedModel else {
            statusMessage = "Önce bir model seçin veya indirin"
            return
        }
        guard inferenceService.isModelLoaded, inferenceService.loadedModelId == model.id else {
            statusMessage = isLoadingModel ? "Model yükleniyor…" : "Model henüz hazır değil — soldan seçin veya yükleyin"
            if !isLoadingModel {
                Task { _ = await selectModel(model) }
            }
            return
        }

        currentSession.messages.append(ChatMessage(role: .user, content: trimmed))
        let assistantIndex = currentSession.messages.count
        currentSession.messages.append(ChatMessage(role: .assistant, content: ""))

        let template = model.chatTemplate
        let messagesForInference = Self.trimMessagesForContext(
            currentSession.messages.dropLast().map { $0 },
            maxContextTokens: Int(settings.contextLength)
        )
        let stream = inferenceService.streamResponse(messages: messagesForInference, chatTemplate: template)

        do {
            var pending = ""
            var lastFlush = Date()
            for try await chunk in stream {
                pending += chunk
                let now = Date()
                if now.timeIntervalSince(lastFlush) >= 0.06 {
                    currentSession.messages[assistantIndex].content += pending
                    pending = ""
                    lastFlush = now
                }
            }
            if !pending.isEmpty {
                currentSession.messages[assistantIndex].content += pending
            }
            try await saveCurrentSession()
        } catch is CancellationError {
            statusMessage = "Üretim durduruldu"
        } catch {
            if currentSession.messages[assistantIndex].content.isEmpty {
                currentSession.messages[assistantIndex].content = "Hata: \(error.localizedDescription)"
            }
            statusMessage = error.localizedDescription
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
        statusMessage = "Ayarlar kaydedildi"
        if let model = selectedModel {
            Task { await selectModel(model) }
        }
    }
}

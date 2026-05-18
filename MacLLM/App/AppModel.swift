import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var installedModels: [InstalledModel] = []
    var catalogEntries: [CatalogEntry] = []
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
            catalogEntries = try catalogService.loadDefaultCatalog()
            sessions = try chatStore.loadSessionIndex()
            if let saved = UserDefaults.standard.data(forKey: "inferenceSettings"),
               let decoded = try? JSONDecoder().decode(InferenceSettings.self, from: saved) {
                settings = decoded
                inferenceService.settings = decoded
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

    func selectModel(_ model: InstalledModel) async {
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
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func downloadModel(_ entry: CatalogEntry) async {
        statusMessage = "\(entry.name) indiriliyor..."
        do {
            let localURL = try await downloadService.download(entry: entry) { info in
                Task { @MainActor in
                    self.statusMessage = String(format: "%.0f%% — %@", info.progress * 100, entry.name)
                }
            }
            _ = try modelStore.registerModel(
                id: entry.id,
                name: entry.name,
                repoId: entry.repoId,
                filename: entry.filename,
                localURL: localURL,
                chatTemplate: entry.chatTemplate
            )
            refreshModels()
            if let model = installedModels.first(where: { $0.id == entry.id }) {
                await selectModel(model)
            }
            statusMessage = "\(entry.name) indirildi"
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

        do {
            let filename = url.lastPathComponent
            let id = filename.replacingOccurrences(of: ".gguf", with: "")
            let dest = modelStore.destinationURL(repoId: "imported", filename: filename)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            _ = try modelStore.registerModel(
                id: id,
                name: filename,
                repoId: "imported",
                filename: filename,
                localURL: dest,
                chatTemplate: "chatml"
            )
            refreshModels()
            if let model = installedModels.first(where: { $0.id == id }) {
                await selectModel(model)
            }
            statusMessage = "Model içe aktarıldı"
        } catch {
            statusMessage = error.localizedDescription
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
        guard let model = selectedModel, inferenceService.isModelLoaded else {
            statusMessage = "Önce bir model seçin veya indirin"
            return
        }

        currentSession.messages.append(ChatMessage(role: .user, content: trimmed))
        let assistantIndex = currentSession.messages.count
        currentSession.messages.append(ChatMessage(role: .assistant, content: ""))

        let template = model.chatTemplate
        let stream = inferenceService.streamResponse(messages: currentSession.messages.dropLast().map { $0 }, chatTemplate: template)

        do {
            for try await chunk in stream {
                currentSession.messages[assistantIndex].content += chunk
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

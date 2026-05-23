import Foundation

enum ModelStoreError: LocalizedError {
    case directoryCreationFailed
    case modelNotFound
    case invalidMetadata

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            return "Model klasörü oluşturulamadı."
        case .modelNotFound:
            return "Model bulunamadı."
        case .invalidMetadata:
            return "Model metadata dosyası geçersiz."
        }
    }
}

final class ModelStore: @unchecked Sendable {
    static let shared = ModelStore()

    private let fileManager = FileManager.default

    var appSupportURL: URL {
        let base = applicationSupportBaseURL()
        return base.appendingPathComponent("MacLLM", isDirectory: true)
    }

    /// Eski MacSistem verilerini MacLLM klasörüne taşır (bir kez).
    func migrateLegacyStorageIfNeeded() {
        let base = applicationSupportBaseURL()
        let legacy = base.appendingPathComponent("MacSistem", isDirectory: true)
        let modern = base.appendingPathComponent("MacLLM", isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: modern.path) else { return }
        try? fileManager.moveItem(at: legacy, to: modern)
    }

    var modelsDirectory: URL {
        appSupportURL.appendingPathComponent("models", isDirectory: true)
    }

    var metadataURL: URL {
        appSupportURL.appendingPathComponent("installed-models.json")
    }

    private func applicationSupportBaseURL() -> URL {
        if let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return base
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    func ensureDirectories() throws {
        migrateLegacyStorageIfNeeded()
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: appSupportURL.appendingPathComponent("chats", isDirectory: true), withIntermediateDirectories: true)
    }

    func loadInstalledModels() throws -> [InstalledModel] {
        try ensureDirectories()
        guard fileManager.fileExists(atPath: metadataURL.path) else { return [] }
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode([InstalledModel].self, from: data)
    }

    func saveInstalledModels(_ models: [InstalledModel]) throws {
        try ensureDirectories()
        let data = try JSONEncoder().encode(models)
        try data.write(to: metadataURL, options: .atomic)
    }

    func destinationURL(repoId: String, filename: String) -> URL {
        let safeRepo = repoId.replacingOccurrences(of: "/", with: "__")
        let dir = modelsDirectory.appendingPathComponent(safeRepo, isDirectory: true)
        return dir.appendingPathComponent(filename)
    }

    func registerModel(
        id: String,
        name: String,
        repoId: String,
        filename: String,
        localURL: URL,
        chatTemplate: String,
        mmprojURL: URL? = nil
    ) throws -> InstalledModel {
        var models = try loadInstalledModels()
        let attrs = try fileManager.attributesOfItem(atPath: localURL.path)
        let size = (attrs[.size] as? Int64) ?? 0

        let entry = InstalledModel(
            id: id,
            name: name,
            repoId: repoId,
            filename: filename,
            localPath: localURL.path,
            chatTemplate: chatTemplate,
            fileSizeBytes: size,
            downloadedAt: .now,
            lastUsedAt: nil,
            mmprojLocalPath: mmprojURL?.path,
            mmprojFilename: mmprojURL?.lastPathComponent
        )

        models.removeAll { $0.id == id }
        models.insert(entry, at: 0)
        try saveInstalledModels(models)
        return entry
    }

    func deleteModel(id: String) throws {
        var models = try loadInstalledModels()
        guard let index = models.firstIndex(where: { $0.id == id }) else {
            throw ModelStoreError.modelNotFound
        }
        let model = models[index]
        let url = URL(fileURLWithPath: model.localPath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let parent = url.deletingLastPathComponent()
        if let contents = try? fileManager.contentsOfDirectory(atPath: parent.path), contents.isEmpty {
            try? fileManager.removeItem(at: parent)
        }
        models.remove(at: index)
        try saveInstalledModels(models)
    }

    func touchLastUsed(id: String) throws {
        var models = try loadInstalledModels()
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }
        models[index].lastUsedAt = .now
        try saveInstalledModels(models)
    }

    func totalDiskUsageBytes() throws -> Int64 {
        try loadInstalledModels().reduce(0) { $0 + $1.fileSizeBytes }
    }

    func availableDiskBytes() -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? appSupportURL.resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return available
    }
}

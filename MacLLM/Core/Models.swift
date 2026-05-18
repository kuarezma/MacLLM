import Foundation

// MARK: - Catalog

struct CatalogEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let repoId: String
    let filename: String
    let estimatedSizeBytes: Int64
    let chatTemplate: String
    let ramHintGB: Int
    /// Katalogda listelenmesi için önerilen minimum fiziksel RAM (GB).
    let minPhysicalRamGB: Int?

    init(
        id: String,
        name: String,
        description: String,
        repoId: String,
        filename: String,
        estimatedSizeBytes: Int64,
        chatTemplate: String,
        ramHintGB: Int,
        minPhysicalRamGB: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.repoId = repoId
        self.filename = filename
        self.estimatedSizeBytes = estimatedSizeBytes
        self.chatTemplate = chatTemplate
        self.ramHintGB = ramHintGB
        self.minPhysicalRamGB = minPhysicalRamGB
    }
}

struct DefaultCatalog: Codable {
    let models: [CatalogEntry]
}

// MARK: - Installed model

struct InstalledModel: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var repoId: String
    var filename: String
    var localPath: String
    var chatTemplate: String
    var fileSizeBytes: Int64
    var downloadedAt: Date
    var lastUsedAt: Date?

    var fileURL: URL { URL(fileURLWithPath: localPath) }
}

// MARK: - Chat

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: UUID
    var role: ChatRole
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatSession: Codable, Identifiable {
    var id: UUID
    var title: String
    var modelId: String?
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Yeni sohbet",
        modelId: String? = nil,
        messages: [ChatMessage] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.modelId = modelId
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Download

struct DownloadTaskInfo: Identifiable {
    let id: String
    let catalogEntry: CatalogEntry
    var progress: Double
    var bytesReceived: Int64
    var totalBytes: Int64
    var bytesPerSecond: Double
    var estimatedSecondsRemaining: TimeInterval?
    var state: DownloadState
    var errorMessage: String?
}

enum DownloadState: String {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case cancelled
}

// MARK: - Inference settings

struct InferenceSettings: Codable, Equatable {
    var temperature: Float
    var topP: Float
    var maxTokens: Int32
    var contextLength: UInt32
    var gpuLayers: Int32
    var threadCount: Int32

    static let `default` = InferenceSettings(
        temperature: 0.7,
        topP: 0.9,
        maxTokens: 1024,
        contextLength: 4096,
        gpuLayers: -1,
        threadCount: Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
    )

    static func defaults(for profile: MacSystemProfile) -> InferenceSettings {
        var settings = InferenceSettings.default
        switch profile.physicalMemoryGB {
        case ..<10:
            settings.contextLength = 2048
            settings.maxTokens = 768
        case 10..<18:
            settings.contextLength = 4096
            settings.maxTokens = 1024
        case 18..<26:
            settings.contextLength = 6144
            settings.maxTokens = 1536
        default:
            settings.contextLength = 8192
            settings.maxTokens = 2048
        }
        settings.threadCount = Int32(max(1, min(8, profile.processorCount - 2)))
        return settings
    }
}

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

// MARK: - Inference settings (Ollama-compatible parameters)

/// Ollama `Modelfile` / API parametreleriyle uyumlu çıkarım ayarları.
struct InferenceSettings: Codable, Equatable {
    // Örnekleme (temperature, top_p, top_k, min_p, seed, mirostat)
    var temperature: Float
    var topP: Float
    var topK: Int32
    var minP: Float
    var seed: UInt32
    var mirostat: Int32
    var mirostatTau: Float
    var mirostatEta: Float

    // Tekrar cezası (repeat_penalty, repeat_last_n)
    var repeatPenalty: Float
    var repeatLastN: Int32

    // Bağlam ve donanım (num_ctx, num_gpu, num_thread)
    var maxTokens: Int32
    var contextLength: UInt32
    var gpuLayers: Int32
    var threadCount: Int32

    // Sohbet (system, stop)
    var systemPrompt: String
    var stopSequences: [String]

    enum CodingKeys: String, CodingKey {
        case temperature, topP, topK, minP, seed, mirostat, mirostatTau, mirostatEta
        case repeatPenalty, repeatLastN
        case maxTokens, contextLength, gpuLayers, threadCount
        case systemPrompt, stopSequences
    }

    init(
        temperature: Float = 0.8,
        topP: Float = 0.9,
        topK: Int32 = 40,
        minP: Float = 0,
        seed: UInt32 = 0,
        mirostat: Int32 = 0,
        mirostatTau: Float = 5,
        mirostatEta: Float = 0.1,
        repeatPenalty: Float = 1.1,
        repeatLastN: Int32 = 64,
        maxTokens: Int32 = 1024,
        contextLength: UInt32 = 4096,
        gpuLayers: Int32 = -1,
        threadCount: Int32 = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2))),
        systemPrompt: String = "",
        stopSequences: [String] = ["</s>", "<|eot_id|>"]
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.seed = seed
        self.mirostat = mirostat
        self.mirostatTau = mirostatTau
        self.mirostatEta = mirostatEta
        self.repeatPenalty = repeatPenalty
        self.repeatLastN = repeatLastN
        self.maxTokens = maxTokens
        self.contextLength = contextLength
        self.gpuLayers = gpuLayers
        self.threadCount = threadCount
        self.systemPrompt = systemPrompt
        self.stopSequences = stopSequences
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try c.decodeIfPresent(Float.self, forKey: .temperature) ?? 0.8
        topP = try c.decodeIfPresent(Float.self, forKey: .topP) ?? 0.9
        topK = try c.decodeIfPresent(Int32.self, forKey: .topK) ?? 40
        minP = try c.decodeIfPresent(Float.self, forKey: .minP) ?? 0
        seed = try c.decodeIfPresent(UInt32.self, forKey: .seed) ?? 0
        mirostat = try c.decodeIfPresent(Int32.self, forKey: .mirostat) ?? 0
        mirostatTau = try c.decodeIfPresent(Float.self, forKey: .mirostatTau) ?? 5
        mirostatEta = try c.decodeIfPresent(Float.self, forKey: .mirostatEta) ?? 0.1
        repeatPenalty = try c.decodeIfPresent(Float.self, forKey: .repeatPenalty) ?? 1.1
        repeatLastN = try c.decodeIfPresent(Int32.self, forKey: .repeatLastN) ?? 64
        maxTokens = try c.decodeIfPresent(Int32.self, forKey: .maxTokens) ?? 1024
        contextLength = try c.decodeIfPresent(UInt32.self, forKey: .contextLength) ?? 4096
        gpuLayers = try c.decodeIfPresent(Int32.self, forKey: .gpuLayers) ?? -1
        threadCount = try c.decodeIfPresent(Int32.self, forKey: .threadCount)
            ?? Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        stopSequences = try c.decodeIfPresent([String].self, forKey: .stopSequences)
            ?? ["</s>", "<|eot_id|>"]
    }

    /// Ollama varsayılanlarına yakın profil.
    static var ollamaDefaults: InferenceSettings {
        InferenceSettings()
    }

    static let `default` = InferenceSettings()

    static func defaults(for profile: MacSystemProfile) -> InferenceSettings {
        var settings = InferenceSettings.ollamaDefaults
        switch profile.physicalMemoryGB {
        case ..<10:
            settings.contextLength = 2048
            settings.maxTokens = 768
            settings.gpuLayers = 20
        case 10..<18:
            settings.contextLength = 4096
            settings.maxTokens = 1024
            settings.gpuLayers = 40
        case 18..<26:
            settings.contextLength = 6144
            settings.maxTokens = 1536
            settings.gpuLayers = 60
        default:
            settings.contextLength = 8192
            settings.maxTokens = 2048
            settings.gpuLayers = -1
        }
        settings.threadCount = Int32(max(1, min(8, profile.processorCount - 2)))
        return settings
    }

    var stopSequencesText: String {
        get { stopSequences.joined(separator: "\n") }
        set {
            stopSequences = newValue
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }
                .filter { !$0.isEmpty }
        }
    }

    var usesMirostat: Bool { mirostat > 0 }
}

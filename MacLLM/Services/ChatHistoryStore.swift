import Foundation

/// Sohbet özeti — `chat-sessions-index.json` içinde; mesajlar ayrı dosyada.
struct ChatSessionSummary: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var modelId: String?
    var createdAt: Date
    var updatedAt: Date

    init(from session: ChatSession) {
        id = session.id
        title = session.title
        modelId = session.modelId
        createdAt = session.createdAt
        updatedAt = session.updatedAt
    }

    func asEmptySession() -> ChatSession {
        ChatSession(
            id: id,
            title: title,
            modelId: modelId,
            messages: [],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct ChatSessionIndexFile: Codable {
    var version: Int
    var sessions: [ChatSessionSummary]
}

final class ChatHistoryStore: Sendable {
    static let shared = ChatHistoryStore()

    private let fileManager = FileManager.default
    private let indexVersion = 2

    private var chatsDirectory: URL {
        ModelStore.shared.appSupportURL.appendingPathComponent("chats", isDirectory: true)
    }

    private var indexURL: URL {
        ModelStore.shared.appSupportURL.appendingPathComponent("chat-sessions-index.json")
    }

    private var legacyIndexURL: URL {
        ModelStore.shared.appSupportURL.appendingPathComponent("chat-sessions-index.v1.backup.json")
    }

    private func sessionFileURL(id: UUID) -> URL {
        chatsDirectory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    func loadSessionIndex() throws -> [ChatSession] {
        try ModelStore.shared.ensureDirectories()
        try migrateLegacyIndexIfNeeded()

        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let index = try JSONDecoder().decode(ChatSessionIndexFile.self, from: data)
        return index.sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { $0.asEmptySession() }
    }

    func loadSession(id: UUID) throws -> ChatSession? {
        let summaries = try loadSummaries()
        guard summaries.contains(where: { $0.id == id }) else { return nil }
        let url = sessionFileURL(id: id)
        guard fileManager.fileExists(atPath: url.path) else {
            return summaries.first(where: { $0.id == id })?.asEmptySession()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ChatSession.self, from: data)
    }

    func saveSession(_ session: ChatSession) throws {
        try ModelStore.shared.ensureDirectories()
        let url = sessionFileURL(id: session.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: url, options: .atomic)

        var summaries = try loadSummaries()
        let summary = ChatSessionSummary(from: session)
        if let index = summaries.firstIndex(where: { $0.id == session.id }) {
            summaries[index] = summary
        } else {
            summaries.insert(summary, at: 0)
        }
        try writeIndex(summaries)
    }

    func deleteSession(id: UUID) throws {
        var summaries = try loadSummaries()
        summaries.removeAll { $0.id == id }
        try writeIndex(summaries)
        let url = sessionFileURL(id: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Private

    private func loadSummaries() throws -> [ChatSessionSummary] {
        try migrateLegacyIndexIfNeeded()
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let index = try JSONDecoder().decode(ChatSessionIndexFile.self, from: data)
        return index.sessions
    }

    private func writeIndex(_ summaries: [ChatSessionSummary]) throws {
        let sorted = summaries.sorted { $0.updatedAt > $1.updatedAt }
        let index = ChatSessionIndexFile(version: indexVersion, sessions: sorted)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    /// Eski tek dosyalı indeksi oturum başına dosyaya taşır.
    private func migrateLegacyIndexIfNeeded() throws {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }

        let data = try Data(contentsOf: indexURL)
        if let index = try? JSONDecoder().decode(ChatSessionIndexFile.self, from: data),
           index.version >= indexVersion {
            return
        }

        guard let legacySessions = try? JSONDecoder().decode([ChatSession].self, from: data),
              !legacySessions.isEmpty else {
            return
        }

        if !fileManager.fileExists(atPath: legacyIndexURL.path) {
            try fileManager.copyItem(at: indexURL, to: legacyIndexURL)
        }

        for session in legacySessions {
            let url = sessionFileURL(id: session.id)
            if !fileManager.fileExists(atPath: url.path) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let payload = try encoder.encode(session)
                try payload.write(to: url, options: .atomic)
            }
        }

        let summaries = legacySessions.map { ChatSessionSummary(from: $0) }
        try writeIndex(summaries)
    }
}

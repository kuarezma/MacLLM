import Foundation

final class ChatHistoryStore: Sendable {
    static let shared = ChatHistoryStore()

    private let fileManager = FileManager.default

    private var chatsDirectory: URL {
        ModelStore.shared.appSupportURL.appendingPathComponent("chats", isDirectory: true)
    }

    private var indexURL: URL {
        ModelStore.shared.appSupportURL.appendingPathComponent("chat-sessions-index.json")
    }

    func loadSessionIndex() throws -> [ChatSession] {
        try ModelStore.shared.ensureDirectories()
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return try JSONDecoder().decode([ChatSession].self, from: data)
    }

    func saveSessionIndex(_ sessions: [ChatSession]) throws {
        try ModelStore.shared.ensureDirectories()
        let data = try JSONEncoder().encode(sessions)
        try data.write(to: indexURL, options: .atomic)
    }

    func loadSession(id: UUID) throws -> ChatSession? {
        try loadSessionIndex().first { $0.id == id }
    }

    func saveSession(_ session: ChatSession) throws {
        var sessions = try loadSessionIndex()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        try saveSessionIndex(sessions)
    }

    func deleteSession(id: UUID) throws {
        var sessions = try loadSessionIndex()
        sessions.removeAll { $0.id == id }
        try saveSessionIndex(sessions)
    }
}

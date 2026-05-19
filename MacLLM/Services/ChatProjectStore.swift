import Foundation

struct ChatProject: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, systemPrompt, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

private struct ChatProjectIndex: Codable {
    var projects: [ChatProject]
}

final class ChatProjectStore: @unchecked Sendable {
    static let shared = ChatProjectStore()

    private let fileManager = FileManager.default

    private var indexURL: URL {
        ModelStore.shared.appSupportURL.appendingPathComponent("chat-projects.json")
    }

    func load() throws -> [ChatProject] {
        try ModelStore.shared.ensureDirectories()
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let index = try JSONDecoder().decode(ChatProjectIndex.self, from: data)
        return index.projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ project: ChatProject) throws {
        var projects = (try? load()) ?? []
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
        try write(projects)
    }

    func delete(id: UUID) throws {
        var projects = (try? load()) ?? []
        projects.removeAll { $0.id == id }
        try write(projects)
    }

    private func write(_ projects: [ChatProject]) throws {
        let index = ChatProjectIndex(projects: projects)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }
}

enum ChatExporter {
    static func markdown(for session: ChatSession, modelName: String?) -> String {
        var lines: [String] = [
            "# \(session.title)",
            "",
            "Oluşturulma: \(formatted(session.createdAt))",
            "Güncelleme: \(formatted(session.updatedAt))",
        ]
        if let modelName, !modelName.isEmpty {
            lines.append("Model: \(modelName)")
        }
        lines.append("")

        for message in session.messages {
            let label: String
            switch message.role {
            case .user: label = "Kullanıcı"
            case .assistant: label = "Asistan"
            case .system: label = "Sistem"
            }
            lines.append("## \(label)")
            lines.append("")
            lines.append(message.content)
            if !message.attachments.isEmpty {
                lines.append("")
                lines.append("_Ekler: \(message.attachments.map(\.fileName).joined(separator: ", "))_")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

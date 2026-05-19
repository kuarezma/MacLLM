import Foundation

enum ChatImporter {
    /// `ChatExporter` markdown çıktısından oturum oluşturur.
    static func session(fromMarkdown content: String) -> ChatSession? {
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return nil }

        var title = "İçe aktarılan sohbet"
        if lines[0].hasPrefix("# ") {
            title = String(lines[0].dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }

        var messages: [ChatMessage] = []
        var currentRole: ChatRole?
        var buffer: [String] = []

        func flush() {
            guard let role = currentRole else { return }
            let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                messages.append(ChatMessage(role: role, content: body))
            }
            buffer.removeAll(keepingCapacity: true)
        }

        for line in lines.dropFirst() {
            if line.hasPrefix("## ") {
                flush()
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                switch heading {
                case "Kullanıcı": currentRole = .user
                case "Asistan": currentRole = .assistant
                case "Sistem": currentRole = .system
                default: currentRole = nil
                }
                continue
            }
            if line.hasPrefix("Oluşturulma:") || line.hasPrefix("Güncelleme:") || line.hasPrefix("Model:") {
                continue
            }
            if line.hasPrefix("_Ekler:") {
                continue
            }
            if currentRole != nil {
                buffer.append(line)
            }
        }
        flush()

        guard !messages.isEmpty else { return nil }
        return ChatSession(title: title, messages: messages)
    }
}

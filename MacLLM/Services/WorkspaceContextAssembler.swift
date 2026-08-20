import Foundation

enum WorkspaceContextAssembler {
    /// Mesaj içerisindeki `@dosya_adı` etiketlerini bulur ve dosya içeriklerini mesaja kod bloğu olarak iliştirir.
    static func enrichUserMessageWithMentionedFiles(_ content: String) -> (enrichedContent: String, mentionedFiles: [String]) {
        let allFiles = ProjectWorkspaceService.shared.listAllFiles(maxCount: 1000)
        guard !allFiles.isEmpty else { return (content, []) }

        var mentionedFiles: [String] = []
        var addedCodeBlocks: [String] = []

        let words = content.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        for word in words where word.hasPrefix("@") && word.count > 1 {
            let mention = String(word.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",;:!?()[]\"'"))
            guard !mention.isEmpty else { continue }

            if let matchedFile = allFiles.first(where: {
                $0.localizedCaseInsensitiveContains(mention) ||
                $0.lastPathComponentLowercased == mention.lowercased()
            }) {
                if !mentionedFiles.contains(matchedFile) {
                    mentionedFiles.append(matchedFile)
                    if let fileData = try? ProjectWorkspaceService.shared.readFile(relativePath: matchedFile, startLine: 1, endLine: 300) {
                        let ext = (matchedFile as NSString).pathExtension
                        let block = """
                        
                        ---
                        ### Dosya Bağlamı: `\(matchedFile)`
                        ```\(ext)
                        \(fileData.content)
                        ```
                        """
                        addedCodeBlocks.append(block)
                    }
                }
            }
        }

        if addedCodeBlocks.isEmpty {
            return (content, [])
        }

        let enriched = content + "\n" + addedCodeBlocks.joined(separator: "\n")
        return (enriched, mentionedFiles)
    }

    /// Proje dizin ağacının özetini ajan sistem istemi için hazırlar.
    static func buildWorkspaceTreeSummary(maxFiles: Int = 50) -> String {
        let files = ProjectWorkspaceService.shared.listAllFiles(maxCount: maxFiles)
        guard !files.isEmpty else { return "Çalışma dizini boş veya dosya bulunamadı." }

        var lines: [String] = ["Proje Dosya Ağacı:"]
        for file in files {
            lines.append(" - \(file)")
        }
        if files.count >= maxFiles {
            lines.append(" - ... (ve diğer dosyalar)")
        }
        return lines.joined(separator: "\n")
    }
}

private extension String {
    var lastPathComponentLowercased: String {
        (self as NSString).lastPathComponent.lowercased()
    }
}

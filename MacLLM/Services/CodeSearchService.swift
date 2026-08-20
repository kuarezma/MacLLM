import Foundation
import OSLog

struct CodeSearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let relativePath: String
    let lineNumber: Int
    let lineContent: String
    let contextSnippet: String

    init(
        relativePath: String,
        lineNumber: Int,
        lineContent: String,
        contextSnippet: String = ""
    ) {
        self.id = "\(relativePath):\(lineNumber)"
        self.relativePath = relativePath
        self.lineNumber = lineNumber
        self.lineContent = lineContent
        self.contextSnippet = contextSnippet
    }
}

enum CodeSearchService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacLLM", category: "CodeSearch")

    static func search(
        query: String,
        extensionFilter: String? = nil,
        maxResults: Int = 30
    ) -> [CodeSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let files = ProjectWorkspaceService.shared.listAllFiles(maxCount: 1000)
        var results: [CodeSearchResult] = []

        let ext = extensionFilter?.trimmingCharacters(in: CharacterSet(charactersIn: ". \t\n"))

        for file in files {
            if let ext, !ext.isEmpty, !file.lowercased().hasSuffix(".\(ext.lowercased())") {
                continue
            }

            guard let readResult = try? ProjectWorkspaceService.shared.readFile(relativePath: file) else {
                continue
            }

            let lines = readResult.content.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                if line.localizedCaseInsensitiveContains(trimmedQuery) {
                    let lineNum = idx + 1
                    let startCtx = max(0, idx - 2)
                    let endCtx = min(lines.count - 1, idx + 2)
                    let snippet = lines[startCtx...endCtx].joined(separator: "\n")

                    results.append(CodeSearchResult(
                        relativePath: file,
                        lineNumber: lineNum,
                        lineContent: line.trimmingCharacters(in: .whitespaces),
                        contextSnippet: snippet
                    ))

                    if results.count >= maxResults {
                        return results
                    }
                }
            }
        }

        return results
    }
}

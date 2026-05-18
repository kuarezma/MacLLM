import Foundation

enum MarkdownBlock: Equatable {
    case text(String)
    case code(language: String?, content: String)
}

/// Basit Markdown ayrıştırıcı (kod çitleri). SwiftUI bağımlılığı yok — birim test edilebilir.
enum MarkdownContentParser {
    static func blocks(from markdown: String) -> [MarkdownBlock] {
        guard markdown.contains("```") else {
            return markdown.isEmpty ? [] : [.text(markdown)]
        }

        var result: [MarkdownBlock] = []
        var remaining = markdown[...]
        let fence = "```"

        while !remaining.isEmpty {
            guard let openRange = remaining.range(of: fence) else {
                let tail = String(remaining)
                if !tail.isEmpty { result.append(.text(tail)) }
                break
            }

            let before = String(remaining[..<openRange.lowerBound])
            if !before.isEmpty { result.append(.text(before)) }

            remaining = remaining[openRange.upperBound...]
            var language = ""
            if let newline = remaining.firstIndex(of: "\n") {
                language = String(remaining[..<newline]).trimmingCharacters(in: .whitespaces)
                remaining = remaining[newline...].dropFirst()
            }

            if let closeRange = remaining.range(of: fence) {
                let code = String(remaining[..<closeRange.lowerBound])
                    .trimmingCharacters(in: .newlines)
                let lang = language.isEmpty ? nil : language
                result.append(.code(language: lang, content: code))
                remaining = remaining[closeRange.upperBound...]
            } else {
                let code = String(remaining).trimmingCharacters(in: .newlines)
                let lang = language.isEmpty ? nil : language
                result.append(.code(language: lang, content: code))
                break
            }
        }

        return result
    }
}

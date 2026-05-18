import Foundation

enum MarkdownBlock: Equatable {
    case text(String)
    case code(language: String?, content: String)
}

enum ProseSegment: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bulletList([String])
    case numberedList([String])
}

/// Basit Markdown ayrıştırıcı (kod çitleri, başlıklar, listeler). SwiftUI bağımlılığı yok.
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

    /// Düz metin bloğunu paragraflar, başlıklar ve listelere ayırır.
    static func proseSegments(from text: String) -> [ProseSegment] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var segments: [ProseSegment] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let stripped = line.trimmingCharacters(in: .whitespaces)

            if stripped.isEmpty {
                index += 1
                continue
            }

            if let heading = parseHeading(stripped) {
                segments.append(heading)
                index += 1
                continue
            }

            if let bullet = parseBullet(stripped) {
                var items = [bullet]
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty { index += 1; break }
                    if let item = parseBullet(next) {
                        items.append(item)
                        index += 1
                    } else {
                        break
                    }
                }
                segments.append(.bulletList(items))
                continue
            }

            if let numbered = parseNumbered(stripped) {
                var items = [numbered]
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty { index += 1; break }
                    if let item = parseNumbered(next) {
                        items.append(item)
                        index += 1
                    } else {
                        break
                    }
                }
                segments.append(.numberedList(items))
                continue
            }

            var paragraphLines: [String] = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextStripped = next.trimmingCharacters(in: .whitespaces)
                if nextStripped.isEmpty
                    || parseHeading(nextStripped) != nil
                    || parseBullet(nextStripped) != nil
                    || parseNumbered(nextStripped) != nil {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            let paragraph = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                segments.append(.paragraph(paragraph))
            }
        }

        return segments
    }

    private static func parseHeading(_ line: String) -> ProseSegment? {
        if line.hasPrefix("### ") {
            return .heading(level: 3, text: String(line.dropFirst(4)))
        }
        if line.hasPrefix("## ") {
            return .heading(level: 2, text: String(line.dropFirst(3)))
        }
        if line.hasPrefix("# ") {
            return .heading(level: 1, text: String(line.dropFirst(2)))
        }
        return nil
    }

    private static func parseBullet(_ line: String) -> String? {
        let prefixes = ["- ", "* ", "• "]
        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func parseNumbered(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let numPart = line[..<dot]
        guard !numPart.isEmpty, numPart.allSatisfy(\.isNumber) else { return nil }
        let after = line.index(after: dot)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return String(line[line.index(after: after)...])
    }
}

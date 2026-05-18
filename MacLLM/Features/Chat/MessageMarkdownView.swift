import SwiftUI

enum MarkdownBlock {
    case text(String)
    case code(language: String?, content: String)
}

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

struct MessageMarkdownView: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownContentParser.blocks(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if blocks.isEmpty {
                Text(text)
                    .textSelection(.enabled)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let prose):
                        Text(attributedProse(prose))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .code(let language, let code):
                        VStack(alignment: .leading, spacing: 4) {
                            if let language, !language.isEmpty {
                                Text(language)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(code)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    private func attributedProse(_ prose: String) -> AttributedString {
        var attributed = AttributedString(prose)
        applyInlineCode(in: &attributed)
        applyBold(in: &attributed)
        return attributed
    }

    private func applyInlineCode(in attributed: inout AttributedString) {
        let pattern = #"`([^`]+)`"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let string = String(attributed.characters)
        let matches = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: string),
                  let innerRange = Range(match.range(at: 1), in: string) else { continue }
            let code = String(string[innerRange])
            var replacement = AttributedString(code)
            replacement.font = .system(.body, design: .monospaced)
            replacement.backgroundColor = Color.primary.opacity(0.08)
            if let attrRange = Range(range, in: attributed) {
                attributed.replaceSubrange(attrRange, with: replacement)
            }
        }
    }

    private func applyBold(in attributed: inout AttributedString) {
        let pattern = #"\*\*([^*]+)\*\*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let string = String(attributed.characters)
        let matches = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: string),
                  let innerRange = Range(match.range(at: 1), in: string) else { continue }
            var replacement = AttributedString(String(string[innerRange]))
            replacement.inlinePresentationIntent = .stronglyEmphasized
            if let attrRange = Range(range, in: attributed) {
                attributed.replaceSubrange(attrRange, with: replacement)
            }
        }
    }
}

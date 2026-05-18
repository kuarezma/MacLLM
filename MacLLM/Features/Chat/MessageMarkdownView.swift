import SwiftUI

struct MessageMarkdownView: View {
    let text: String
    var isStreaming: Bool = false

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

            if isStreaming {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Yanıt yazılıyor…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
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

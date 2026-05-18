import SwiftUI

struct ProseMarkdownView: View {
    let text: String

    private var segments: [ProseSegment] {
        let parsed = MarkdownContentParser.proseSegments(from: text)
        return parsed.isEmpty ? [.paragraph(text)] : parsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .paragraph(let prose):
                    Text(ProseMarkdownView.attributedInline(prose))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .heading(let level, let title):
                    Text(ProseMarkdownView.attributedInline(title))
                        .font(headingFont(level: level))
                        .fontWeight(.semibold)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, level == 1 ? 4 : 2)
                case .bulletList(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(ProseMarkdownView.attributedInline(item))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                case .numberedList(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 20, alignment: .trailing)
                                Text(ProseMarkdownView.attributedInline(item))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }

    static func attributedInline(_ prose: String) -> AttributedString {
        var attributed = AttributedString(prose)
        applyInlineCode(in: &attributed)
        applyBold(in: &attributed)
        return attributed
    }

    private static func applyInlineCode(in attributed: inout AttributedString) {
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

    private static func applyBold(in attributed: inout AttributedString) {
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

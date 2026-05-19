import SwiftUI

struct MessageMarkdownView: View {
    let text: String
    var isStreaming: Bool = false

    private var blocks: [MarkdownBlock] {
        MarkdownContentParser.blocks(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isStreaming {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if blocks.isEmpty {
                Text(text)
                    .textSelection(.enabled)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let prose):
                        ProseMarkdownView(text: prose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .code(let language, let code):
                        CodeBlockView(language: language, code: code)
                    }
                }
            }

            if isStreaming, text.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Yanıt yazılıyor…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 20, alignment: .leading)
                .padding(.top, 2)
            }
        }
    }
}

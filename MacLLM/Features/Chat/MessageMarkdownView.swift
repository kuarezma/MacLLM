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
                        ProseMarkdownView(text: prose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .code(let language, let code):
                        CodeBlockView(language: language, code: code)
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
}

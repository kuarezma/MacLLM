import SwiftUI

@MainActor
final class MessageMarkdownUIState: ObservableObject {
    @Published var cachedHash: Int = 0
    @Published var cachedBlocks: [MarkdownBlock] = []
}

struct MessageMarkdownView: View {
    let text: String
    var isStreaming: Bool = false
    @StateObject private var ui = MessageMarkdownUIState()

    private var blocks: [MarkdownBlock] {
        if isStreaming { return [] }
        let hash = text.hashValue
        if hash == ui.cachedHash, !ui.cachedBlocks.isEmpty {
            return ui.cachedBlocks
        }
        return MarkdownContentParser.blocks(from: text)
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
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
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
        .onChange(of: text) { _, newValue in
            guard !isStreaming else { return }
            ui.cachedHash = newValue.hashValue
            ui.cachedBlocks = MarkdownContentParser.blocks(from: newValue)
        }
        .onAppear {
            guard !isStreaming else { return }
            ui.cachedHash = text.hashValue
            ui.cachedBlocks = MarkdownContentParser.blocks(from: text)
        }
    }
}

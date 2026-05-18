import SwiftUI

/// Hub README — tam Markdown (kod blokları + prose).
struct ReadmeMarkdownView: View {
    let markdown: String
    var maxHeight: CGFloat = 420

    var body: some View {
        ScrollView {
            MessageMarkdownView(text: markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: maxHeight)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

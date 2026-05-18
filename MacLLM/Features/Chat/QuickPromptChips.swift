import SwiftUI

struct QuickPromptChips: View {
    let prompts: [(String, String)]
    var onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 148), spacing: 10)],
            spacing: 10
        ) {
            ForEach(prompts, id: \.0) { icon, text in
                Button {
                    onSelect(text)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        Text(text)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                }
                .buttonStyle(PromptChipButtonStyle())
            }
        }
        .frame(maxWidth: 540)
    }

    static let defaults: [(String, String)] = [
        ("hand.wave", "Merhaba! Kendini tanıt."),
        ("doc.text", "Bu metni özetle."),
        ("chevron.left.forwardslash.chevron.right", "Bu kodu açıkla."),
        ("lightbulb", "Bu konu hakkında 5 fikir ver."),
        ("globe", "Türkçe olarak yanıtla."),
        ("list.bullet", "Adım adım anlat."),
    ]
}

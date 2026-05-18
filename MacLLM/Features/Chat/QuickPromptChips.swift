import SwiftUI

struct QuickPromptChips: View {
    let prompts: [(String, String)]
    var onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
            spacing: 10
        ) {
            ForEach(prompts, id: \.0) { icon, text in
                Button {
                    onSelect(text)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 520)
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

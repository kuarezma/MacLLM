import SwiftUI

struct MessageRow: View {
    let message: ChatMessage

    private var displayContent: String {
        let raw = message.content.isEmpty ? "…" : message.content
        if message.role == .assistant {
            return ChatTemplateResolver.sanitizeDisplayedText(raw)
        }
        return raw
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.rowSpacing) {
            Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(message.role == .user ? Color.accentColor : .purple)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "Siz" : "Asistan")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(displayContent)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppTheme.rowSpacing)
        .background(
            message.role == .user
                ? AppTheme.userBubbleBackground()
                : AppTheme.assistantBubbleBackground()
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.bubbleRadius))
    }
}

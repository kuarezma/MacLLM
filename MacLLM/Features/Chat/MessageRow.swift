import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    var sessionId: UUID
    var showsTypingIndicator: Bool = false

    private var displayContent: String {
        if showsTypingIndicator { return "" }
        let raw = message.content
        if message.role == .assistant {
            return ControlTokenSanitizer.sanitizeForDisplay(raw)
        }
        return raw.isEmpty ? message.displayPreviewText : raw
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.rowSpacing) {
            Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(message.role == .user ? Color.accentColor : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "Siz" : "Asistan")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                if !message.attachments.isEmpty {
                    MessageAttachmentsView(attachments: message.attachments, sessionId: sessionId)
                }

                if showsTypingIndicator {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Yanıt yazılıyor…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if !displayContent.isEmpty {
                    if message.role == .assistant {
                        MessageMarkdownView(text: displayContent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(displayContent)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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

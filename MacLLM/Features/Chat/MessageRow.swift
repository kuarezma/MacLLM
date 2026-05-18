import SwiftUI
import AppKit

struct MessageRow: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var inferenceService: InferenceService

    let message: ChatMessage
    var sessionId: UUID
    var showsTypingIndicator: Bool = false
    var isStreaming: Bool = false
    var generationStats: GenerationStats?
    var reserveStatsSpace: Bool = false

    @State private var thoughtExpanded = false
    @State private var hovered = false
    @State private var isEditing = false
    @State private var editDraft = ""
    @FocusState private var editFocused: Bool

    private var isUser: Bool { message.role == .user }
    private var actionsDisabled: Bool { inferenceService.isGenerating }

    private var displayContent: String {
        if showsTypingIndicator { return "" }
        let raw = message.content
        if message.role == .assistant {
            return ControlTokenSanitizer.sanitizeForDisplay(raw)
        }
        return raw.isEmpty ? message.displayPreviewText : raw
    }

    private var contentSplit: ReasoningContentSplitter.Split {
        ReasoningContentSplitter.split(displayContent)
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                messageBody
                if !showsTypingIndicator, !isEditing {
                    messageActions
                }
                if message.role == .assistant, reserveStatsSpace || generationStats != nil {
                    Text(generationStats?.formattedSummary ?? " ")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .opacity(generationStats != nil ? 1 : 0)
                        .frame(height: AppTheme.messageStatsHeight, alignment: .leading)
                }
            }
            .frame(maxWidth: AppTheme.maxChatContentWidth, alignment: isUser ? .trailing : .leading)
            Spacer(minLength: 0)
        }
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var messageBody: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            if !message.attachments.isEmpty, !isEditing {
                MessageAttachmentsView(attachments: message.attachments, sessionId: sessionId)
            }

            if showsTypingIndicator {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Yanıt yazılıyor…")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if isUser, isEditing {
                editingView
            } else if isUser {
                Text(displayContent)
                    .textSelection(.enabled)
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(AppTheme.userBubbleBackground(), in: RoundedRectangle(cornerRadius: AppTheme.bubbleRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.bubbleRadius, style: .continuous)
                            .strokeBorder(AppTheme.accent.opacity(0.15), lineWidth: 0.5)
                    }
                    .appFloatingShadow(radius: 8, y: 3)
            } else {
                assistantContent
            }
        }
    }

    @ViewBuilder
    private var editingView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("Mesajınız", text: $editDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($editFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.composerBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.bubbleRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.bubbleRadius, style: .continuous)
                        .strokeBorder(AppTheme.accent.opacity(0.5), lineWidth: 1)
                )
                .onAppear {
                    editDraft = message.content
                    editFocused = true
                }

            HStack(spacing: 8) {
                Button("İptal") {
                    isEditing = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)

                Button("Kaydet") {
                    Task {
                        await appModel.editUserMessage(id: message.id, newText: editDraft)
                        isEditing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var isErrorReply: Bool {
        message.role == .assistant && displayContent.hasPrefix("Hata:")
    }

    private var errorDetail: String {
        displayContent.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var assistantContent: some View {
        if isErrorReply {
            ChatErrorBanner(title: "Yanıt üretilemedi", detail: errorDetail)
        } else {
            if let thought = contentSplit.thought, !thought.isEmpty {
                DisclosureGroup(isExpanded: $thoughtExpanded) {
                    Text(thought)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .font(.caption)
                        if let seconds = contentSplit.thoughtSeconds {
                            Text("Düşünüldü · \(seconds) sn")
                        } else {
                            Text("Düşünme")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
            }

            let answer = contentSplit.answer.isEmpty && contentSplit.thought != nil
                ? ""
                : (contentSplit.thought != nil ? contentSplit.answer : displayContent)

            if !answer.isEmpty {
                MessageMarkdownView(text: answer, isStreaming: isStreaming)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var messageActions: some View {
        HStack(spacing: 4) {
            actionButton("doc.on.doc", help: "Kopyala") { copyMessage() }
            if message.role == .user {
                actionButton("pencil", help: "Düzenle") {
                    editDraft = message.content
                    isEditing = true
                }
            }
            if message.role == .assistant {
                actionButton("arrow.clockwise", help: "Yeniden üret") {
                    Task { await appModel.regenerate(from: message.id) }
                }
            }
            actionButton("trash", help: "Sil") {
                Task { await appModel.deleteMessage(id: message.id) }
            }
        }
        .opacity(hovered ? 1 : 0.35)
        .disabled(actionsDisabled)
    }

    private func actionButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(actionsDisabled ? AppTheme.secondaryText.opacity(0.3) : AppTheme.secondaryText)
        .help(help)
    }

    private func copyMessage() {
        let text = displayContent
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

import Foundation

struct InferencePayload {
    var messages: [ChatMessage]
    var mediaPaths: [String]
}

enum InferenceMessageBuilder {
    /// mtmd varsayılan medya işaretçisi (`mtmd_default_marker`).
    static let mediaMarker = "<__media__>"

    static func build(
        messages: [ChatMessage],
        sessionId: UUID
    ) -> InferencePayload {
        var prepared = messages.map { expandDocumentText(in: $0) }
        var mediaPaths: [String] = []

        guard let userIndex = prepared.lastIndex(where: { $0.role == .user }) else {
            return InferencePayload(messages: prepared, mediaPaths: [])
        }

        let userMessage = prepared[userIndex]
        for attachment in userMessage.attachments {
            let path = AttachmentStore.shared.fileURL(sessionId: sessionId, attachment: attachment).path
            switch attachment.kind {
            case .image, .audio:
                mediaPaths.append(path)
            case .video, .document:
                break
            }
        }

        if !mediaPaths.isEmpty {
            var content = userMessage.content
            let existing = content.components(separatedBy: mediaMarker).count - 1
            let needed = max(0, mediaPaths.count - max(0, existing))
            if needed > 0 {
                let prefix = String(repeating: mediaMarker, count: needed)
                content = prefix + content
            }
            prepared[userIndex].content = content
        }

        return InferencePayload(messages: prepared, mediaPaths: mediaPaths)
    }

    /// Çıkarılan belge metnini yalnızca çıkarım isteğine ekler; sohbet geçmişi görünümü değişmez.
    private static func expandDocumentText(in message: ChatMessage) -> ChatMessage {
        guard message.role == .user else { return message }
        var content = message.content
        for attachment in message.attachments where attachment.kind == .document {
            guard let docText = attachment.extractedText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !docText.isEmpty else { continue }
            content += MediaContentProcessor.documentTextBlock(
                fileName: attachment.fileName,
                text: docText
            )
        }
        guard content != message.content else { return message }
        var expanded = message
        expanded.content = content
        return expanded
    }
}

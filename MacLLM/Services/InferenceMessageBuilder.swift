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
        var prepared = messages
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
}

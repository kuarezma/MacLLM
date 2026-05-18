import AppKit
import SwiftUI

struct MessageAttachmentsView: View {
    let attachments: [MessageAttachment]
    let sessionId: UUID

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(attachments) { attachment in
                    attachmentView(attachment)
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentView(_ attachment: MessageAttachment) -> some View {
        let url = AttachmentStore.shared.fileURL(sessionId: sessionId, attachment: attachment)
        switch attachment.kind {
        case .image:
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                attachmentLabel(attachment)
            }
        case .audio:
            HStack {
                Image(systemName: "waveform")
                Text(attachment.fileName)
                    .font(.caption)
            }
            .padding(8)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .video:
            attachmentLabel(attachment, icon: "film")
        case .document:
            attachmentLabel(attachment, icon: "doc.text")
        }
    }

    private func attachmentLabel(_ attachment: MessageAttachment, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon ?? attachment.kind.systemImage)
            Text(attachment.fileName)
                .font(.caption)
                .lineLimit(2)
        }
        .padding(8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct PendingAttachmentChip: View {
    let attachment: MessageAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.kind.systemImage)
            Text(attachment.fileName)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct ChatAttachmentImporter {
    static let contentTypes: [UTType] = [
        .image, .audio, .movie, .video, .pdf, .plainText, .json, .rtf,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "csv") ?? .plainText,
    ].compactMap { $0 }

    static let documentContentTypes: [UTType] = [
        .pdf, .plainText, .json, .rtf,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "csv") ?? .plainText,
    ].compactMap { $0 }

    static func contentTypes(for profile: LoadedModelProfile?) -> [UTType] {
        guard let profile else { return contentTypes }
        if profile.supportsVision && profile.hasMmproj && profile.runtimeMultimodal {
            return contentTypes
        }
        return documentContentTypes
    }

    static func kind(for url: URL) -> AttachmentKind? {
        if let type = UTType(filenameExtension: url.pathExtension),
           let kind = AttachmentStore.kind(for: type) {
            return kind
        }
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp"].contains(ext) { return .image }
        if ["wav", "mp3", "m4a", "flac", "aac", "ogg"].contains(ext) { return .audio }
        if ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext) { return .video }
        if ["pdf", "txt", "md", "csv", "json", "rtf", "log", "swift", "py", "js", "html", "xml"].contains(ext) {
            return .document
        }
        return nil
    }
}

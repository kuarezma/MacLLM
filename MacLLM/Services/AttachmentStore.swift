import Foundation
import UniformTypeIdentifiers

enum AttachmentStoreError: LocalizedError {
    case sessionDirectoryFailed
    case copyFailed
    case fileTooLarge
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .sessionDirectoryFailed: return "Ek dosya klasörü oluşturulamadı."
        case .copyFailed: return "Dosya kopyalanamadı."
        case .fileTooLarge: return "Dosya çok büyük (en fazla 80 MB)."
        case .unsupportedType: return "Desteklenmeyen dosya türü."
        }
    }
}

final class AttachmentStore: @unchecked Sendable {
    static let shared = AttachmentStore()
    static let maxFileBytes: Int64 = 80 * 1024 * 1024

    private let fileManager = FileManager.default

    func sessionDirectory(sessionId: UUID) throws -> URL {
        let root = ModelStore.shared.appSupportURL
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(sessionId.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func fileURL(sessionId: UUID, attachment: MessageAttachment) -> URL {
        let dir = (try? sessionDirectory(sessionId: sessionId))
            ?? ModelStore.shared.appSupportURL
                .appendingPathComponent("attachments/\(sessionId.uuidString)", isDirectory: true)
        return dir.appendingPathComponent(attachment.storageName)
    }

    func importFile(
        from source: URL,
        sessionId: UUID,
        kind: AttachmentKind
    ) throws -> MessageAttachment {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        let attrs = try fileManager.attributesOfItem(atPath: source.path)
        let size = (attrs[.size] as? Int64) ?? 0
        guard size <= Self.maxFileBytes else { throw AttachmentStoreError.fileTooLarge }

        let attachmentId = UUID()
        let ext = source.pathExtension.isEmpty ? defaultExtension(for: kind) : source.pathExtension
        let storageName = "\(attachmentId.uuidString.lowercased()).\(ext)"
        let dest = try sessionDirectory(sessionId: sessionId).appendingPathComponent(storageName)

        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: source, to: dest)

        return MessageAttachment(
            id: attachmentId,
            kind: kind,
            fileName: source.lastPathComponent,
            storageName: storageName,
            byteSize: size
        )
    }

    func writeData(
        _ data: Data,
        sessionId: UUID,
        fileName: String,
        kind: AttachmentKind
    ) throws -> MessageAttachment {
        guard Int64(data.count) <= Self.maxFileBytes else { throw AttachmentStoreError.fileTooLarge }
        let attachmentId = UUID()
        let ext = (fileName as NSString).pathExtension.isEmpty
            ? defaultExtension(for: kind)
            : (fileName as NSString).pathExtension
        let storageName = "\(attachmentId.uuidString.lowercased()).\(ext)"
        let dest = try sessionDirectory(sessionId: sessionId).appendingPathComponent(storageName)
        try data.write(to: dest, options: .atomic)
        return MessageAttachment(
            id: attachmentId,
            kind: kind,
            fileName: fileName,
            storageName: storageName,
            byteSize: Int64(data.count)
        )
    }

    func deleteSessionAttachments(sessionId: UUID) {
        let dir = ModelStore.shared.appSupportURL
            .appendingPathComponent("attachments/\(sessionId.uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: dir)
    }

    private func defaultExtension(for kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "png"
        case .audio: return "wav"
        case .video: return "mp4"
        case .document: return "txt"
        }
    }

    static func kind(for contentType: UTType) -> AttachmentKind? {
        if contentType.conforms(to: .image) { return .image }
        if contentType.conforms(to: .audio) { return .audio }
        if contentType.conforms(to: .movie) || contentType.conforms(to: .video) { return .video }
        if contentType.conforms(to: .pdf)
            || contentType.conforms(to: .plainText)
            || contentType.conforms(to: .rtf)
            || contentType.conforms(to: .json)
            || contentType.conforms(to: .commaSeparatedText) {
            return .document
        }
        if contentType.identifier == "org.openxmlformats.wordprocessingml.document"
            || contentType.identifier == "com.microsoft.word.doc" {
            return .document
        }
        return nil
    }
}

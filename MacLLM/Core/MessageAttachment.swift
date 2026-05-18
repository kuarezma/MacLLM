import Foundation

enum AttachmentKind: String, Codable, CaseIterable {
    case image
    case audio
    case video
    case document

    var label: String {
        switch self {
        case .image: return "Görüntü"
        case .audio: return "Ses"
        case .video: return "Video"
        case .document: return "Belge"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .document: return "doc.text"
        }
    }
}

struct MessageAttachment: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: AttachmentKind
    var fileName: String
    /// Oturum klasörüne göre göreli yol (ör. `a1b2-photo.png`).
    var storageName: String
    var byteSize: Int64
    /// Belgeler için çıkarılan metin; gönderimde `content` içine de yazılır.
    var extractedText: String?

    var isVisual: Bool { kind == .image || kind == .video }

    init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        fileName: String,
        storageName: String,
        byteSize: Int64 = 0,
        extractedText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.storageName = storageName
        self.byteSize = byteSize
        self.extractedText = extractedText
    }
}

extension ChatMessage {
    var hasMediaAttachments: Bool {
        attachments.contains { $0.kind == .image || $0.kind == .audio || $0.kind == .video }
    }

    var displayPreviewText: String {
        let base = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty { return base }
        if attachments.isEmpty { return "" }
        let names = attachments.map(\.fileName).joined(separator: ", ")
        return "📎 \(names)"
    }
}

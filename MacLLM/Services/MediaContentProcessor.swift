import AVFoundation
import AppKit
import Foundation
import PDFKit

enum MediaProcessingError: LocalizedError {
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let detail): return detail
        }
    }
}

/// Belgelerden metin çıkarır; videodan kare üretir.
enum MediaContentProcessor {
    private static let maxDocumentChars = 24_000
    private static let videoFrameCount = 3

    static func enrich(
        _ attachment: inout MessageAttachment,
        sessionId: UUID
    ) async throws {
        let url = AttachmentStore.shared.fileURL(sessionId: sessionId, attachment: attachment)
        switch attachment.kind {
        case .document:
            attachment.extractedText = try extractDocumentText(from: url, fileName: attachment.fileName)
        case .video:
            let frames = try await extractVideoFrames(from: url, sessionId: sessionId, baseName: attachment.fileName)
            attachment.extractedText = frames.isEmpty
                ? nil
                : "[Video: \(attachment.fileName) — \(frames.count) kare görüntü eklendi]"
        case .image, .audio:
            break
        }
    }

    /// Video karelerini ayrı görüntü ekleri olarak döndürür.
    static func videoFrameAttachments(
        source: MessageAttachment,
        sessionId: UUID
    ) async throws -> [MessageAttachment] {
        guard source.kind == .video else { return [] }
        let url = AttachmentStore.shared.fileURL(sessionId: sessionId, attachment: source)
        return try await extractVideoFrames(from: url, sessionId: sessionId, baseName: source.fileName)
    }

    static func documentTextBlock(fileName: String, text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let capped = String(trimmed.prefix(maxDocumentChars))
        return "\n\n[Belge: \(fileName)]\n\(capped)"
    }

    // MARK: - Document

    private static func extractDocumentText(from url: URL, fileName: String) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else {
                throw MediaProcessingError.extractionFailed("PDF okunamadı.")
            }
            let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MediaProcessingError.extractionFailed("PDF içinde metin bulunamadı.")
            }
            return String(text.prefix(maxDocumentChars))
        }

        let textExtensions = ["txt", "md", "markdown", "json", "csv", "log", "swift", "py", "js", "ts", "html", "xml", "yaml", "yml"]
        if textExtensions.contains(ext) {
            let raw = try String(contentsOf: url, encoding: .utf8)
            if raw.isEmpty { throw MediaProcessingError.extractionFailed("Dosya boş.") }
            return String(raw.prefix(maxDocumentChars))
        }

        if ext == "rtf" {
            let data = try Data(contentsOf: url)
            let attributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            let text = attributed.string
            guard !text.isEmpty else { throw MediaProcessingError.extractionFailed("RTF boş.") }
            return String(text.prefix(maxDocumentChars))
        }

        throw MediaProcessingError.extractionFailed("Bu belge türü için metin çıkarma henüz desteklenmiyor (\(fileName)).")
    }

    // MARK: - Video frames

    private static func videoDurationSeconds(asset: AVURLAsset) async throws -> Double {
        let time = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0.1 else {
            throw MediaProcessingError.extractionFailed("Video süresi okunamadı.")
        }
        return seconds
    }

    private static func extractVideoFrames(
        from url: URL,
        sessionId: UUID,
        baseName: String
    ) async throws -> [MessageAttachment] {
        let asset = AVURLAsset(url: url)
        let duration = try await videoDurationSeconds(asset: asset)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)

        let count = min(videoFrameCount, max(1, Int(duration)))
        var attachments: [MessageAttachment] = []
        let stem = (baseName as NSString).deletingPathExtension

        for index in 0..<count {
            let t = duration * (Double(index) + 0.5) / Double(count)
            let time = CMTime(seconds: t, preferredTimescale: 600)
            let cgImage: CGImage
            do {
                cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            } catch {
                continue
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            var frame = try AttachmentStore.shared.writeData(
                png,
                sessionId: sessionId,
                fileName: "\(stem)-kare\(index + 1).png",
                kind: .image
            )
            frame.extractedText = "[Video karesi \(index + 1)/\(count) — \(baseName)]"
            attachments.append(frame)
        }

        if attachments.isEmpty {
            throw MediaProcessingError.extractionFailed("Videodan kare çıkarılamadı.")
        }
        return attachments
    }
}

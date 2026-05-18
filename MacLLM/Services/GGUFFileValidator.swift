import Foundation

enum GGUFFileValidator {
    private static let magic = Data("GGUF".utf8)
    private static let minimumBytes: Int64 = 1_000_000

    static func isValidGGUF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4), header == magic else { return false }
        return true
    }

    static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    /// Mevcut dosya indirmeye uygunsa true.
    static func existingFileIsUsable(at url: URL, expectedBytes: Int64) -> Bool {
        let size = fileSize(at: url)
        guard size >= minimumBytes, isValidGGUF(at: url) else { return false }
        if expectedBytes > 10_000_000 {
            let ratio = Double(size) / Double(expectedBytes)
            if ratio < 0.90 { return false }
        }
        return true
    }

    static func validateDownload(at url: URL, expectedBytes: Int64) throws {
        let size = fileSize(at: url)
        if size < minimumBytes {
            try? FileManager.default.removeItem(at: url)
            throw validationError(
                "Dosya çok küçük (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))). "
                    + "İndirme başarısız olabilir veya gated model için Ayarlar → Hugging Face token gerekir."
            )
        }
        if !isValidGGUF(at: url) {
            try? FileManager.default.removeItem(at: url)
            throw validationError(
                "Geçerli bir GGUF dosyası değil. Hugging Face erişimini veya token’ı kontrol edin."
            )
        }
        if expectedBytes > 10_000_000 {
            let ratio = Double(size) / Double(expectedBytes)
            if ratio < 0.90 {
                try? FileManager.default.removeItem(at: url)
                throw validationError(
                    "İndirilen dosya beklenen boyuttan küçük. Bağlantıyı kontrol edip tekrar indirin."
                )
            }
        }
    }

    private static func validationError(_ message: String) -> NSError {
        NSError(domain: "MacLLM", code: 102, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

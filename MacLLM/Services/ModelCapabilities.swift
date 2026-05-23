import Foundation

struct ModelCapabilities: Equatable {
    var supportsVision: Bool
    var supportsAudio: Bool
    var requiresMmproj: Bool

    static let textOnly = ModelCapabilities(supportsVision: false, supportsAudio: false, requiresMmproj: false)

    static func detect(model: InstalledModel) -> ModelCapabilities {
        let haystack = "\(model.name) \(model.filename) \(model.repoId)".lowercased()
        let visionKeywords = [
            "vl", "vision", "llava", "bakllava", "moondream", "pixtral", "gemma-3", "gemma3",
            "qwen2-vl", "qwen2vl", "qwen3-vl", "qwen3vl", "qwen-vl", "minicpm-v", "minicpmv", "internvl",
            "cogvlm", "llama-3.2-vision", "llama3.2-vision", "granite-vision", "smolvlm",
        ]
        let audioKeywords = ["audio", "whisper", "speech", "ultravox", "granite-speech"]

        let likelyVision = visionKeywords.contains { haystack.contains($0) }
        let likelyAudio = audioKeywords.contains { haystack.contains($0) }
        let hasMmproj = model.mmprojLocalPath.map { FileManager.default.fileExists(atPath: $0) } ?? false

        return ModelCapabilities(
            supportsVision: likelyVision || hasMmproj,
            supportsAudio: likelyAudio,
            requiresMmproj: likelyVision || likelyAudio
        )
    }

    /// Composer / gönderim öncesi görüntü-ses uyarı metni.
    static func attachmentWarning(
        model: InstalledModel?,
        attachments: [MessageAttachment]
    ) -> String? {
        guard let model else {
            return attachments.contains(where: { $0.kind == .image || $0.kind == .video || $0.kind == .audio })
                ? "Görüntü göndermek için önce bir model seçin."
                : nil
        }
        let caps = detect(model: model)
        let hasImage = attachments.contains { $0.kind == .image || $0.kind == .video }
        let hasAudio = attachments.contains { $0.kind == .audio }

        if hasImage, !caps.supportsVision {
            return "«\(model.name)» görüntü desteklemiyor. Model Hub → Qwen2-VL, LLaVA veya Moondream indirin."
        }
        if hasAudio, !caps.supportsAudio {
            return "«\(model.name)» ses desteklemiyor. Sesli çok modlu model gerekir."
        }
        if caps.requiresMmproj, model.mmprojLocalPath == nil, hasImage || hasAudio {
            return "Görüntü için mmproj GGUF gerekli. Hub'dan indirirken otomatik gelir; elle eklediyseniz modeli yeniden yükleyin."
        }
        return nil
    }

    /// Base / completion modeller için sohbet uyumluluk uyarısı.
    static func chatCompatibilityWarning(model: InstalledModel?) -> String? {
        guard let model else { return nil }
        let haystack = "\(model.name) \(model.filename) \(model.repoId)".lowercased()
        if haystack.contains("phi-2") || haystack.contains("phi2") {
            if !haystack.contains("instruct") {
                return "phi-2 base model sohbet için eğitilmemiş. Phi-3-mini-instruct veya Qwen2.5-Instruct deneyin."
            }
        }
        return nil
    }

    func canUse(attachment: MessageAttachment) -> Bool {
        switch attachment.kind {
        case .image, .video:
            return supportsVision
        case .audio:
            return supportsAudio
        case .document:
            return true
        }
    }
}

enum MmprojDiscovery {
    /// Aynı klasörde `*mmproj*.gguf` arar.
    static func findSibling(to modelURL: URL) -> URL? {
        let dir = modelURL.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        return files
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .filter { $0.lastPathComponent.lowercased().contains("mmproj") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    static func findInRepo(files: [HFGGUFile]) -> HFGGUFile? {
        files.first { $0.isMmproj }
    }
}

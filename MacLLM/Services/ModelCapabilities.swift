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
            "qwen2-vl", "qwen2vl", "qwen3-vl", "qwen3vl", "minicpm-v", "minicpmv", "internvl",
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
}

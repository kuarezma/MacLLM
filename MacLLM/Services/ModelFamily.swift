import Foundation

/// Model ailesine göre çıkarım zamanı ayarları.
enum ModelFamily {
    static func haystack(for model: InstalledModel?) -> String {
        guard let model else { return "" }
        return "\(model.name) \(model.filename) \(model.repoId)".lowercased()
    }

    static func isQwopusFamily(_ model: InstalledModel?) -> Bool {
        let haystack = haystack(for: model)
        return haystack.contains("qwopus")
            || haystack.contains("qwen3.5")
            || haystack.contains("qwen3-")
            || haystack.contains("qwen3.")
    }

    /// Qwopus / Qwen3.5: KV önbellek yeniden kullanımı güvenilir değil.
    static func prefersConservativeKVCache(for model: InstalledModel?) -> Bool {
        isQwopusFamily(model)
    }

    /// Yükleme ve üretim öncesi Flash Attention kapalı olmalı.
    static func prefersQwopusTuning(_ model: InstalledModel?) -> Bool {
        isQwopusFamily(model)
    }
}

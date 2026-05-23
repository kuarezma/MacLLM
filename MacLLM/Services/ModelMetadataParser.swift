import Foundation

enum ModelMetadataParser {
    static func parseQuant(from filename: String) -> String? {
        let lower = filename.lowercased()
        let patterns = [
            "q8_0", "q6_k", "q5_k_m", "q5_k_s", "q5_0",
            "q4_k_m", "q4_k_s", "q4_0", "q3_k_m", "q3_k_l", "q3_k_s", "q2_k",
        ]
        for pattern in patterns {
            if lower.contains(pattern) {
                return pattern.uppercased().replacingOccurrences(of: "_", with: "_")
            }
        }
        if let range = lower.range(of: #"q\d+[_a-z]*"#, options: .regularExpression) {
            return String(lower[range]).uppercased()
        }
        return nil
    }

    static func parseParameterSize(from text: String) -> String? {
        let lower = text.lowercased()
        if let match = lower.range(of: #"\d+(\.\d+)?\s*b(?![a-z])"#, options: .regularExpression) {
            let raw = String(lower[match]).replacingOccurrences(of: " ", with: "")
            return raw.uppercased()
        }
        return nil
    }

    /// Örn. "7B" → "7 milyar param."
    static func parameterSizeDisplay(from text: String) -> String? {
        guard let raw = parseParameterSize(from: text) else { return nil }
        let numPart = String(raw.dropLast()).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(numPart) else { return raw }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value)) milyar param."
        }
        return String(format: "%.1f milyar param.", value)
    }

    /// Kompakt rozet: "7B", "3.5B"
    static func parameterSizeBadge(from text: String) -> String? {
        parseParameterSize(from: text)
    }

    static func displayTags(_ tags: [String], limit: Int = 4) -> [String] {
        let skip = Set(["gguf", "transformers", "pytorch", "safetensors", "endpoints_compatible", "region:us"])
        return tags
            .filter { !skip.contains($0.lowercased()) && !$0.hasPrefix("license:") }
            .prefix(limit)
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            .map { $0 }
    }

    static func relativeDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    static func formatFileSize(bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    static func repoDisplayName(_ repoId: String) -> String {
        repoId.split(separator: "/").last.map(String.init) ?? repoId
    }

    static func repoAuthor(_ repoId: String) -> String? {
        let parts = repoId.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return String(parts[0])
    }

    static func parseArchitecture(from text: String) -> String? {
        let lower = text.lowercased()
        let patterns = [
            "phi-4", "phi-3", "phi4", "phi3",
            "llama-3.2", "llama-3.1", "llama-3", "llama3",
            "mistral", "mixtral", "qwen2.5", "qwen2", "qwen3", "qwen",
            "gemma-2", "gemma2", "gemma-3", "gemma3", "gemma",
            "deepseek", "granite", "falcon", "mpt", "gpt-oss",
        ]
        for pattern in patterns {
            if lower.contains(pattern) { return pattern }
        }
        return nil
    }

    static func capabilityTags(from tags: [String]) -> [String] {
        let lower = tags.map { $0.lowercased() }
        var caps: [String] = []
        if lower.contains(where: { $0.contains("tool") || $0.contains("function") }) {
            caps.append("Araç kullanımı")
        }
        if lower.contains(where: { $0.contains("reason") || $0.contains("thinking") }) {
            caps.append("Akıl yürütme")
        }
        if lower.contains(where: { $0.contains("vision") || $0.contains("vl") || $0.contains("multimodal") }) {
            caps.append("Görüntü")
        }
        if lower.contains("conversational") || lower.contains("chat") {
            caps.append("Sohbet")
        }
        return caps
    }
}

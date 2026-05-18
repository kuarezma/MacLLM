import Foundation
import llama

/// llama.cpp `llama_chat_apply_template` için şablon adı / GGUF jinja çözümlemesi.
enum ChatTemplateResolver {
    /// Bilinen kısa adları llama.cpp built-in şablon adlarına çevirir.
    static func resolveBuiltin(_ name: String) -> String {
        switch name.lowercased() {
        case "mistral", "mistral-instruct", "mistral-v0.3":
            return "mistral-v3"
        case "mistral-v1", "mistral-v3", "mistral-v3-tekken", "mistral-v7":
            return name.lowercased()
        case "llama3", "llama-3", "llama-3.1", "llama-3.2":
            return "llama3"
        case "llama2", "llama-2":
            return "llama2"
        case "phi3", "phi-3":
            return "phi3"
        case "gemma", "gemma2":
            return "gemma"
        case "chatml", "qwen", "qwen2", "qwen2.5":
            return "chatml"
        default:
            return name.isEmpty ? "chatml" : name
        }
    }

    /// GGUF metadata jinja (tercih) veya katalog ipucu.
    static func templateForModel(_ model: OpaquePointer?, hint: String) -> String {
        if let model,
           let cTemplate = llama_model_chat_template(model, nil),
           cTemplate.pointee != 0 {
            let jinja = String(cString: cTemplate)
            if !jinja.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return jinja
            }
        }
        return resolveBuiltin(hint)
    }

    /// Kayıtlı modellerdeki eski hatalı şablon adlarını onarır.
    static func repairStoredTemplate(_ template: String, repoId: String, filename: String) -> String {
        if template.lowercased() == "mistral" {
            let haystack = "\(repoId) \(filename)".lowercased()
            if haystack.contains("v0.3") || haystack.contains("instruct-v0.3") {
                return "mistral-v3"
            }
            return "mistral-v1"
        }
        return resolveBuiltin(template)
    }

    /// Modele göre ek stop dizileri (üretimin şablona taşmasını keser).
    static func recommendedStopSequences(for template: String) -> [String] {
        let lower = template.lowercased()
        if lower.contains("mistral") || lower.contains("[inst]") {
            return ["</s>", "[INST]", "[/INST]"]
        }
        if lower.contains("llama-3") || lower.contains("llama3") || lower.contains("eot_id") {
            return ["</s>", "<|eot_id|>", "<|start_header_id|>"]
        }
        if lower.contains("phi") {
            return ["</s>", "<|end|>"]
        }
        return ["</s>"]
    }

    static func mergedStopSequences(settings: InferenceSettings, template: String) -> [String] {
        var stops = settings.stopSequences
        for extra in recommendedStopSequences(for: template) where !stops.contains(extra) {
            stops.append(extra)
        }
        return stops.filter { !$0.isEmpty }
    }
}

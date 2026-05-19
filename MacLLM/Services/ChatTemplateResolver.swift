import Foundation
import llama

/// llama.cpp `llama_chat_apply_template` yalnızca built-in şablon adlarını kabul eder (Jinja değil).
enum ChatTemplateResolver {
    private static let chatmlEnd = "<|" + "im_end" + "|>"
    private static let chatmlStart = "<|" + "im_start" + "|>"
    /// llama.cpp builtin chatml (Qwopus / Qwen3.5) mesaj kapanışı
    private static let chatmlRedactedEnd = "<|" + "redacted_im_end" + "|>"

    static var defaultChatMLStopSequences: [String] {
        ["</s>", chatmlRedactedEnd, chatmlEnd, chatmlStart]
    }

    /// Bilinen kısa adları llama.cpp built-in şablon adlarına çevirir.
    static func resolveBuiltin(_ name: String) -> String {
        if isJinjaTemplate(name) {
            return builtinName(fromJinja: name, fallback: "chatml")
        }
        switch name.lowercased() {
        case "mistral", "mistral-instruct", "mistral-v0.3":
            return "mistral-v3"
        case "mistral-v1", "mistral-v3", "mistral-v3-tekken", "mistral-v7", "mistral-v7-tekken":
            return name.lowercased()
        case "llama3", "llama-3", "llama-3.1", "llama-3.2":
            return "llama3"
        case "llama2", "llama-2":
            return "llama2"
        case "phi3", "phi-3":
            return "phi3"
        case "phi2", "phi-2":
            return "phi2"
        case "gemma", "gemma2":
            return "gemma"
        case "chatml", "qwen", "qwen2", "qwen2.5":
            return "chatml"
        default:
            return name.isEmpty ? "chatml" : name
        }
    }

    /// Model yüklendiğinde kullanılacak built-in şablon adı (GGUF jinja → ad eşlemesi).
    static func templateForModel(_ model: OpaquePointer?, hint: String) -> String {
        let resolvedHint = resolveBuiltin(hint)
        guard let model,
              let cTemplate = llama_model_chat_template(model, nil),
              cTemplate.pointee != 0 else {
            return resolvedHint
        }
        let jinja = String(cString: cTemplate)
        guard !jinja.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return resolvedHint
        }
        return builtinName(fromJinja: jinja, fallback: resolvedHint)
    }

    /// Kayıtlı modellerdeki eski hatalı şablon adlarını onarır.
    static func repairStoredTemplate(_ template: String, repoId: String, filename: String) -> String {
        if isJinjaTemplate(template) {
            return builtinName(fromJinja: template, fallback: resolveBuiltin(guessFromRepo(repoId: repoId, filename: filename)))
        }
        if template.lowercased() == "mistral" {
            let haystack = "\(repoId) \(filename)".lowercased()
            if haystack.contains("v0.3") || haystack.contains("instruct-v0.3") {
                return "mistral-v3"
            }
            return "mistral-v1"
        }
        let haystack = "\(repoId) \(filename)".lowercased()
        if haystack.contains("phi-2") || haystack.contains("phi2") {
            let lower = template.lowercased()
            if lower == "phi3" || lower == "chatml" || isJinjaTemplate(template) {
                return "phi2"
            }
        }
        return resolveBuiltin(template)
    }

    /// Modele göre ek stop dizileri.
    static func recommendedStopSequences(for template: String) -> [String] {
        let lower = resolveBuiltin(template).lowercased()
        if lower.hasPrefix("mistral") {
            return ["</s>"]
        }
        if lower.contains("llama3") {
            return ["</s>", "<|eot_id|>", "<|start_header_id|>"]
        }
        if lower.contains("phi3") || lower.contains("phi-3") {
            return ["</s>", "<|end|>"]
        }
        if lower.contains("phi2") || lower.contains("phi-2") {
            return ["<|endoftext|>", "\nInstruct:"]
        }
        if lower.contains("phi") {
            return ["</s>", "<|end|>"]
        }
        if lower == "chatml" || lower.contains("qwen") || lower.contains("qwopus") {
            return defaultChatMLStopSequences
        }
        return ["</s>"]
    }

    /// Arayüzde gösterilecek metinden kontrol token sızıntısını temizler.
    static func sanitizeDisplayedText(_ text: String) -> String {
        ControlTokenSanitizer.sanitizeForDisplay(text)
    }

    static func mergedStopSequences(settings: InferenceSettings, template: String) -> [String] {
        var stops = settings.stopSequences
        for extra in recommendedStopSequences(for: template) where !stops.contains(extra) {
            stops.append(extra)
        }
        return stops
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Private

    private static func isJinjaTemplate(_ value: String) -> Bool {
        value.contains("{%") || value.contains("{{") || value.contains("for message in messages")
    }

    private static func guessFromRepo(repoId: String, filename: String) -> String {
        let haystack = "\(repoId) \(filename)".lowercased()
        if haystack.contains("mistral") || haystack.contains("mixtral") {
            if haystack.contains("v0.3") || haystack.contains("instruct-v0.3") { return "mistral-v3" }
            return "mistral-v1"
        }
        if haystack.contains("llama-3") || haystack.contains("llama3") { return "llama3" }
        if haystack.contains("phi-2") || haystack.contains("phi2") { return "phi2" }
        if haystack.contains("phi-3") || haystack.contains("phi3") { return "phi3" }
        if haystack.contains("gemma") { return "gemma" }
        if haystack.contains("qwen") { return "chatml" }
        if haystack.contains("qwopus") || haystack.contains("opus") || haystack.contains("coder") { return "chatml" }
        return "chatml"
    }

    /// GGUF Jinja metnini llama.cpp built-in adına çevirir (llama-chat.cpp ile uyumlu).
    static func builtinName(fromJinja jinja: String, fallback: String) -> String {
        let trimmed = jinja.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isJinjaTemplate(trimmed), isKnownBuiltin(trimmed) {
            return resolveBuiltin(trimmed)
        }

        let contains: (String) -> Bool = { jinja.contains($0) }

        if contains("<|im_start|>") || contains(chatmlRedactedEnd) {
            if contains("<|im_sep|>") { return "phi4" }
            if contains("<end_of_utterance>") { return "smolvlm" }
            return "chatml"
        }

        if jinja.lowercased().hasPrefix("mistral") || contains("[INST]") {
            if contains("[SYSTEM_PROMPT]") { return "mistral-v7" }
            if contains("' [INST] ' + system_message") || contains("[AVAILABLE_TOOLS]") {
                if contains(" [INST]") { return "mistral-v1" }
                if contains("\"[INST]\"") { return "mistral-v3-tekken" }
                return "mistral-v3"
            }
            // Mistral 7B Instruct v0.3 resmi HF şablonu
            if contains("'[INST] ' + message['content']")
                || contains("'[INST] ' + message[\"content\"]")
                || contains("'[INST] ' + message['content'] + ' [/INST]'") {
                return "mistral-v3"
            }
            if contains("<<SYS>>") { return "llama2-sys" }
            if contains("bos_token + '[INST]") { return "llama2-sys-bos" }
            if contains("content.strip()") { return "llama2-sys-strip" }
            return "llama2"
        }

        if contains("<|assistant|>") && contains("<|end|>") { return "phi3" }
        if contains("<|start|>") || contains("<start_of_turn>") { return "gemma" }
        if contains("<|start_header_id|>") && contains("<|end_header_id|>") { return "llama3" }

        return resolveBuiltin(fallback)
    }

    /// phi-2 instruct format — llama.cpp built-in yok; Swift'te üretilir.
    static func applyPhi2Template(messages: [ChatMessage], addGenerationPrompt: Bool) -> String {
        var output = ""
        var systemText: String?

        for message in messages {
            switch message.role {
            case .system:
                systemText = message.content
            case .user:
                var instruct = message.content
                if let system = systemText {
                    instruct = "\(system)\n\n\(instruct)"
                    systemText = nil
                }
                output += "Instruct: \(instruct)\nOutput: "
            case .assistant:
                output += "\(message.content)\n"
            }
        }

        if addGenerationPrompt, messages.last?.role != .user {
            output += "Instruct: \nOutput: "
        }
        return output
    }

    private static func isKnownBuiltin(_ name: String) -> Bool {
        let known: Set<String> = [
            "chatml", "llama2", "llama2-sys", "llama2-sys-bos", "llama2-sys-strip",
            "mistral-v1", "mistral-v3", "mistral-v3-tekken", "mistral-v7", "mistral-v7-tekken",
            "llama3", "llama4", "phi3", "phi2", "phi4", "gemma", "gemma2", "zephyr", "vicuna",
        ]
        return known.contains(name.lowercased())
    }
}

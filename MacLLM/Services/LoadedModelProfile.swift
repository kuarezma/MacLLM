import Foundation

enum ModelModality: String, Equatable {
    case textOnly
    case vision
    case audio
    case multimodal

    var label: String {
        switch self {
        case .textOnly: return "Metin"
        case .vision: return "Vision"
        case .audio: return "Ses"
        case .multimodal: return "Çok modlu"
        }
    }
}

enum ComposerHintKind: Equatable {
    case warning
    case info
}

struct ComposerHint: Equatable, Identifiable {
    var id: String { message }
    var kind: ComposerHintKind
    var message: String
    var icon: String
    var actionTitle: String?
}

struct LoadedModelProfile: Equatable {
    var modelId: String
    var displayName: String
    var resolvedChatTemplate: String
    var modality: ModelModality
    var supportsVision: Bool
    var supportsAudio: Bool
    var hasMmproj: Bool
    var runtimeMultimodal: Bool
    var isChatInstruct: Bool
    var nCtxTrain: Int?
    var parameterCount: UInt64?
    var modelDescription: String
    var recommendedMaxContext: UInt32
    var recommendedStopSequences: [String]
    var composerHints: [ComposerHint]
    var userContextExceedsTraining: Bool

    var parameterLabel: String? {
        guard let parameterCount, parameterCount > 0 else { return nil }
        let billions = Double(parameterCount) / 1e9
        if billions >= 1 {
            return String(format: "%.1fB", billions)
        }
        let millions = Double(parameterCount) / 1e6
        return String(format: "%.0fM", millions)
    }

    func allowsAttachment(_ kind: AttachmentKind) -> Bool {
        switch kind {
        case .image, .video:
            return supportsVision && hasMmproj && runtimeMultimodal
        case .audio:
            return supportsAudio && hasMmproj && runtimeMultimodal
        case .document:
            return true
        }
    }

    func attachmentWarning(for attachments: [MessageAttachment]) -> String? {
        let hasImage = attachments.contains { $0.kind == .image || $0.kind == .video }
        let hasAudio = attachments.contains { $0.kind == .audio }

        if hasImage, !supportsVision {
            return "«\(displayName)» görüntü desteklemiyor. Model Hub → Qwen2-VL, LLaVA veya Moondream deneyin."
        }
        if hasAudio, !supportsAudio {
            return "«\(displayName)» ses desteklemiyor. Sesli çok modlu model gerekir."
        }
        if (hasImage || hasAudio), supportsVision || supportsAudio, !hasMmproj {
            return "Vision için mmproj GGUF gerekli. Hub'dan indirirken otomatik gelir; elle eklediyseniz modeli yeniden yükleyin."
        }
        if (hasImage || hasAudio), hasMmproj, !runtimeMultimodal {
            return "mmproj yüklü ancak vision motoru hazır değil. Modeli yeniden yükleyin."
        }
        return nil
    }

    func primaryComposerHint(pendingAttachments: [MessageAttachment]) -> ComposerHint? {
        if let attachmentWarning = attachmentWarning(for: pendingAttachments) {
            return ComposerHint(
                kind: .warning,
                message: attachmentWarning,
                icon: "eye.slash",
                actionTitle: "Hub"
            )
        }
        return composerHints.first
    }

    var contextExceedsTraining: Bool {
        userContextExceedsTraining
    }
}

enum ModelProfileBuilder {
    static func build(
        model: InstalledModel,
        resolvedTemplate: String,
        runtimeVision: Bool,
        runtimeAudio: Bool,
        nCtxTrain: Int,
        parameterCount: UInt64,
        description: String,
        userContextLength: UInt32,
        systemProfile: MacSystemProfile,
        settings: InferenceSettings
    ) -> LoadedModelProfile {
        let heuristic = ModelCapabilities.detect(model: model)
        let hasMmproj = model.mmprojLocalPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        let runtimeMultimodal = runtimeVision || runtimeAudio

        let supportsVision = runtimeVision || (heuristic.supportsVision && hasMmproj)
        let supportsAudio = runtimeAudio || heuristic.supportsAudio

        let modality: ModelModality = {
            if supportsVision && supportsAudio { return .multimodal }
            if supportsVision { return .vision }
            if supportsAudio { return .audio }
            return .textOnly
        }()

        let isChatInstruct = detectChatInstruct(model: model)
        let recommendedMaxContext = recommendedContextCap(
            userContextLength: userContextLength,
            nCtxTrain: nCtxTrain,
            systemProfile: systemProfile
        )

        let stops = ChatTemplateResolver.mergedStopSequences(
            settings: settings,
            template: resolvedTemplate
        )

        var hints: [ComposerHint] = []
        if !isChatInstruct, let message = ModelCapabilities.chatCompatibilityWarning(model: model) {
            hints.append(ComposerHint(
                kind: .warning,
                message: message,
                icon: "exclamationmark.triangle",
                actionTitle: "Hub"
            ))
        }
        if supportsVision, !hasMmproj {
            hints.append(ComposerHint(
                kind: .warning,
                message: "Vision model — mmproj GGUF gerekli. Hub üzerinden indirirken otomatik gelir.",
                icon: "eye.slash",
                actionTitle: "Hub"
            ))
        } else if supportsVision, hasMmproj, runtimeMultimodal {
            hints.append(ComposerHint(
                kind: .info,
                message: "Vision hazır — görüntü ve taranmış PDF gönderebilirsiniz.",
                icon: "eye",
                actionTitle: nil
            ))
        }

        return LoadedModelProfile(
            modelId: model.id,
            displayName: model.name,
            resolvedChatTemplate: resolvedTemplate,
            modality: modality,
            supportsVision: supportsVision,
            supportsAudio: supportsAudio,
            hasMmproj: hasMmproj,
            runtimeMultimodal: runtimeMultimodal,
            isChatInstruct: isChatInstruct,
            nCtxTrain: nCtxTrain > 0 ? nCtxTrain : nil,
            parameterCount: parameterCount > 0 ? parameterCount : nil,
            modelDescription: description,
            recommendedMaxContext: recommendedMaxContext,
            recommendedStopSequences: stops,
            composerHints: hints,
            userContextExceedsTraining: nCtxTrain > 0 && userContextLength > UInt32(nCtxTrain)
        )
    }

    private static func detectChatInstruct(model: InstalledModel) -> Bool {
        let haystack = "\(model.name) \(model.filename) \(model.repoId)".lowercased()
        if haystack.contains("phi-2") || haystack.contains("phi2") {
            return haystack.contains("instruct")
        }
        if haystack.contains("base") && !haystack.contains("instruct") {
            return false
        }
        let instructMarkers = ["instruct", "-chat", "chat-", "it-", "-it"]
        return instructMarkers.contains { haystack.contains($0) }
    }

    private static func recommendedContextCap(
        userContextLength: UInt32,
        nCtxTrain: Int,
        systemProfile: MacSystemProfile
    ) -> UInt32 {
        var cap = userContextLength
        if nCtxTrain > 0 {
            cap = min(cap, UInt32(nCtxTrain))
        }
        let ramCap: UInt32 = switch systemProfile.physicalMemoryGB {
        case ..<8: 4096
        case 8..<16: 8192
        case 16..<32: 16384
        default: 32768
        }
        return min(cap, ramCap)
    }
}

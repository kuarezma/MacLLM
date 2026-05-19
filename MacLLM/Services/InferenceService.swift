import Foundation

@MainActor
final class InferenceService: ObservableObject {
    static let shared = InferenceService()

    @Published private(set) var isModelLoaded = false
    @Published private(set) var loadedModelId: String?
    @Published private(set) var isGenerating = false
    @Published private(set) var lastGenerationStats: GenerationStats?
    @Published var settings: InferenceSettings = .default

    private var llamaContext: LlamaContext?
    private var generationTask: Task<Void, Never>?
    private var lastLoadedModel: InstalledModel?
    private var promptCacheSessionId: UUID?
    private var promptCacheFingerprint: String = ""
    private var promptCacheTokenCount: Int = 0

    private static let generationStallSeconds: TimeInterval = 60
    private static let maxEmptyDecodeLoops = 8_192

    private static func modelHaystack(_ model: InstalledModel?) -> String {
        guard let model else { return "" }
        return "\(model.name) \(model.filename) \(model.repoId)".lowercased()
    }

    private static func prefersConservativeKVCache(for model: InstalledModel?) -> Bool {
        let haystack = modelHaystack(model)
        return haystack.contains("qwopus") || haystack.contains("qwen3.5")
            || (model?.repoId == "imported" && haystack.contains("qwopus"))
    }

    func loadModel(_ model: InstalledModel, settingsOverride: InferenceSettings? = nil) async throws {
        await stopGeneration()
        await unloadModel()
        invalidatePromptCache()
        let effectiveSettings = settingsOverride ?? settings
        llamaContext = try await LlamaContext.createContext(
            path: model.localPath,
            settings: effectiveSettings,
            chatTemplateHint: model.chatTemplate,
            mmprojPath: model.mmprojLocalPath
        )
        isModelLoaded = true
        loadedModelId = model.id
        lastLoadedModel = model
        try ModelStore.shared.touchLastUsed(id: model.id)
    }

    func buildLoadedProfile(
        for model: InstalledModel,
        systemProfile: MacSystemProfile
    ) async -> LoadedModelProfile? {
        guard let llamaContext, loadedModelId == model.id else { return nil }
        let resolvedTemplate = await llamaContext.resolvedChatTemplate()
        let meta = await llamaContext.modelMetadata()
        let runtime = await llamaContext.runtimeCapabilities()
        return ModelProfileBuilder.build(
            model: model,
            resolvedTemplate: resolvedTemplate,
            runtimeVision: runtime.vision,
            runtimeAudio: runtime.audio,
            nCtxTrain: meta.nCtxTrain,
            parameterCount: meta.nParams,
            description: meta.description,
            userContextLength: settings.contextLength,
            systemProfile: systemProfile,
            settings: settings
        )
    }

    func unloadModel() async {
        await stopGeneration()
        invalidatePromptCache()

        if let llamaContext {
            await llamaContext.shutdown()
        }
        llamaContext = nil
        isModelLoaded = false
        loadedModelId = nil
    }

    func invalidatePromptCache() {
        promptCacheSessionId = nil
        promptCacheFingerprint = ""
        promptCacheTokenCount = 0
    }

    func clearKVCache() async {
        await llamaContext?.clear()
        invalidatePromptCache()
    }

    func applyRuntimeSettingsIfLoaded() async {
        guard let llamaContext, isModelLoaded else { return }
        await llamaContext.updateRuntimeSettings(settings)
    }

    func stopGeneration() async {
        generationTask?.cancel()
        await llamaContext?.cancel()
        if let generationTask {
            await generationTask.value
        }
        generationTask = nil
        isGenerating = false
    }

    private static func messagesWithSystem(_ messages: [ChatMessage], systemPrompt: String) -> [ChatMessage] {
        let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return messages }
        if messages.contains(where: { $0.role == .system }) { return messages }
        var result = messages
        result.insert(ChatMessage(role: .system, content: trimmed), at: 0)
        return result
    }

    static func messageFingerprint(messages: [ChatMessage]) -> String {
        messages.map { "\($0.id.uuidString):\($0.content.count)" }.joined(separator: "|")
    }

    private func canReusePromptCache(
        sessionId: UUID,
        messages: [ChatMessage],
        promptTokenCount: Int,
        hasMedia: Bool,
        kvPosition: Int32
    ) -> Bool {
        guard settings.usePromptCache, !hasMedia else { return false }
        guard promptCacheSessionId == sessionId,
              promptCacheTokenCount > 0,
              Int(kvPosition) == promptCacheTokenCount,
              promptTokenCount > promptCacheTokenCount else { return false }
        let fingerprint = Self.messageFingerprint(messages: messages)
        return fingerprint.hasPrefix(promptCacheFingerprint) && !promptCacheFingerprint.isEmpty
    }

    func streamResponse(
        messages: [ChatMessage],
        chatTemplate: String,
        sessionId: UUID,
        stopSequences: [String]? = nil,
        forceFullPrefill: Bool = false,
        systemPromptOverride: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let payload = InferenceMessageBuilder.build(messages: messages, sessionId: sessionId)
        let systemPrompt = systemPromptOverride ?? settings.systemPrompt
        let promptMessages = Self.messagesWithSystem(payload.messages, systemPrompt: systemPrompt)
        let mediaPaths = payload.mediaPaths
        guard let llamaContext else {
            return AsyncThrowingStream { $0.finish(throwing: LlamaError.couldNotInitializeContext) }
        }

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                await self.stopGeneration()
                self.generationTask = Task.detached(priority: .userInitiated) {
                    let started = Date()
                    do {
                        await MainActor.run {
                            self.isGenerating = true
                            self.lastGenerationStats = nil
                        }
                        defer {
                            Task { @MainActor in
                                self.isGenerating = false
                            }
                        }

                        let resolvedTemplate = await llamaContext.resolvedChatTemplate()
                        let inferenceSettings = await MainActor.run { self.settings }
                        let stops = stopSequences ?? ChatTemplateResolver.mergedStopSequences(
                            settings: inferenceSettings,
                            template: resolvedTemplate
                        )

                        let prompt = try await llamaContext.applyChatTemplate(
                            messages: promptMessages,
                            templateName: chatTemplate
                        )
                        let promptTokenCount = await llamaContext.countTokens(in: prompt, addBos: true)

                        var emittedOutput = ""
                        var didRetryWithoutFlash = false

                        generationAttempt: for attempt in 0..<3 {
                            var outputFilter = GenerationOutputFilter(stopSequences: stops)
                            emittedOutput = ""

                            let kvPosition = await llamaContext.kvPosition
                            let loadedModel = await MainActor.run { self.lastLoadedModel }
                            let cacheReuseAllowed = await MainActor.run {
                                !forceFullPrefill
                                    && !Self.prefersConservativeKVCache(for: loadedModel)
                                    && self.canReusePromptCache(
                                        sessionId: sessionId,
                                        messages: promptMessages,
                                        promptTokenCount: promptTokenCount,
                                        hasMedia: !mediaPaths.isEmpty,
                                        kvPosition: kvPosition
                                    )
                            }
                            let reuseCache = attempt == 0 && cacheReuseAllowed

                            let reuseCount = await MainActor.run { self.promptCacheTokenCount }

                            do {
                                if reuseCache {
                                    try await llamaContext.completionInit(
                                        text: prompt,
                                        mediaPaths: mediaPaths,
                                        reuseTokenCount: reuseCount
                                    )
                                } else {
                                    await llamaContext.clear()
                                    if attempt == 0 {
                                        await MainActor.run { self.invalidatePromptCache() }
                                    }
                                    try await llamaContext.completionInit(
                                        text: prompt,
                                        mediaPaths: mediaPaths
                                    )
                                }

                                emittedOutput = try await Self.runGenerationLoop(
                                    llamaContext: llamaContext,
                                    outputFilter: &outputFilter,
                                    continuation: continuation
                                )
                                break generationAttempt
                            } catch let error as LlamaError {
                                switch error {
                                case .decodeFailed:
                                    await MainActor.run { self.invalidatePromptCache() }
                                    if attempt == 0 {
                                        await llamaContext.clear()
                                        continue generationAttempt
                                    }
                                    if attempt == 1,
                                       inferenceSettings.flashAttention,
                                       !didRetryWithoutFlash,
                                       let model = await MainActor.run(body: { self.lastLoadedModel }) {
                                        didRetryWithoutFlash = true
                                        var relaxed = inferenceSettings
                                        relaxed.flashAttention = false
                                        try await self.loadModel(model, settingsOverride: relaxed)
                                        continue generationAttempt
                                    }
                                    throw error
                                case .generationStalled, .generationEmpty:
                                    await MainActor.run { self.invalidatePromptCache() }
                                    if attempt < 2 {
                                        await llamaContext.clear()
                                        continue generationAttempt
                                    }
                                    throw error
                                default:
                                    throw error
                                }
                            }
                        }

                        let snapshot = await llamaContext.generationSnapshot()
                        let savedOutputTokens = snapshot.outputTokens
                        let finalKVPosition = await llamaContext.kvPosition
                        let savedEmitted = emittedOutput
                        guard ControlTokenSanitizer.hasMeaningfulText(savedEmitted) else {
                            throw LlamaError.generationEmpty
                        }
                        let duration = max(Date().timeIntervalSince(started), 0.001)
                        let tps = Double(savedOutputTokens) / duration

                        await MainActor.run {
                            self.lastGenerationStats = GenerationStats(
                                outputTokens: savedOutputTokens,
                                tokensPerSecond: tps,
                                durationSeconds: duration
                            )
                            if inferenceSettings.usePromptCache,
                               savedOutputTokens > 0,
                               promptTokenCount + savedOutputTokens == Int(finalKVPosition) {
                                self.promptCacheSessionId = sessionId
                                self.promptCacheFingerprint = Self.messageFingerprint(messages: promptMessages)
                                self.promptCacheTokenCount = Int(finalKVPosition)
                            }
                        }
                        continuation.finish()
                    } catch {
                        await self.clearKVCache()
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    private static func runGenerationLoop(
        llamaContext: LlamaContext,
        outputFilter: inout GenerationOutputFilter,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws -> String {
        var emittedOutput = ""
        var lastProgress = Date()
        var emptyLoops = 0
        let started = Date()

        while await !llamaContext.is_done {
            try Task.checkCancellation()
            let chunk = try await llamaContext.completionLoop()

            if chunk.isEmpty {
                emptyLoops += 1
                if emptyLoops >= maxEmptyDecodeLoops
                    || Date().timeIntervalSince(lastProgress) >= generationStallSeconds
                    || Date().timeIntervalSince(started) >= generationStallSeconds * 2 {
                    throw LlamaError.generationStalled
                }
                continue
            }
            emptyLoops = 0

            let safe = outputFilter.push(chunk)
            if !safe.isEmpty {
                emittedOutput += safe
                continuation.yield(safe)
                lastProgress = Date()
            }
        }

        let tail = outputFilter.finish()
        if !tail.isEmpty {
            emittedOutput += tail
            continuation.yield(tail)
        }
        return emittedOutput
    }

    func countPromptTokens(
        messages: [ChatMessage],
        chatTemplate: String,
        sessionId: UUID,
        systemPromptOverride: String? = nil
    ) async throws -> Int {
        guard let llamaContext else {
            throw LlamaError.couldNotInitializeContext
        }
        let payload = InferenceMessageBuilder.build(messages: messages, sessionId: sessionId)
        let systemPrompt = systemPromptOverride ?? settings.systemPrompt
        let promptMessages = Self.messagesWithSystem(payload.messages, systemPrompt: systemPrompt)
        let prompt = try await llamaContext.applyChatTemplate(
            messages: promptMessages,
            templateName: chatTemplate
        )
        return await llamaContext.countTokens(in: prompt, addBos: true)
    }
}

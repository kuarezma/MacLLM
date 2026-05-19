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
    private var promptCacheSessionId: UUID?
    private var promptCacheText: String = ""
    private var promptCacheFingerprint: String = ""

    func loadModel(_ model: InstalledModel) async throws {
        await stopGeneration()
        await unloadModel()
        invalidatePromptCache()
        llamaContext = try await LlamaContext.createContext(
            path: model.localPath,
            settings: settings,
            chatTemplateHint: model.chatTemplate,
            mmprojPath: model.mmprojLocalPath
        )
        isModelLoaded = true
        loadedModelId = model.id
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
        promptCacheText = ""
        promptCacheFingerprint = ""
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

    func updatePromptCache(
        sessionId: UUID,
        messages: [ChatMessage],
        chatTemplate: String
    ) async {
        guard settings.usePromptCache, let llamaContext else { return }
        do {
            let promptMessages = Self.messagesWithSystem(messages, systemPrompt: settings.systemPrompt)
            let prompt = try await llamaContext.applyChatTemplate(
                messages: promptMessages,
                templateName: chatTemplate
            )
            promptCacheSessionId = sessionId
            promptCacheText = prompt
            promptCacheFingerprint = Self.messageFingerprint(messages: promptMessages)
        } catch {
            invalidatePromptCache()
        }
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
        prompt: String,
        hasMedia: Bool
    ) -> Bool {
        guard settings.usePromptCache, !hasMedia else { return false }
        guard promptCacheSessionId == sessionId,
              !promptCacheText.isEmpty,
              prompt.hasPrefix(promptCacheText),
              prompt.count > promptCacheText.count else { return false }
        let fingerprint = Self.messageFingerprint(messages: messages)
        return fingerprint.hasPrefix(promptCacheFingerprint) || promptCacheFingerprint.isEmpty
    }

    func streamResponse(
        messages: [ChatMessage],
        chatTemplate: String,
        sessionId: UUID,
        stopSequences: [String]? = nil,
        forceFullPrefill: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        let payload = InferenceMessageBuilder.build(messages: messages, sessionId: sessionId)
        let promptMessages = Self.messagesWithSystem(payload.messages, systemPrompt: settings.systemPrompt)
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
                        var outputFilter = GenerationOutputFilter(stopSequences: stops)

                        let prompt = try await llamaContext.applyChatTemplate(
                            messages: promptMessages,
                            templateName: chatTemplate
                        )

                        let reuseCache = await MainActor.run {
                            !forceFullPrefill
                                && self.canReusePromptCache(
                                    sessionId: sessionId,
                                    messages: promptMessages,
                                    prompt: prompt,
                                    hasMedia: !mediaPaths.isEmpty
                                )
                        }

                        if reuseCache {
                            let cached = await MainActor.run { self.promptCacheText }
                            try await llamaContext.completionInit(
                                text: prompt,
                                mediaPaths: mediaPaths,
                                cachedPrefix: cached
                            )
                        } else {
                            await llamaContext.clear()
                            try await llamaContext.completionInit(text: prompt, mediaPaths: mediaPaths)
                        }

                        while await !llamaContext.is_done {
                            try Task.checkCancellation()
                            let chunk = try await llamaContext.completionLoop()
                            guard !chunk.isEmpty else { continue }

                            let safe = outputFilter.push(chunk)
                            if !safe.isEmpty {
                                continuation.yield(safe)
                            }
                        }

                        let tail = outputFilter.finish()
                        if !tail.isEmpty {
                            continuation.yield(tail)
                        }

                        let snapshot = await llamaContext.generationSnapshot()
                        let duration = max(Date().timeIntervalSince(started), 0.001)
                        let tps = Double(snapshot.outputTokens) / duration
                        await MainActor.run {
                            self.lastGenerationStats = GenerationStats(
                                outputTokens: snapshot.outputTokens,
                                tokensPerSecond: tps,
                                durationSeconds: duration
                            )
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    func countPromptTokens(
        messages: [ChatMessage],
        chatTemplate: String,
        sessionId: UUID
    ) async throws -> Int {
        guard let llamaContext else {
            throw LlamaError.couldNotInitializeContext
        }
        let payload = InferenceMessageBuilder.build(messages: messages, sessionId: sessionId)
        let promptMessages = Self.messagesWithSystem(payload.messages, systemPrompt: settings.systemPrompt)
        let prompt = try await llamaContext.applyChatTemplate(
            messages: promptMessages,
            templateName: chatTemplate
        )
        return await llamaContext.countTokens(in: prompt, addBos: true)
    }
}

import Foundation
import OSLog

@MainActor
final class InferenceService: ObservableObject {
    static let shared = InferenceService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacLLM", category: "Inference")

    @Published private(set) var isModelLoaded = false
    @Published private(set) var loadedModelId: String?
    @Published private(set) var isGenerating = false
    @Published private(set) var isStoppingGeneration = false
    @Published private(set) var lastGenerationStats: GenerationStats?
    @Published private(set) var modelLoadingStage: String?
    @Published var settings: InferenceSettings = .default

    private var llamaContext: LlamaContext?
    private var generationTask: Task<Void, Never>?
    private var generationRunID: UInt64 = 0
    private var lastLoadedModel: InstalledModel?
    private var promptCacheSessionId: UUID?
    private var promptCacheFingerprint: String = ""
    private var promptCacheTokenCount: Int = 0

    private static let generationStallSeconds: TimeInterval = 60
    private static let maxEmptyDecodeLoops = 8_192
    private static func elapsedMilliseconds(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }

    func loadModel(_ model: InstalledModel, settingsOverride: InferenceSettings? = nil) async throws {
        let startedAt = Date()
        logger.info("Model load start id=\(model.id) name=\(model.name)")
        defer { modelLoadingStage = nil }
        modelLoadingStage = "Mevcut model kapatiliyor"
        await stopGeneration()
        await unloadModel()
        invalidatePromptCache()
        let effectiveSettings = settingsOverride ?? settings
        modelLoadingStage = "Model dosyasi yukleniyor"
        let path = model.localPath
        let chatTemplateHint = model.chatTemplate
        let mmprojPath = model.mmprojLocalPath
        let loadedContext = try await Task.detached(priority: .userInitiated) {
            try LlamaContext.createContext(
                path: path,
                settings: effectiveSettings,
                chatTemplateHint: chatTemplateHint,
                mmprojPath: mmprojPath
            )
        }.value
        if Task.isCancelled {
            await loadedContext.shutdown()
            logger.notice("Model load cancelled id=\(model.id) after=\(Self.elapsedMilliseconds(since: startedAt))ms")
            throw CancellationError()
        }
        modelLoadingStage = "Calisma profili hazirlaniyor"
        llamaContext = loadedContext
        isModelLoaded = true
        loadedModelId = model.id
        lastLoadedModel = model
        try ModelStore.shared.touchLastUsed(id: model.id)
        logger.info("Model load success id=\(model.id) elapsed=\(Self.elapsedMilliseconds(since: startedAt))ms")
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
        let startedAt = Date()
        let task = generationTask
        guard task != nil || isGenerating || isStoppingGeneration else { return }
        logger.debug("Stop generation requested hasTask=\(task != nil)")
        isStoppingGeneration = true
        generationRunID &+= 1
        generationTask = nil
        task?.cancel()
        await llamaContext?.cancel()
        if let task {
            await task.value
        }
        isGenerating = false
        isStoppingGeneration = false
        logger.debug("Stop generation finished elapsed=\(Self.elapsedMilliseconds(since: startedAt))ms")
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
                self.generationRunID &+= 1
                let runID = self.generationRunID
                self.logger.info("Generation start run=\(runID) session=\(sessionId.uuidString)")
                self.isStoppingGeneration = false
                self.isGenerating = true
                self.lastGenerationStats = nil
                self.generationTask = Task.detached(priority: .userInitiated) {
                    let started = Date()
                    do {
                        defer {
                            Task { @MainActor in
                                guard self.generationRunID == runID else { return }
                                self.isGenerating = false
                                self.isStoppingGeneration = false
                                self.generationTask = nil
                            }
                        }

                        let resolvedTemplate = await llamaContext.resolvedChatTemplate()
                        var inferenceSettings = await MainActor.run { self.settings }

                        let prompt = try await llamaContext.applyChatTemplate(
                            messages: promptMessages,
                            templateName: chatTemplate
                        )
                        let promptTokenCount = await llamaContext.countTokens(in: prompt, addBos: true)

                        var emittedOutput = ""
                        var didRetryWithoutFlash = false
                        var useQwopusNarrowStops = false
                        let initialModel = await MainActor.run { self.lastLoadedModel }
                        let maxAttempts = ModelFamily.isQwopusFamily(initialModel) ? 4 : 3

                        generationAttempt: for attempt in 0..<maxAttempts {
                            self.logger.debug("Generation attempt run=\(runID) attempt=\(attempt + 1)")
                            emittedOutput = ""

                            let loadedModel = await MainActor.run { self.lastLoadedModel }
                            let attemptStops: [String]
                            if useQwopusNarrowStops {
                                attemptStops = ChatTemplateResolver.qwopusGenerationStopSequences
                            } else {
                                attemptStops = stopSequences ?? ChatTemplateResolver.mergedStopSequences(
                                    settings: inferenceSettings,
                                    template: resolvedTemplate
                                )
                            }
                            var outputFilter = GenerationOutputFilter(stopSequences: attemptStops)

                            let kvPosition = await llamaContext.kvPosition
                            let cacheReuseAllowed = await MainActor.run {
                                !forceFullPrefill
                                    && !ModelFamily.prefersConservativeKVCache(for: loadedModel)
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
                            } catch let error as LlamaError {
                                switch error {
                                case .decodeFailed:
                                    await MainActor.run { self.invalidatePromptCache() }
                                    if attempt == 0 {
                                        await llamaContext.clear()
                                        if ModelFamily.isQwopusFamily(loadedModel),
                                           inferenceSettings.flashAttention,
                                           !didRetryWithoutFlash,
                                           let model = loadedModel {
                                            didRetryWithoutFlash = true
                                            self.logger.notice(
                                                "Decode failed run=\(runID), Qwopus flash attention off retry"
                                            )
                                            var relaxed = inferenceSettings
                                            relaxed.flashAttention = false
                                            try await self.loadModel(model, settingsOverride: relaxed)
                                            inferenceSettings = await MainActor.run { self.settings }
                                        }
                                        continue generationAttempt
                                    }
                                    if !didRetryWithoutFlash,
                                       inferenceSettings.flashAttention,
                                       let model = loadedModel {
                                        didRetryWithoutFlash = true
                                        self.logger.notice(
                                            "Decode failed run=\(runID), retrying with flash attention off"
                                        )
                                        var relaxed = inferenceSettings
                                        relaxed.flashAttention = false
                                        try await self.loadModel(model, settingsOverride: relaxed)
                                        inferenceSettings = await MainActor.run { self.settings }
                                        continue generationAttempt
                                    }
                                    throw error
                                case .generationStalled, .generationEmpty:
                                    await MainActor.run { self.invalidatePromptCache() }
                                    if attempt + 1 < maxAttempts {
                                        self.logger.notice(
                                            "Generation retry run=\(runID) reason=\(String(describing: error)) nextAttempt=\(attempt + 2)"
                                        )
                                        await llamaContext.clear()
                                        useQwopusNarrowStops = ModelFamily.isQwopusFamily(loadedModel)
                                        continue generationAttempt
                                    }
                                    self.logger.error(
                                        "Generation terminal failure run=\(runID) reason=\(String(describing: error))"
                                    )
                                    throw error
                                default:
                                    throw error
                                }
                            }

                            if ControlTokenSanitizer.hasMeaningfulText(emittedOutput) {
                                break generationAttempt
                            }

                            guard ModelFamily.isQwopusFamily(loadedModel), attempt + 1 < maxAttempts else {
                                throw LlamaError.generationEmpty
                            }

                            useQwopusNarrowStops = true
                            await MainActor.run { self.invalidatePromptCache() }
                            await llamaContext.clear()
                            if inferenceSettings.flashAttention,
                               !didRetryWithoutFlash,
                               let model = loadedModel {
                                didRetryWithoutFlash = true
                                self.logger.notice(
                                    "Empty Qwopus output run=\(runID), reloading with flash attention off"
                                )
                                var relaxed = inferenceSettings
                                relaxed.flashAttention = false
                                try await self.loadModel(model, settingsOverride: relaxed)
                                inferenceSettings = await MainActor.run { self.settings }
                            } else {
                                self.logger.notice(
                                    "Empty Qwopus output run=\(runID), narrow-stop retry attempt=\(attempt + 2)"
                                )
                            }
                        }

                        let snapshot = await llamaContext.generationSnapshot()
                        let savedOutputTokens = snapshot.outputTokens
                        let finalKVPosition = await llamaContext.kvPosition
                        let duration = max(Date().timeIntervalSince(started), 0.001)
                        let tps = Double(savedOutputTokens) / duration
                        self.logger.info(
                            "Generation success run=\(runID) tokens=\(savedOutputTokens) elapsed=\(Int(duration * 1000))ms tps=\(tps)"
                        )

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
                        self.logger.error("Generation failure run=\(runID) error=\(String(describing: error))")
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

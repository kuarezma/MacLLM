import Foundation

@MainActor
final class InferenceService: ObservableObject {
    static let shared = InferenceService()

    @Published private(set) var isModelLoaded = false
    @Published private(set) var loadedModelId: String?
    @Published private(set) var isGenerating = false
    @Published var settings: InferenceSettings = .default

    private var llamaContext: LlamaContext?
    private var generationTask: Task<Void, Never>?

    func loadModel(_ model: InstalledModel) async throws {
        await stopGeneration()
        await unloadModel()
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

    func unloadModel() async {
        await stopGeneration()

        if let llamaContext {
            await llamaContext.shutdown()
        }
        llamaContext = nil
        isModelLoaded = false
        loadedModelId = nil
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

    func streamResponse(
        messages: [ChatMessage],
        chatTemplate: String,
        sessionId: UUID
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
                do {
                    await MainActor.run { self.isGenerating = true }
                    defer {
                        Task { @MainActor in
                            self.isGenerating = false
                        }
                    }

                    let resolvedTemplate = await llamaContext.resolvedChatTemplate()
                    let inferenceSettings = await MainActor.run { self.settings }
                    let stops = ChatTemplateResolver.mergedStopSequences(
                        settings: inferenceSettings,
                        template: resolvedTemplate
                    )
                    var outputFilter = GenerationOutputFilter(stopSequences: stops)

                    let prompt = try await llamaContext.applyChatTemplate(
                        messages: promptMessages,
                        templateName: chatTemplate
                    )
                    await llamaContext.clear()
                    try await llamaContext.completionInit(text: prompt, mediaPaths: mediaPaths)

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
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                }
            }
        }
    }
}

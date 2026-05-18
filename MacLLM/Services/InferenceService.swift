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
        unloadModel()
        llamaContext = try await LlamaContext.createContext(path: model.localPath, settings: settings)
        isModelLoaded = true
        loadedModelId = model.id
        try ModelStore.shared.touchLastUsed(id: model.id)
    }

    func unloadModel() {
        generationTask?.cancel()
        generationTask = nil
        llamaContext = nil
        isModelLoaded = false
        loadedModelId = nil
        isGenerating = false
    }

    func stopGeneration() {
        generationTask?.cancel()
        Task {
            await llamaContext?.cancel()
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

    func streamResponse(
        messages: [ChatMessage],
        chatTemplate: String
    ) -> AsyncThrowingStream<String, Error> {
        let promptMessages = Self.messagesWithSystem(messages, systemPrompt: settings.systemPrompt)
        let stops = settings.stopSequences.filter { !$0.isEmpty }
        guard let llamaContext else {
            return AsyncThrowingStream { $0.finish(throwing: LlamaError.couldNotInitializeContext) }
        }

        return AsyncThrowingStream { continuation in
            generationTask = Task.detached(priority: .userInitiated) {
                do {
                    await MainActor.run { self.isGenerating = true }
                    defer {
                        Task {
                            await MainActor.run { self.isGenerating = false }
                            await llamaContext.clear()
                        }
                    }

                    let prompt = try await llamaContext.applyChatTemplate(
                        messages: promptMessages,
                        templateName: chatTemplate
                    )
                    try await llamaContext.completionInit(text: prompt)

                    var generated = ""
                    var emittedCount = 0

                    while await !llamaContext.is_done {
                        try Task.checkCancellation()
                        let chunk = try await llamaContext.completionLoop()
                        guard !chunk.isEmpty else { continue }

                        generated += chunk
                        var hitStop = false
                        for stop in stops where generated.contains(stop) {
                            if let range = generated.range(of: stop) {
                                let trimmed = String(generated[..<range.lowerBound])
                                if trimmed.count > emittedCount {
                                    let start = trimmed.index(trimmed.startIndex, offsetBy: emittedCount)
                                    continuation.yield(String(trimmed[start...]))
                                }
                                hitStop = true
                                break
                            }
                        }
                        if hitStop { break }
                        continuation.yield(chunk)
                        emittedCount = generated.count
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

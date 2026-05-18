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

    func streamResponse(
        messages: [ChatMessage],
        chatTemplate: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            generationTask = Task {
                do {
                    guard let llamaContext else {
                        continuation.finish(throwing: LlamaError.couldNotInitializeContext)
                        return
                    }

                    isGenerating = true
                    defer {
                        isGenerating = false
                        Task { await llamaContext.clear() }
                    }

                    let prompt = try await llamaContext.applyChatTemplate(messages: messages, templateName: chatTemplate)
                    try await llamaContext.completionInit(text: prompt)

                    while await !llamaContext.is_done {
                        try Task.checkCancellation()
                        let chunk = try await llamaContext.completionLoop()
                        if !chunk.isEmpty {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class StreamingTextBuffer {
    var text: String = ""
    var sessionId: UUID?
    var messageId: UUID?
    var isActive: Bool = false

    private var pendingText = ""
    private var publishTask: Task<Void, Never>?

    func begin(sessionId: UUID, messageId: UUID) {
        publishTask?.cancel()
        publishTask = nil
        self.sessionId = sessionId
        self.messageId = messageId
        pendingText = ""
        text = ""
        isActive = true
    }

    func append(_ chunk: String) {
        guard isActive, !chunk.isEmpty else { return }
        pendingText += chunk
        publishTask?.cancel()
        publishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 33_000_000)
            guard !Task.isCancelled, isActive else { return }
            text = pendingText
            publishTask = nil
        }
    }

    func finish() -> String {
        publishTask?.cancel()
        publishTask = nil
        text = pendingText
        let result = text
        isActive = false
        return result
    }

    func reset() {
        publishTask?.cancel()
        publishTask = nil
        pendingText = ""
        text = ""
        sessionId = nil
        messageId = nil
        isActive = false
    }
}

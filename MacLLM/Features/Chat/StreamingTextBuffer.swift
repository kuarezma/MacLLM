import Foundation
import Observation

@MainActor
@Observable
final class StreamingTextBuffer {
    var text: String = ""
    var sessionId: UUID?
    var messageId: UUID?
    var isActive: Bool = false

    func begin(sessionId: UUID, messageId: UUID) {
        self.sessionId = sessionId
        self.messageId = messageId
        text = ""
        isActive = true
    }

    func append(_ chunk: String) {
        guard isActive, !chunk.isEmpty else { return }
        text += chunk
    }

    func finish() -> String {
        let result = text
        isActive = false
        return result
    }

    func reset() {
        text = ""
        sessionId = nil
        messageId = nil
        isActive = false
    }
}

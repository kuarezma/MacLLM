import Foundation

/// Paylaşılan `StreamingTextBuffer` ve `AppModel` örneği (SwiftUI kökünde tek buffer).
@MainActor
final class AppShell {
    let streamingBuffer: StreamingTextBuffer
    let appModel: AppModel

    init() {
        let buffer = StreamingTextBuffer()
        streamingBuffer = buffer
        appModel = AppModel(streamingBuffer: buffer)
    }
}

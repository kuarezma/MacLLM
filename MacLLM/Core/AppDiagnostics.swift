import Foundation
import OSLog

enum AppDiagnostics {
    static let subsystem = Bundle.main.bundleIdentifier ?? "MacLLM"

    static let inference = Logger(subsystem: subsystem, category: "Inference")
    static let downloads = Logger(subsystem: subsystem, category: "Downloads")
    static let appModel = Logger(subsystem: subsystem, category: "AppModel")

    static func elapsedMilliseconds(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }
}

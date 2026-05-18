import AppKit

extension Notification.Name {
    static let macLLMOpenSettings = Notification.Name("macLLMOpenSettings")
}

enum AppSettingsOpener {
    @MainActor
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .macLLMOpenSettings, object: nil)
    }
}

import AppKit

enum AppSettingsOpener {
    @MainActor
    static func open() {
        NSApp.activate(ignoringOtherApps: true)

        let settingsSelector = Selector(("showSettingsWindow:"))
        if NSApp.responds(to: settingsSelector) {
            NSApp.sendAction(settingsSelector, to: nil, from: nil)
            return
        }

        let prefsSelector = Selector(("showPreferencesWindow:"))
        if NSApp.responds(to: prefsSelector) {
            NSApp.sendAction(prefsSelector, to: nil, from: nil)
            return
        }

        _ = focusExistingSettingsWindow()
    }

    @MainActor
    private static func focusExistingSettingsWindow() -> Bool {
        let keywords = ["settings", "ayarlar", "preferences"]
        for window in NSApp.windows where window.isVisible {
            let title = window.title.lowercased()
            if keywords.contains(where: { title.contains($0) }) {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return false
    }
}

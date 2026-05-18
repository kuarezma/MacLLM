import AppKit

enum AppSettingsOpener {
    @MainActor
    static func open() {
        let settingsSelector = Selector(("showSettingsWindow:"))
        let preferencesSelector = Selector(("showPreferencesWindow:"))
        if NSApp.responds(to: settingsSelector) {
            NSApp.sendAction(settingsSelector, to: nil, from: nil)
        } else {
            NSApp.sendAction(preferencesSelector, to: nil, from: nil)
        }
    }
}

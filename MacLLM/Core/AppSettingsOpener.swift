import AppKit
import SwiftUI

enum AppSettingsOpener {
    private static var openHandler: (@MainActor () -> Void)?

    @MainActor
    static func register(_ handler: @escaping @MainActor () -> Void) {
        openHandler = handler
    }

    @MainActor
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let openHandler {
            openHandler()
            return
        }

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

struct SettingsOpenerRegistrar: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                AppSettingsOpener.register { openSettings() }
            }
    }
}

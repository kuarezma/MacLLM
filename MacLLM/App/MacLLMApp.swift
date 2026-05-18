import SwiftUI

@main
struct MacLLMApp: App {
    @State private var appModel = AppModel()
    @StateObject private var inferenceService = InferenceService.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appModel)
                .environmentObject(inferenceService)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni Sohbet") {
                    appModel.newChat()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .appSettings) {
                Button("Model Kataloğu…") {
                    appModel.showCatalog = true
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(appModel)
                .environmentObject(inferenceService)
        }
    }
}

import SwiftUI
import UserNotifications

@main
struct MacLLMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()
    @State private var appUpdate = AppUpdateController.shared
    @StateObject private var inferenceService = InferenceService.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appModel)
                .environment(appUpdate)
                .environmentObject(inferenceService)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    AppDelegate.appModel = appModel
                }
                .task {
                    await requestNotificationPermissionIfNeeded()
                    if appUpdate.autoCheckEnabled {
                        await appUpdate.checkForUpdates()
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni Sohbet") {
                    Task { await appModel.newChat() }
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .sidebar) {
                Button("Sohbetlerde Ara") {
                    NotificationCenter.default.post(name: .focusSidebarSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button("Yeni Proje") {
                    appModel.showNewProjectSheet = true
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
            CommandGroup(after: .appSettings) {
                Button("Model Ekle…") {
                    appModel.showCatalog = true
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(appModel)
                .environment(appUpdate)
                .environmentObject(inferenceService)
        }
    }

    private func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}

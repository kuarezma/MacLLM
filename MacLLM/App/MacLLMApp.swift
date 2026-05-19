import SwiftUI
import UserNotifications

@main
struct MacLLMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var shell = AppShell()
    @State private var appUpdate = AppUpdateController.shared
    @StateObject private var inferenceService = InferenceService.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(shell.appModel)
                .environment(shell.streamingBuffer)
                .environment(appUpdate)
                .environmentObject(inferenceService)
                .frame(minWidth: 960, minHeight: 640)
                .tint(AppTheme.accent)
                .onAppear {
                    AppDelegate.appModel = shell.appModel
                }
                .task {
                    await requestNotificationPermissionIfNeeded()
                    if appUpdate.autoCheckEnabled {
                        await appUpdate.checkForUpdates()
                    }
                }
                .background(SettingsOpenerRegistrar())
        }
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Yeni Sohbet") {
                    Task { await shell.appModel.newChat() }
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .sidebar) {
                Button("Sohbetlerde Ara") {
                    NotificationCenter.default.post(name: .focusSidebarSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button("Yeni Proje") {
                    shell.appModel.showNewProjectSheet = true
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
            CommandGroup(after: .appSettings) {
                Button("Model Ekle…") {
                    shell.appModel.showCatalog = true
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(shell.appModel)
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

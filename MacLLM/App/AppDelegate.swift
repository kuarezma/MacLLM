import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var appModel: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await performGracefulShutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func performGracefulShutdown() async {
        AppShutdown.isShuttingDown = true

        HuggingFaceDownloadService.shared.cancelAllDownloads()

        if let appModel = Self.appModel {
            if InferenceService.shared.isGenerating {
                appModel.stopGeneration()
                try? await Task.sleep(for: .milliseconds(200))
            }
            if !appModel.currentSession.messages.isEmpty {
                try? await appModel.saveCurrentSession()
            }
        }

        await InferenceService.shared.unloadModel()
    }
}

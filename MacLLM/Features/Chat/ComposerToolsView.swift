import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ComposerToolsUIState: ObservableObject {
    @Published var webSearchEnabled = WebSearchPreferences.isEnabled
}

struct ComposerToolsView: View {
    @EnvironmentObject private var appModel: AppModel
    var isDisabled: Bool = false
    @StateObject private var ui = ComposerToolsUIState()

    var body: some View {
        HStack(spacing: 2) {
            Button {
                ui.webSearchEnabled.toggle()
                WebSearchPreferences.isEnabled = ui.webSearchEnabled
            } label: {
                Image(systemName: ui.webSearchEnabled ? "globe.americas.fill" : "globe")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ui.webSearchEnabled ? AppTheme.accent : AppTheme.secondaryText)
            .disabled(isDisabled)
            .help(ui.webSearchEnabled ? "Web araması açık — sonraki mesaja bağlam eklenir" : "Web araması")

            Menu {
                Button {
                    appModel.showSystemPromptSheet = true
                } label: {
                    Label("Sistem istemi…", systemImage: "text.quote")
                }
                Button {
                    exportChat()
                } label: {
                    Label("Sohbeti dışa aktar…", systemImage: "square.and.arrow.up")
                }
                .disabled(appModel.currentSession.messages.isEmpty)
                Button {
                    importChat()
                } label: {
                    Label("Sohbeti içe aktar…", systemImage: "square.and.arrow.down")
                }
                Divider()
                Button {
                    AppSettingsOpener.open()
                } label: {
                    Label("Ayarlar", systemImage: "gearshape")
                }
                Button {
                    Task { await appModel.newChat() }
                } label: {
                    Label("Yeni sohbet", systemImage: "square.and.pencil")
                }
            } label: {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(AppTheme.secondaryText)
            .disabled(isDisabled)
            .help("Araçlar")
        }
        .onAppear {
            ui.webSearchEnabled = WebSearchPreferences.isEnabled
        }
    }

    @MainActor
    private func exportChat() {
        let markdown = appModel.exportCurrentSessionMarkdown()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(appModel.currentSession.title).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                appModel.setStatusMessage("Sohbet dışa aktarıldı")
            } catch {
                appModel.reportUserFacingError(error, context: "Sohbet dışa aktarılamadı")
            }
        }
    }

    @MainActor
    private func importChat() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await appModel.importChat(from: url) }
        }
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ComposerToolsView: View {
    @Environment(AppModel.self) private var appModel
    var isDisabled: Bool = false
    @State private var webSearchEnabled = WebSearchPreferences.isEnabled

    var body: some View {
        HStack(spacing: 2) {
            Button {
                webSearchEnabled.toggle()
                WebSearchPreferences.isEnabled = webSearchEnabled
            } label: {
                Image(systemName: webSearchEnabled ? "globe.americas.fill" : "globe")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(webSearchEnabled ? AppTheme.accent : AppTheme.secondaryText)
            .disabled(isDisabled)
            .help(webSearchEnabled ? "Web araması açık — sonraki mesaja bağlam eklenir" : "Web araması")

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
            webSearchEnabled = WebSearchPreferences.isEnabled
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
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
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
